defmodule Cascade.Runtime.StateManager do
  @moduledoc """
  Manages job execution state using Postgres.

  The StateManager is the central coordinator for job execution state.
  All state is stored in Postgres for consistency and durability:
  - Job state is computed from TaskExecution records
  - Task claims use row-level locking for atomicity
  - Worker heartbeats are tracked in the worker_heartbeats table

  This design prioritizes correctness and observability over raw performance.
  TODO: Add ETS caching layer for improved performance (after correctness is validated).
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
  Gets the current state for a job (computed from Postgres).
  """
  def get_job_state(job_id) do
    Workflows.get_job_state(job_id)
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
  Gets all active workers with their stats (from Postgres).
  """
  def get_active_workers do
    Workflows.get_active_workers()
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
    Logger.info("StateManager initialized (Postgres-based)")
    {:ok, %{}}
  end

  @impl true
  def handle_call({:create_job_state, job_id, _dag_definition}, _from, state) do
    # Job state is already in Postgres (created by Scheduler)
    # Just compute and return the current state
    try do
      {:ok, job_state} = Workflows.get_job_state(job_id)
      Logger.info("Created job state for job_id=#{job_id}")
      {:reply, {:ok, job_state}, state}
    rescue
      e ->
        Logger.error("Failed to create job state for job_id=#{job_id}: #{inspect(e)}")
        {:reply, {:error, :job_not_found}, state}
    end
  end

  @impl true
  def handle_call({:update_task_status, job_id, task_id, new_status, opts}, _from, state) do
    # Find the task execution in Postgres
    task_executions = Workflows.list_task_executions_for_job(job_id)
    task_execution = Enum.find(task_executions, fn te -> te.task_id == task_id end)

    if task_execution do
      old_status = task_execution.status

      Logger.info("🔄 [STATUS_UPDATE] job=#{job_id}, task=#{task_id}, #{old_status} → #{new_status}")

      # Build attributes for update (filter out nils and convert worker_node to string)
      attrs = %{status: new_status}

      attrs = if opts[:worker_node], do: Map.put(attrs, :worker_node, to_string(opts[:worker_node])), else: attrs
      attrs = if opts[:result], do: Map.put(attrs, :result, opts[:result]), else: attrs
      attrs = if opts[:error], do: Map.put(attrs, :error, opts[:error]), else: attrs

      # Add timestamps based on status
      attrs =
        case new_status do
          :running -> Map.put(attrs, :started_at, DateTime.utc_now())
          s when s in [:success, :failed, :upstream_failed] -> Map.put(attrs, :completed_at, DateTime.utc_now())
          _ -> attrs
        end

      # Update in Postgres
      case Workflows.update_task_execution(task_execution, attrs) do
        {:ok, _updated_execution} ->
          # Publish task event
          publish_task_event(job_id, task_id, new_status, opts)

          # Get updated job state
          {:ok, job_state} = Workflows.get_job_state(job_id)

          {:reply, {:ok, job_state}, state}

        {:error, changeset} ->
          Logger.error("Failed to update task execution: #{inspect(changeset)}")
          {:reply, {:error, :update_failed}, state}
      end
    else
      Logger.error("⚠️  [STATUS_UPDATE_FAILED] job=#{job_id}, task=#{task_id} - task execution not found")
      {:reply, {:error, :task_not_found}, state}
    end
  end

  @impl true
  def handle_call({:assign_task, _job_id, _task_id, _worker_node}, _from, state) do
    # No longer needed - task assignment is handled by claim_task
    {:reply, {:ok, :deprecated}, state}
  end

  @impl true
  def handle_call({:claim_task, job_id, task_id, worker_id}, _from, state) do
    # Delegate to Workflows.claim_task which uses Postgres row-level locking
    case Workflows.claim_task(job_id, task_id, worker_id) do
      {:ok, :claimed} ->
        {:reply, {:ok, :claimed}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_cast({:heartbeat, node, capacity, active_tasks}, state) do
    # Delegate to Workflows.upsert_worker_heartbeat
    Workflows.upsert_worker_heartbeat(node, capacity, active_tasks)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:remove_job_state, job_id}, state) do
    # No-op since we're not using ETS
    Logger.info("Removed job state for job_id=#{job_id} (no-op for Postgres-based state)")
    {:noreply, state}
  end

  ## Private Functions

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
end
