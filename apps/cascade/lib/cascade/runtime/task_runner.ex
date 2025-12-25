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

    # Check if task is already assigned/running (deduplication)
    case StateManager.claim_task(job_id, task_id, state.worker_id) do
      {:ok, :claimed} ->
        Logger.info("Executing task: job_id=#{job_id}, task_id=#{task_id}, worker=#{state.worker_id}")

        # Update state to running
        StateManager.update_task_status(job_id, task_id, :running, worker_node: node())

        # Execute the task
        result = execute_task(task_config, payload)

        # Handle result
        case result do
          {:ok, task_result} ->
            Logger.info("Task succeeded: job_id=#{job_id}, task_id=#{task_id}")
            Scheduler.handle_task_completion(job_id, task_id, task_result)

          {:error, error} ->
            Logger.error("Task failed: job_id=#{job_id}, task_id=#{task_id}, error=#{inspect(error)}")
            Scheduler.handle_task_failure(job_id, task_id, inspect(error))
        end

        {:noreply, %{state | current_task: nil}}

      {:error, :already_claimed} ->
        # Task already being executed by another worker, skip
        Logger.debug("Task already claimed by another worker: job_id=#{job_id}, task_id=#{task_id}")
        {:noreply, state}
    end
  end

  ## Private Functions

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
