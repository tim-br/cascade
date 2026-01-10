defmodule Cascade.Storage.SQLiteBackend do
  @moduledoc """
  SQLite storage backend implementation.

  Uses SQLite-compatible features:
  - Optimistic locking for atomic task claiming (vs Postgres FOR UPDATE)
  - JSON storage for definition, context, and result fields
  - UPSERT with ON CONFLICT for worker heartbeats
  - Suitable for single-node, zero-config deployments
  """

  @behaviour Cascade.Storage.Backend

  import Ecto.Query, warn: false
  alias Cascade.Repo
  alias Cascade.Workflows.{DAG, DagSchedule, Job, TaskExecution, WorkerHeartbeat}
  require Logger

  ## DAG functions

  @impl true
  def list_dags do
    DAG
    |> order_by([d], asc: d.name)
    |> Repo.all()
  end

  @impl true
  def list_enabled_dags do
    DAG
    |> where([d], d.enabled == true)
    |> Repo.all()
  end

  @impl true
  def get_dag!(id), do: Repo.get!(DAG, id)

  @impl true
  def get_dag_by_name(name) do
    Repo.get_by(DAG, name: name)
  end

  @impl true
  def create_dag(attrs \\ %{}) do
    %DAG{}
    |> DAG.changeset(attrs)
    |> Repo.insert()
  end

  @impl true
  def update_dag(%DAG{} = dag, attrs) do
    dag
    |> DAG.changeset(attrs)
    |> Repo.update()
  end

  @impl true
  def delete_dag(%DAG{} = dag) do
    Repo.delete(dag)
  end

  ## Job functions

  @impl true
  def list_jobs do
    Repo.all(Job)
  end

  @impl true
  def list_jobs_for_dag(dag_id) do
    Job
    |> where([j], j.dag_id == ^dag_id)
    |> order_by([j], desc: j.inserted_at)
    |> Repo.all()
  end

  @impl true
  def list_active_jobs do
    Job
    |> where([j], j.status in [:pending, :running])
    |> Repo.all()
  end

  @impl true
  def get_job!(id), do: Repo.get!(Job, id)

  @impl true
  def get_job_with_details!(id) do
    Job
    |> where([j], j.id == ^id)
    |> preload([:dag, :task_executions])
    |> Repo.one!()
  end

  @impl true
  def create_job(attrs \\ %{}) do
    %Job{}
    |> Job.changeset(attrs)
    |> Repo.insert()
  end

  @impl true
  def update_job(%Job{} = job, attrs) do
    job
    |> Job.changeset(attrs)
    |> Repo.update()
  end

  @impl true
  def delete_job(%Job{} = job) do
    Repo.delete(job)
  end

  ## TaskExecution functions

  @impl true
  def list_task_executions do
    Repo.all(TaskExecution)
  end

  @impl true
  def list_task_executions_for_job(job_id) do
    # Get task executions
    task_executions =
      TaskExecution
      |> where([te], te.job_id == ^job_id)
      |> Repo.all()

    # Get the job and DAG definition for topological ordering
    job = get_job!(job_id)
    dag = get_dag!(job.dag_id)

    # Order tasks topologically based on DAG structure
    task_order = topological_sort(dag.definition)

    # Sort task executions based on topological order
    Enum.sort_by(task_executions, fn te ->
      # Find index in topological order, default to end if not found
      Enum.find_index(task_order, &(&1 == te.task_id)) || 9999
    end)
  end

  @impl true
  def get_task_execution!(id), do: Repo.get!(TaskExecution, id)

  @impl true
  def create_task_execution(attrs \\ %{}) do
    %TaskExecution{}
    |> TaskExecution.changeset(attrs)
    |> Repo.insert()
  end

  @impl true
  def update_task_execution(%TaskExecution{} = task_execution, attrs) do
    task_execution
    |> TaskExecution.changeset(attrs)
    |> Repo.update()
  end

  @impl true
  def delete_task_execution(%TaskExecution{} = task_execution) do
    Repo.delete(task_execution)
  end

  @impl true
  def claim_task(job_id, task_id, worker_id) do
    # SQLite doesn't support FOR UPDATE, so use optimistic locking
    # with immediate transaction to acquire database-level lock
    Repo.transaction(
      fn ->
        # Find the task execution (database-level lock via IMMEDIATE transaction)
        task_execution =
          TaskExecution
          |> where([te], te.job_id == ^job_id and te.task_id == ^task_id)
          |> Repo.one()

        if task_execution do
          # Check if task is already successfully completed or skipped
          if task_execution.status in [:success, :upstream_failed] do
            Repo.rollback(:already_completed)
          else
            # Convert worker_id to string for comparison and storage
            worker_id_str = to_string(worker_id)

            case task_execution.claimed_by_worker do
              nil ->
                # Not claimed yet, claim it
                {:ok, _} =
                  update_task_execution(task_execution, %{
                    claimed_by_worker: worker_id_str,
                    claimed_at: DateTime.utc_now()
                  })

                :claimed

              ^worker_id_str ->
                # Already claimed by this worker (idempotent)
                :claimed

              _other_worker ->
                # Already claimed by a different worker
                Repo.rollback(:already_claimed)
            end
          end
        else
          Repo.rollback(:task_not_found)
        end
      end,
      # Use IMMEDIATE transaction to acquire write lock immediately
      mode: :immediate
    )
    |> case do
      {:ok, :claimed} -> {:ok, :claimed}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def get_job_state(job_id) do
    task_executions = list_task_executions_for_job(job_id)
    job = get_job!(job_id)
    dag = get_dag!(job.dag_id)

    # Get all task IDs from the DAG
    all_task_ids =
      dag.definition["nodes"]
      |> Enum.map(& &1["id"])
      |> MapSet.new()

    # Build state from task executions
    {pending, running, completed, failed, skipped} =
      Enum.reduce(task_executions, {all_task_ids, %{}, MapSet.new(), MapSet.new(), MapSet.new()}, fn te,
                                                                                                       {pending_acc,
                                                                                                        running_acc,
                                                                                                        completed_acc,
                                                                                                        failed_acc,
                                                                                                        skipped_acc} ->
        case te.status do
          :pending ->
            {pending_acc, running_acc, completed_acc, failed_acc, skipped_acc}

          :running ->
            {
              MapSet.delete(pending_acc, te.task_id),
              Map.put(running_acc, te.task_id, te.worker_node),
              completed_acc,
              failed_acc,
              skipped_acc
            }

          :success ->
            {
              MapSet.delete(pending_acc, te.task_id),
              Map.delete(running_acc, te.task_id),
              MapSet.put(completed_acc, te.task_id),
              failed_acc,
              skipped_acc
            }

          :failed ->
            {
              MapSet.delete(pending_acc, te.task_id),
              Map.delete(running_acc, te.task_id),
              completed_acc,
              MapSet.put(failed_acc, te.task_id),
              skipped_acc
            }

          :upstream_failed ->
            {
              MapSet.delete(pending_acc, te.task_id),
              Map.delete(running_acc, te.task_id),
              completed_acc,
              failed_acc,
              MapSet.put(skipped_acc, te.task_id)
            }

          _ ->
            {pending_acc, running_acc, completed_acc, failed_acc, skipped_acc}
        end
      end)

    {:ok,
     %{
       job_id: job_id,
       dag_id: job.dag_id,
       status: job.status,
       pending_tasks: pending,
       running_tasks: running,
       completed_tasks: completed,
       failed_tasks: failed,
       skipped_tasks: skipped,
       dag_definition: dag.definition,
       started_at: job.started_at
     }}
  end

  ## WorkerHeartbeat functions

  @impl true
  def upsert_worker_heartbeat(node, capacity, active_tasks) do
    attrs = %{
      node: node,
      last_seen: DateTime.utc_now(),
      capacity: capacity,
      active_tasks: active_tasks
    }

    # SQLite supports ON CONFLICT (SQLite 3.24.0+)
    %WorkerHeartbeat{}
    |> WorkerHeartbeat.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:last_seen, :capacity, :active_tasks, :updated_at]},
      conflict_target: :node
    )
  end

  @impl true
  def get_active_workers do
    cutoff = DateTime.add(DateTime.utc_now(), -30, :second)

    WorkerHeartbeat
    |> where([wh], wh.last_seen > ^cutoff)
    |> Repo.all()
  end

  @impl true
  def get_worker_heartbeat(node) do
    Repo.get(WorkerHeartbeat, node)
  end

  ## DagSchedule functions

  @impl true
  def list_due_schedules(current_time) do
    DagSchedule
    |> where([s], s.is_active == true)
    |> where([s], s.next_run_at <= ^current_time)
    |> Repo.all()
  end

  @impl true
  def get_dag_schedule(dag_id) do
    Repo.get(DagSchedule, dag_id)
  end

  @impl true
  def upsert_dag_schedule(attrs) do
    %DagSchedule{}
    |> DagSchedule.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:cron_expression, :next_run_at, :is_active, :updated_at]},
      conflict_target: :dag_id
    )
  end

  @impl true
  def update_dag_schedule(%DagSchedule{} = schedule, attrs) do
    schedule
    |> DagSchedule.changeset(attrs)
    |> Repo.update()
  end

  @impl true
  def deactivate_dag_schedule(dag_id) do
    DagSchedule
    |> where([s], s.dag_id == ^dag_id)
    |> Repo.update_all(set: [is_active: false, updated_at: DateTime.utc_now()])

    :ok
  end

  @impl true
  def delete_dag_schedule(dag_id) do
    DagSchedule
    |> where([s], s.dag_id == ^dag_id)
    |> Repo.delete_all()

    :ok
  end

  @impl true
  def count_active_schedules do
    DagSchedule
    |> where([s], s.is_active == true)
    |> Repo.aggregate(:count)
  end

  ## Private helpers

  # Performs topological sort on DAG definition
  defp topological_sort(dag_definition) do
    nodes = dag_definition["nodes"] || []
    edges = dag_definition["edges"] || []

    # Build adjacency list (task_id -> list of dependent task_ids)
    dependencies =
      Enum.reduce(edges, %{}, fn edge, acc ->
        from = edge["from"]
        to = edge["to"]
        Map.update(acc, to, [from], &[from | &1])
      end)

    # Initialize with tasks that have no dependencies
    task_ids = Enum.map(nodes, & &1["id"])

    no_deps =
      task_ids
      |> Enum.reject(&Map.has_key?(dependencies, &1))

    # Kahn's algorithm for topological sort
    kahn_sort(task_ids, dependencies, no_deps, [])
  end

  defp kahn_sort([], _dependencies, _queue, result), do: Enum.reverse(result)
  defp kahn_sort(_remaining, _dependencies, [], result), do: Enum.reverse(result)

  defp kahn_sort(remaining, dependencies, [current | rest_queue], result) do
    # Add current to result
    new_result = [current | result]
    new_remaining = List.delete(remaining, current)

    # Find tasks that now have all dependencies satisfied
    newly_ready =
      Enum.filter(new_remaining, fn task_id ->
        deps = Map.get(dependencies, task_id, [])
        # All dependencies are in the result
        Enum.all?(deps, &(&1 in new_result))
      end)

    # Add newly ready tasks to queue (avoid duplicates)
    new_queue = Enum.uniq(rest_queue ++ newly_ready)

    kahn_sort(new_remaining, dependencies, new_queue, new_result)
  end
end
