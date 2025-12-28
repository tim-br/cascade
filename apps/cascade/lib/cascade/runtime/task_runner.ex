defmodule Cascade.Runtime.TaskRunner do
  @moduledoc """
  GenServer that executes tasks.

  Each TaskRunner:
  - Subscribes to PubSub for task assignments
  - Executes tasks (local or Lambda)
  - Reports results back via the Scheduler
  """

  use GenServer
  require Logger

  alias Cascade.Runtime.{Scheduler, StateManager}
  alias Cascade.Runtime.TaskExecutors.{LocalExecutor, LambdaExecutor}
  alias Cascade.Events

  ## Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    worker_id = Keyword.get(opts, :worker_id, :rand.uniform(10000))

    # Subscribe to worker topic for this node
    Phoenix.PubSub.subscribe(Cascade.PubSub, Events.worker_topic(node()))

    Logger.info("TaskRunner started: worker_id=#{worker_id}, node=#{node()}")

    state = %{
      worker_id: worker_id,
      current_task: nil,
      node: node()
    }

    {:ok, state}
  end

  @impl true
  def handle_info({:execute_task, payload}, state) do
    %{job_id: job_id, task_id: task_id, task_config: task_config} = payload
    depends_on = Map.get(payload, :depends_on, [])

    Logger.info("🔔 [TASK_DISPATCH] job=#{job_id}, task=#{task_id}, worker=#{state.worker_id}, type=#{task_config["type"]}")

    # Check if task is already assigned/running (deduplication)
    case StateManager.claim_task(job_id, task_id, state.worker_id) do
      {:ok, :claimed} ->
        Logger.info("🎯 [TASK_CLAIMED] job=#{job_id}, task=#{task_id}, worker=#{state.worker_id}")

        # Check if dependencies are still valid (race condition protection)
        # If any dependency failed since dispatch, skip execution
        case check_dependencies_valid(job_id, depends_on) do
          :ok ->
            # Update state to running
            StateManager.update_task_status(job_id, task_id, :running, worker_node: node())

            # Execute the task
            result = execute_task(task_config, payload)

            # Handle result
            case result do
              {:ok, task_result} ->
                Logger.info("✅ [TASK_SUCCESS] job=#{job_id}, task=#{task_id}, worker=#{state.worker_id}, result=#{inspect(task_result)}")
                Scheduler.handle_task_completion(job_id, task_id, task_result)

              {:error, error} ->
                Logger.error("❌ [TASK_FAILURE] job=#{job_id}, task=#{task_id}, worker=#{state.worker_id}, error=#{inspect(error)}")
                Scheduler.handle_task_failure(job_id, task_id, inspect(error))
            end

          {:error, :upstream_failed} ->
            Logger.warning("Task #{task_id} skipped - upstream dependency failed after dispatch")
            # Mark as upstream_failed instead of executing
            StateManager.update_task_status(job_id, task_id, :upstream_failed)
            # Notify scheduler to check if job is complete
            Scheduler.handle_task_skipped(job_id, task_id)
        end

        {:noreply, %{state | current_task: nil}}

      {:error, :already_claimed} ->
        # Task already being executed by another worker, skip
        Logger.debug("Task already claimed by another worker: job_id=#{job_id}, task_id=#{task_id}")
        {:noreply, state}

      {:error, :already_completed} ->
        # Task already completed (success or upstream_failed), cannot be re-executed
        Logger.debug("Task already completed, skipping: job_id=#{job_id}, task_id=#{task_id}")
        {:noreply, state}
    end
  end

  ## Private Functions

  defp check_dependencies_valid(job_id, depends_on) do
    if Enum.empty?(depends_on) do
      # No dependencies, always valid
      :ok
    else
      # Check all dependencies in Postgres (source of truth)
      alias Cascade.Workflows
      task_executions = Workflows.list_task_executions_for_job(job_id)

      # Check if any dependency has failed
      failed_dependency = Enum.find(depends_on, fn dep_task_id ->
        case Enum.find(task_executions, fn te -> te.task_id == dep_task_id end) do
          nil -> false  # Dependency not found (shouldn't happen)
          task_execution -> task_execution.status == :failed
        end
      end)

      if failed_dependency do
        Logger.warning("Dependency #{failed_dependency} has failed - cannot execute task")
        {:error, :upstream_failed}
      else
        :ok
      end
    end
  end

  defp execute_task(task_config, payload) do
    task_type = task_config["type"]

    case task_type do
      "local" ->
        LocalExecutor.execute(task_config, payload)

      "lambda" ->
        LambdaExecutor.execute(task_config, payload)

      _ ->
        {:error, "Unknown task type: #{task_type}"}
    end
  end
end
