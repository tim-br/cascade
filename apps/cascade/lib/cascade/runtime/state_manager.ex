defmodule Cascade.Runtime.StateManager do
  @moduledoc """
  Manages in-memory state for active jobs using ETS.

  The StateManager is the central brain for job execution state.
  It maintains three ETS tables:
  - :active_jobs - tracks job execution state
  - :worker_assignments - tracks which tasks are assigned to which workers
  - :worker_heartbeats - tracks worker health and capacity

  State is persisted asynchronously to Postgres for durability.
  """

  use GenServer
  require Logger

  alias Cascade.Events
  alias Cascade.Workflows

  ## Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Initializes job state from a DAG definition.

  Creates an entry in the :active_jobs table with pending tasks.
  """
  def create_job_state(job_id, dag_definition) do
    GenServer.call(__MODULE__, {:create_job_state, job_id, dag_definition})
  end

  @doc """
  Updates task status and publishes event.
  """
  def update_task_status(job_id, task_id, status, opts \\ []) do
    GenServer.call(__MODULE__, {:update_task_status, job_id, task_id, status, opts})
  end

  @doc """
  Gets the current state for a job.
  """
  def get_job_state(job_id) do
    case :ets.lookup(:active_jobs, job_id) do
      [{^job_id, state}] -> {:ok, state}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Assigns a task to a worker node.
  """
  def assign_task(job_id, task_id, worker_node) do
    GenServer.call(__MODULE__, {:assign_task, job_id, task_id, worker_node})
  end

  @doc """
  Atomically claims a task for execution.
  Returns {:ok, :claimed} if successfully claimed, {:error, :already_claimed} if already taken.
  """
  def claim_task(job_id, task_id, worker_id) do
    GenServer.call(__MODULE__, {:claim_task, job_id, task_id, worker_id})
  end

  @doc """
  Records a worker heartbeat.
  """
  def record_heartbeat(node, capacity, active_tasks) do
    GenServer.cast(__MODULE__, {:heartbeat, node, capacity, active_tasks})
  end

  @doc """
  Gets all active workers with their stats.
  """
  def get_active_workers do
    :ets.tab2list(:worker_heartbeats)
  end

  @doc """
  Removes a job from active state (called when job completes).
  """
  def remove_job_state(job_id) do
    GenServer.cast(__MODULE__, {:remove_job_state, job_id})
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    # Create ETS tables
    :ets.new(:active_jobs, [:set, :public, :named_table, read_concurrency: true])
    :ets.new(:worker_assignments, [:set, :public, :named_table, read_concurrency: true])
    :ets.new(:worker_heartbeats, [:set, :public, :named_table, read_concurrency: true])

    Logger.info("StateManager initialized with ETS tables")

    {:ok, %{}}
  end

  @impl true
  def handle_call({:create_job_state, job_id, dag_definition}, _from, state) do
    # Extract all task IDs from the DAG
    all_tasks =
      dag_definition["nodes"]
      |> Enum.map(& &1["id"])
      |> MapSet.new()

    job_state = %{
      job_id: job_id,
      dag_id: dag_definition["dag_id"],
      status: :running,
      pending_tasks: all_tasks,
      running_tasks: %{},
      completed_tasks: MapSet.new(),
      failed_tasks: MapSet.new(),
      dag_definition: dag_definition,
      started_at: DateTime.utc_now()
    }

    :ets.insert(:active_jobs, {job_id, job_state})

    Logger.info("Created job state for job_id=#{job_id}")

    {:reply, {:ok, job_state}, state}
  end

  @impl true
  def handle_call({:update_task_status, job_id, task_id, new_status, opts}, _from, state) do
    case :ets.lookup(:active_jobs, job_id) do
      [{^job_id, job_state}] ->
        updated_state = apply_task_status_change(job_state, task_id, new_status, opts)
        :ets.insert(:active_jobs, {job_id, updated_state})

        # Publish task event
        publish_task_event(job_id, task_id, new_status, opts)

        # Persist to Postgres (synchronous for reliability)
        # Use Task.Supervisor for async in production if needed
        persist_task_status(job_id, task_id, new_status, opts)

        {:reply, {:ok, updated_state}, state}

      [] ->
        {:reply, {:error, :job_not_found}, state}
    end
  end

  @impl true
  def handle_call({:assign_task, job_id, task_id, worker_node}, _from, state) do
    assignment = %{
      worker_node: worker_node,
      assigned_at: DateTime.utc_now(),
      status: :assigned
    }

    :ets.insert(:worker_assignments, {{job_id, task_id}, assignment})

    # Update job state
    case :ets.lookup(:active_jobs, job_id) do
      [{^job_id, job_state}] ->
        updated_state = %{
          job_state
          | running_tasks: Map.put(job_state.running_tasks, task_id, worker_node),
            pending_tasks: MapSet.delete(job_state.pending_tasks, task_id)
        }

        :ets.insert(:active_jobs, {job_id, updated_state})

        {:reply, {:ok, assignment}, state}

      [] ->
        {:reply, {:error, :job_not_found}, state}
    end
  end

  @impl true
  def handle_call({:claim_task, job_id, task_id, worker_id}, _from, state) do
    # Atomically check and claim the task
    case :ets.lookup(:worker_assignments, {job_id, task_id}) do
      [] ->
        # Not assigned yet, claim it
        assignment = %{
          worker_id: worker_id,
          worker_node: node(),
          claimed_at: DateTime.utc_now(),
          status: :claimed
        }

        :ets.insert(:worker_assignments, {{job_id, task_id}, assignment})
        {:reply, {:ok, :claimed}, state}

      [{_key, existing_assignment}] ->
        # Already assigned, check if it's this worker
        if existing_assignment[:worker_id] == worker_id do
          {:reply, {:ok, :claimed}, state}
        else
          {:reply, {:error, :already_claimed}, state}
        end
    end
  end

  @impl true
  def handle_cast({:heartbeat, node, capacity, active_tasks}, state) do
    heartbeat_data = %{
      node: node,
      last_seen: DateTime.utc_now(),
      capacity: capacity,
      active_tasks: active_tasks
    }

    :ets.insert(:worker_heartbeats, {node, heartbeat_data})

    {:noreply, state}
  end

  @impl true
  def handle_cast({:remove_job_state, job_id}, state) do
    :ets.delete(:active_jobs, job_id)
    Logger.info("Removed job state for job_id=#{job_id}")
    {:noreply, state}
  end

  ## Private Functions

  defp apply_task_status_change(job_state, task_id, status, opts) do
    case status do
      :running ->
        %{
          job_state
          | running_tasks: Map.put(job_state.running_tasks, task_id, opts[:worker_node]),
            pending_tasks: MapSet.delete(job_state.pending_tasks, task_id)
        }

      :success ->
        %{
          job_state
          | completed_tasks: MapSet.put(job_state.completed_tasks, task_id),
            running_tasks: Map.delete(job_state.running_tasks, task_id)
        }

      :failed ->
        %{
          job_state
          | failed_tasks: MapSet.put(job_state.failed_tasks, task_id),
            running_tasks: Map.delete(job_state.running_tasks, task_id)
        }

      _ ->
        job_state
    end
  end

  defp publish_task_event(job_id, task_id, status, opts) do
    event = %Events.TaskEvent{
      job_id: job_id,
      task_id: task_id,
      status: status,
      worker_node: opts[:worker_node],
      timestamp: DateTime.utc_now(),
      result: opts[:result],
      error: opts[:error]
    }

    Events.publish_task_event(event)
  end

  defp persist_task_status(job_id, task_id, status, opts) do
    # Find the TaskExecution record and update it
    case Workflows.list_task_executions_for_job(job_id) do
      task_executions ->
        task_execution =
          Enum.find(task_executions, fn te -> te.task_id == task_id end)

        if task_execution do
          attrs = %{
            status: status,
            worker_node: opts[:worker_node],
            result: opts[:result],
            error: opts[:error]
          }

          attrs =
            case status do
              :running -> Map.put(attrs, :started_at, DateTime.utc_now())
              s when s in [:success, :failed] -> Map.put(attrs, :completed_at, DateTime.utc_now())
              _ -> attrs
            end

          Workflows.update_task_execution(task_execution, attrs)
        end
    end
  end
end
