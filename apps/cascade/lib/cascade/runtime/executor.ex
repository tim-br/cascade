defmodule Cascade.Runtime.Executor do
  @moduledoc """
  The Executor dispatches tasks to available workers.

  Responsibilities:
  - Receive task dispatch requests from Scheduler
  - Select available workers (load balancing)
  - Send task execution commands to workers via PubSub
  - Track task assignments in StateManager
  - Handle worker failures and reassign tasks (Phase 2)

  For Phase 1 (single node), selects the current node for all tasks.
  """

  use GenServer
  require Logger

  alias Cascade.Runtime.StateManager
  alias Cascade.Events

  ## Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Dispatches a task to an available worker.
  """
  def dispatch_task(job_id, task_id, task_config) do
    GenServer.cast(__MODULE__, {:dispatch_task, job_id, task_id, task_config})
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    Logger.info("Executor started")

    {:ok, %{}}
  end

  @impl true
  def handle_cast({:dispatch_task, job_id, task_id, task_config}, state) do
    # Select a worker
    worker_node = select_worker(task_config)

    # Assign task in StateManager
    StateManager.assign_task(job_id, task_id, worker_node)

    # Build task execution payload
    task_payload = %{
      job_id: job_id,
      task_id: task_id,
      task_config: task_config
    }

    # Send task to worker via PubSub
    Events.send_to_worker(worker_node, {:execute_task, task_payload})

    Logger.info("Dispatched task: job_id=#{job_id}, task_id=#{task_id}, worker=#{worker_node}")

    {:noreply, state}
  end

  ## Private Functions

  defp select_worker(_task_config) do
    # Phase 1: Simple strategy - always use current node
    # Phase 2: Implement load balancing across cluster
    node()
  end

  # Future: Phase 2 implementation
  # defp select_worker(task_config) do
  #   workers = StateManager.get_active_workers()
  #
  #   # Filter workers by capacity
  #   available_workers =
  #     workers
  #     |> Enum.filter(fn {_node, data} ->
  #       data.active_tasks < data.capacity
  #     end)
  #
  #   case available_workers do
  #     [] ->
  #       # No available workers, use current node
  #       node()
  #
  #     workers ->
  #       # Select worker with least load
  #       {worker_node, _data} =
  #         Enum.min_by(workers, fn {_node, data} ->
  #           data.active_tasks / data.capacity
  #         end)
  #
  #       worker_node
  #   end
  # end
end
