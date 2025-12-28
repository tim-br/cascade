defmodule Cascade.Workflows do
  @moduledoc """
  The Workflows context.

  Provides functions for managing DAGs, Jobs, and TaskExecutions.

  This module delegates to a configurable backend implementation
  (SQLite, Postgres, or DynamoDB) based on runtime configuration.
  """

  alias Cascade.Workflows.{DAG, Job, TaskExecution, WorkerHeartbeat}

  @doc """
  Returns the configured storage backend module.

  Defaults to SQLiteBackend for zero-config setup.
  Use PostgresBackend in production with DATABASE_URL set.
  """
  def backend do
    Application.get_env(:cascade, :storage_backend, Cascade.Storage.SQLiteBackend)
  end

  ## DAG functions

  @doc """
  Returns the list of dags.

  ## Examples

      iex> list_dags()
      [%DAG{}, ...]

  """
  defdelegate list_dags(), to: backend()

  @doc """
  Returns the list of enabled dags.
  """
  defdelegate list_enabled_dags(), to: backend()

  @doc """
  Gets a single dag.

  Raises `Ecto.NoResultsError` if the DAG does not exist.

  ## Examples

      iex> get_dag!(123)
      %DAG{}

      iex> get_dag!(456)
      ** (Ecto.NoResultsError)

  """
  defdelegate get_dag!(id), to: backend()

  @doc """
  Gets a dag by name.
  """
  defdelegate get_dag_by_name(name), to: backend()

  @doc """
  Creates a dag.

  ## Examples

      iex> create_dag(%{field: value})
      {:ok, %DAG{}}

      iex> create_dag(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  defdelegate create_dag(attrs \\ %{}), to: backend()

  @doc """
  Updates a dag.

  ## Examples

      iex> update_dag(dag, %{field: new_value})
      {:ok, %DAG{}}

      iex> update_dag(dag, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  defdelegate update_dag(dag, attrs), to: backend()

  @doc """
  Deletes a dag.

  ## Examples

      iex> delete_dag(dag)
      {:ok, %DAG{}}

      iex> delete_dag(dag)
      {:error, %Ecto.Changeset{}}

  """
  defdelegate delete_dag(dag), to: backend()

  ## Job functions

  @doc """
  Returns the list of jobs.
  """
  defdelegate list_jobs(), to: backend()

  @doc """
  Returns the list of jobs for a specific DAG.
  """
  defdelegate list_jobs_for_dag(dag_id), to: backend()

  @doc """
  Returns the list of active (running or pending) jobs.
  """
  defdelegate list_active_jobs(), to: backend()

  @doc """
  Gets a single job.

  Raises `Ecto.NoResultsError` if the Job does not exist.
  """
  defdelegate get_job!(id), to: backend()

  @doc """
  Gets a job with preloaded associations.
  """
  defdelegate get_job_with_details!(id), to: backend()

  @doc """
  Creates a job.
  """
  defdelegate create_job(attrs \\ %{}), to: backend()

  @doc """
  Updates a job.
  """
  defdelegate update_job(job, attrs), to: backend()

  @doc """
  Deletes a job.
  """
  defdelegate delete_job(job), to: backend()

  ## TaskExecution functions

  @doc """
  Returns the list of task_executions.
  """
  defdelegate list_task_executions(), to: backend()

  @doc """
  Returns the list of task executions for a specific job.
  """
  defdelegate list_task_executions_for_job(job_id), to: backend()

  @doc """
  Gets a single task_execution.

  Raises `Ecto.NoResultsError` if the TaskExecution does not exist.
  """
  defdelegate get_task_execution!(id), to: backend()

  @doc """
  Creates a task_execution.
  """
  defdelegate create_task_execution(attrs \\ %{}), to: backend()

  @doc """
  Updates a task_execution.
  """
  defdelegate update_task_execution(task_execution, attrs), to: backend()

  @doc """
  Deletes a task_execution.
  """
  defdelegate delete_task_execution(task_execution), to: backend()

  @doc """
  Atomically claims a task for execution by a worker.

  Returns {:ok, :claimed} if successfully claimed.
  Returns {:error, :already_claimed} if already claimed by another worker.
  Returns {:error, :already_completed} if task is already completed.
  """
  defdelegate claim_task(job_id, task_id, worker_id), to: backend()

  @doc """
  Gets the current job state computed from task executions.

  Returns a map with:
  - :pending_tasks - MapSet of task IDs still pending
  - :running_tasks - Map of task_id => worker_node for running tasks
  - :completed_tasks - MapSet of successfully completed task IDs
  - :failed_tasks - MapSet of failed task IDs
  - :skipped_tasks - MapSet of skipped task IDs (upstream_failed)
  """
  defdelegate get_job_state(job_id), to: backend()

  ## WorkerHeartbeat functions

  @doc """
  Records or updates a worker heartbeat.
  """
  defdelegate upsert_worker_heartbeat(node, capacity, active_tasks), to: backend()

  @doc """
  Gets all active worker heartbeats.
  Returns workers that have been seen in the last 30 seconds.
  """
  defdelegate get_active_workers(), to: backend()

  @doc """
  Gets a specific worker heartbeat by node name.
  """
  defdelegate get_worker_heartbeat(node), to: backend()
end
