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
          # Dispatch next ready tasks
          dispatch_ready_tasks(job_id, job_state.dag_definition)
        end

      {:error, _} ->
        Logger.warning("Job state not found for job_id=#{job_id}")
    end

    {:noreply, state}
  end

  @impl true
  def handle_cast({:task_failed, job_id, task_id, error}, state) do
    Logger.error("Task failed: job_id=#{job_id}, task_id=#{task_id}, error=#{inspect(error)}")

    # Update task status
    StateManager.update_task_status(job_id, task_id, :failed, error: error)

    # For now, we'll continue execution even if a task fails
    # TODO: Implement failure handling policies (fail-fast, ignore, retry)

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

        # Dispatch each ready task
        Enum.each(ready_tasks, fn task_id ->
          task_config = find_task_config(dag_definition, task_id)
          Executor.dispatch_task(job_id, task_id, task_config)
        end)

      {:error, _} ->
        Logger.warning("Cannot dispatch tasks, job state not found for job_id=#{job_id}")
    end
  end

  defp find_task_config(dag_definition, task_id) do
    dag_definition["nodes"]
    |> Enum.find(fn node -> node["id"] == task_id end)
  end

  defp job_complete?(job_state) do
    all_tasks_count = MapSet.size(job_state.pending_tasks) +
                      map_size(job_state.running_tasks) +
                      MapSet.size(job_state.completed_tasks) +
                      MapSet.size(job_state.failed_tasks)

    completed_or_failed = MapSet.size(job_state.completed_tasks) + MapSet.size(job_state.failed_tasks)

    # Job is complete when all tasks are either completed or failed
    completed_or_failed == all_tasks_count and map_size(job_state.running_tasks) == 0
  end

  defp complete_job(job_id, job_state) do
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
