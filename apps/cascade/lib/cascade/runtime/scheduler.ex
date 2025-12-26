defmodule Cascade.Runtime.Scheduler do
  @moduledoc """
  The Scheduler orchestrates job execution lifecycles.

  Responsibilities:
  - Manual job triggering
  - Creating Job records in Postgres
  - Initializing job state in StateManager
  - Determining which tasks are ready to run based on dependencies
  - Sending tasks to the Executor for dispatch
  - Handling task completion events and scheduling next tasks
  - Marking jobs as complete when all tasks finish

  Future:  - Cron-based scheduling (Phase 5)
  """

  use GenServer
  require Logger

  alias Cascade.Workflows
  alias Cascade.Runtime.{StateManager, Executor}
  alias Cascade.DSL.Validator
  alias Cascade.Events

  ## Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Manually triggers a job for a given DAG.

  Creates a Job record, initializes state, and starts execution.
  """
  def trigger_job(dag_id, triggered_by, context \\ %{}) do
    GenServer.call(__MODULE__, {:trigger_job, dag_id, triggered_by, context})
  end

  @doc """
  Handles task completion and schedules next tasks.
  """
  def handle_task_completion(job_id, task_id, result) do
    GenServer.cast(__MODULE__, {:task_completed, job_id, task_id, result})
  end

  @doc """
  Handles task failure.
  """
  def handle_task_failure(job_id, task_id, error) do
    GenServer.cast(__MODULE__, {:task_failed, job_id, task_id, error})
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    # Subscribe to task events
    Phoenix.PubSub.subscribe(Cascade.PubSub, Events.scheduler_triggers_topic())

    Logger.info("Scheduler started")

    {:ok, %{}}
  end

  @impl true
  def handle_call({:trigger_job, dag_id, triggered_by, context}, _from, state) do
    case Workflows.get_dag!(dag_id) do
      nil ->
        {:reply, {:error, :dag_not_found}, state}

      dag ->
        # Validate the DAG
        case Validator.validate(dag.definition) do
          {:ok, _} ->
            # Create Job in Postgres
            {:ok, job} =
              Workflows.create_job(%{
                dag_id: dag.id,
                status: :running,
                triggered_by: triggered_by,
                started_at: DateTime.utc_now(),
                context: context
              })

            # Create TaskExecution records for all tasks
            create_task_executions(job, dag.definition)

            # Initialize job state in StateManager
            dag_definition_with_id = Map.put(dag.definition, "dag_id", dag.id)
            {:ok, _job_state} = StateManager.create_job_state(job.id, dag_definition_with_id)

            # Publish job event
            publish_job_event(job.id, dag.id, :running)

            # Find and dispatch ready tasks
            dispatch_ready_tasks(job.id, dag.definition)

            Logger.info("Triggered job_id=#{job.id} for dag=#{dag.name}")

            {:reply, {:ok, job}, state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  rescue
    e ->
      Logger.error("Failed to trigger job: #{inspect(e)}")
      {:reply, {:error, e}, state}
  end

  @impl true
  def handle_cast({:task_completed, job_id, task_id, result}, state) do
    Logger.info("Task completed: job_id=#{job_id}, task_id=#{task_id}")

    # Update task status
    StateManager.update_task_status(job_id, task_id, :success, result: result)

    # Check if job is complete
    case StateManager.get_job_state(job_id) do
      {:ok, job_state} ->
        if job_complete?(job_state) do
          complete_job(job_id, job_state)
        else
          if all_remaining_tasks_blocked?(job_state) do
            Logger.error(
              "All remaining tasks blocked for job #{job_id} - marking blocked tasks and failing job"
            )

            mark_blocked_tasks_as_upstream_failed(job_id, job_state)
            complete_job(job_id, job_state)
          else
            # Dispatch next ready tasks
            dispatch_ready_tasks(job_id, job_state.dag_definition)
          end
        end

      {:error, _} ->
        Logger.warning("Job state not found for job_id=#{job_id}")
    end

    {:noreply, state}
  end

  @impl true
  def handle_cast({:task_failed, job_id, task_id, error}, state) do
    Logger.error("Task failed: job_id=#{job_id}, task_id=#{task_id}, error=#{inspect(error)}")

    # Check if we should retry this task
    case StateManager.get_job_state(job_id) do
      {:ok, job_state} ->
        # Get task config to check retry settings
        task_config = find_task_config(job_state.dag_definition, task_id)
        max_retries = task_config["config"]["retry"] || 0

        # Get current retry count from Postgres
        task_execution = get_task_execution(job_id, task_id)
        current_retry_count = task_execution.retry_count

        if current_retry_count < max_retries do
          # Retry the task
          new_retry_count = current_retry_count + 1

          Logger.warning(
            "Retrying task #{task_id} (attempt #{new_retry_count + 1}/#{max_retries + 1}) for job #{job_id}"
          )

          # Update retry count in Postgres
          Workflows.update_task_execution(task_execution, %{
            retry_count: new_retry_count,
            error: "Attempt #{current_retry_count + 1} failed: #{error}. Retrying..."
          })

          # Re-dispatch the task
          completed_tasks = MapSet.to_list(job_state.completed_tasks)

          task_context =
            build_task_context(job_id, task_id, job_state.dag_definition, completed_tasks)

          Executor.dispatch_task(job_id, task_id, task_config, task_context)
        else
          # No more retries, mark as failed
          if max_retries > 0 do
            Logger.error("Task #{task_id} failed after #{max_retries} retries for job #{job_id}")
          end

          # Update task status to failed
          StateManager.update_task_status(job_id, task_id, :failed, error: error)

          # Re-fetch job state after updating task status
          case StateManager.get_job_state(job_id) do
            {:ok, updated_job_state} ->
              # Check if job is complete (all tasks finished)
              if job_complete?(updated_job_state) do
                # All tasks are done, finalize the job
                Logger.info("Job #{job_id} complete with failures")
                complete_job(job_id, updated_job_state)
              else
                # Check if there are any tasks that can still run
                # If all remaining tasks are blocked, fail the job immediately
                if all_remaining_tasks_blocked?(updated_job_state) do
                  Logger.error(
                    "All remaining tasks blocked for job #{job_id} - marking blocked tasks and failing job"
                  )

                  mark_blocked_tasks_as_upstream_failed(job_id, updated_job_state)
                  complete_job(job_id, updated_job_state)
                else
                  # Job still has runnable tasks, let them continue
                  Logger.info(
                    "Task #{task_id} failed, but job #{job_id} has remaining runnable tasks - continuing execution"
                  )

                  # Note: We don't dispatch new tasks here because failed tasks don't have success outputs
                  # Downstream tasks that depend on the failed task will never become ready
                  # But parallel independent tasks will continue
                end
              end

            {:error, _} ->
              Logger.error("Failed to get updated job state for job_id=#{job_id}")
          end
        end

      {:error, _} ->
        Logger.warning("Job state not found for job_id=#{job_id}")
    end

    {:noreply, state}
  end

  ## Private Functions

  defp create_task_executions(job, dag_definition) do
    dag_definition["nodes"]
    |> Enum.each(fn node ->
      Workflows.create_task_execution(%{
        job_id: job.id,
        task_id: node["id"],
        status: :pending,
        execution_type: node["type"]
      })
    end)
  end

  defp dispatch_ready_tasks(job_id, dag_definition) do
    case StateManager.get_job_state(job_id) do
      {:ok, job_state} ->
        completed_tasks = MapSet.to_list(job_state.completed_tasks)
        failed_tasks = MapSet.to_list(job_state.failed_tasks)

        ready_tasks = Validator.get_ready_tasks(dag_definition, completed_tasks, failed_tasks)

        # Filter out tasks that are already running
        ready_tasks =
          Enum.reject(ready_tasks, fn task_id ->
            Map.has_key?(job_state.running_tasks, task_id)
          end)

        # Dispatch each ready task with context from completed dependencies
        Enum.each(ready_tasks, fn task_id ->
          task_config = find_task_config(dag_definition, task_id)
          task_context = build_task_context(job_id, task_id, dag_definition, completed_tasks)
          Executor.dispatch_task(job_id, task_id, task_config, task_context)
        end)

      {:error, _} ->
        Logger.warning("Cannot dispatch tasks, job state not found for job_id=#{job_id}")
    end
  end

  defp find_task_config(dag_definition, task_id) do
    dag_definition["nodes"]
    |> Enum.find(fn node -> node["id"] == task_id end)
  end

  defp get_task_execution(job_id, task_id) do
    task_executions = Workflows.list_task_executions_for_job(job_id)
    Enum.find(task_executions, fn te -> te.task_id == task_id end)
  end

  defp build_task_context(job_id, task_id, dag_definition, completed_tasks) do
    # Get the original job context
    job = Workflows.get_job!(job_id)
    job_context = job.context || %{}

    # Find dependencies for this task
    dependencies = find_task_dependencies(dag_definition, task_id)

    # Get results from completed dependency tasks
    dependency_results =
      dependencies
      |> Enum.filter(fn dep_id -> dep_id in completed_tasks end)
      |> Enum.map(fn dep_id ->
        # Fetch task execution result from database
        case Workflows.list_task_executions_for_job(job_id) do
          task_executions ->
            task_execution = Enum.find(task_executions, fn te -> te.task_id == dep_id end)

            if task_execution && task_execution.result do
              {dep_id, task_execution.result}
            else
              {dep_id, %{}}
            end
        end
      end)
      |> Map.new()

    # Merge job context with upstream results
    Map.merge(job_context, %{"upstream_results" => dependency_results})
  end

  defp find_task_dependencies(dag_definition, task_id) do
    # Find all edges that point TO this task
    dag_definition["edges"]
    |> Enum.filter(fn edge -> edge["to"] == task_id end)
    |> Enum.map(fn edge -> edge["from"] end)
  end

  defp job_complete?(job_state) do
    all_tasks_count =
      MapSet.size(job_state.pending_tasks) +
        map_size(job_state.running_tasks) +
        MapSet.size(job_state.completed_tasks) +
        MapSet.size(job_state.failed_tasks)

    completed_or_failed =
      MapSet.size(job_state.completed_tasks) + MapSet.size(job_state.failed_tasks)

    # Job is complete when all tasks are either completed or failed
    completed_or_failed == all_tasks_count and map_size(job_state.running_tasks) == 0
  end

  defp all_remaining_tasks_blocked?(job_state) do
    # If there are running tasks, they might complete and unblock pending tasks
    if map_size(job_state.running_tasks) > 0 do
      false
    else
      # Check if any pending tasks can become ready
      completed_tasks = MapSet.to_list(job_state.completed_tasks)
      failed_tasks = MapSet.to_list(job_state.failed_tasks)

      ready_tasks =
        Validator.get_ready_tasks(
          job_state.dag_definition,
          completed_tasks,
          failed_tasks
        )

      # If no tasks are ready and we have pending tasks, they're all blocked
      ready_tasks == [] and MapSet.size(job_state.pending_tasks) > 0
    end
  end

  defp mark_blocked_tasks_as_upstream_failed(job_id, job_state) do
    # Get all pending tasks - these are blocked and will never run
    blocked_tasks = MapSet.to_list(job_state.pending_tasks)

    Logger.info("Marking #{length(blocked_tasks)} tasks as upstream_failed for job #{job_id}")

    # Update each blocked task in Postgres
    Enum.each(blocked_tasks, fn task_id ->
      case Workflows.list_task_executions_for_job(job_id) do
        task_executions ->
          task_execution = Enum.find(task_executions, fn te -> te.task_id == task_id end)

          if task_execution && task_execution.status == :pending do
            Workflows.update_task_execution(task_execution, %{
              status: :upstream_failed,
              completed_at: DateTime.utc_now()
            })

            Logger.debug("Marked task #{task_id} as upstream_failed")
          end
      end
    end)
  end

  defp complete_job(job_id, job_state) do
    # Mark any remaining pending tasks as upstream_failed
    # (these tasks never ran because their dependencies failed)
    if MapSet.size(job_state.pending_tasks) > 0 do
      mark_blocked_tasks_as_upstream_failed(job_id, job_state)
    end

    # Determine final status
    final_status = if MapSet.size(job_state.failed_tasks) > 0, do: :failed, else: :success

    # Update Job in Postgres
    job = Workflows.get_job!(job_id)

    Workflows.update_job(job, %{
      status: final_status,
      completed_at: DateTime.utc_now()
    })

    # Publish job completion event
    publish_job_event(job_id, job_state.dag_id, final_status)

    # Remove from active state
    StateManager.remove_job_state(job_id)

    Logger.info("Job completed: job_id=#{job_id}, status=#{final_status}")
  end

  defp publish_job_event(job_id, dag_id, status) do
    event = %Events.JobEvent{
      job_id: job_id,
      dag_id: dag_id,
      status: status,
      timestamp: DateTime.utc_now(),
      metadata: %{}
    }

    Events.publish_job_event(event)
  end
end
