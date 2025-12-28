defmodule Cascade.Workflows do
  @moduledoc """
  The Workflows context.

  Provides functions for managing DAGs, Jobs, and TaskExecutions.

  This module delegates to a configurable backend implementation
  (SQLite, Postgres, or DynamoDB) based on runtime configuration.
  """

  alias Cascade.Workflows.{DAG, Job, TaskExecution}

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
  def list_dags, do: backend().list_dags()

  @doc """
  Returns the list of enabled dags.
  """
  def list_enabled_dags, do: backend().list_enabled_dags()

  @doc """
  Gets a single dag.

  Raises `Ecto.NoResultsError` if the DAG does not exist.

  ## Examples

      iex> get_dag!(123)
      %DAG{}

      iex> get_dag!(456)
      ** (Ecto.NoResultsError)

  """
  def get_dag!(id), do: backend().get_dag!(id)

  @doc """
  Gets a dag by name.
  """
  def get_dag_by_name(name), do: backend().get_dag_by_name(name)

  @doc """
  Creates a dag.

  ## Examples

      iex> create_dag(%{field: value})
      {:ok, %DAG{}}

      iex> create_dag(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_dag(attrs \\ %{}), do: backend().create_dag(attrs)

  @doc """
  Updates a dag.

  ## Examples

      iex> update_dag(dag, %{field: new_value})
      {:ok, %DAG{}}

      iex> update_dag(dag, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_dag(%DAG{} = dag, attrs), do: backend().update_dag(dag, attrs)

  @doc """
  Deletes a dag.

  ## Examples

      iex> delete_dag(dag)
      {:ok, %DAG{}}

      iex> delete_dag(dag)
      {:error, %Ecto.Changeset{}}

  """
  def delete_dag(%DAG{} = dag), do: backend().delete_dag(dag)

  ## Job functions

  @doc """
  Returns the list of jobs.
  """
  def list_jobs, do: backend().list_jobs()

  @doc """
  Returns the list of jobs for a specific DAG.
  """
  def list_jobs_for_dag(dag_id), do: backend().list_jobs_for_dag(dag_id)

  @doc """
  Returns the list of active (running or pending) jobs.
  """
  def list_active_jobs, do: backend().list_active_jobs()

  @doc """
  Gets a single job.

  Raises `Ecto.NoResultsError` if the Job does not exist.
  """
  def get_job!(id), do: backend().get_job!(id)

  @doc """
  Gets a job with preloaded associations.
  """
  def get_job_with_details!(id), do: backend().get_job_with_details!(id)

  @doc """
  Creates a job.
  """
  def create_job(attrs \\ %{}), do: backend().create_job(attrs)

  @doc """
  Updates a job.
  """
  def update_job(%Job{} = job, attrs), do: backend().update_job(job, attrs)

  @doc """
  Deletes a job.
  """
  def delete_job(%Job{} = job), do: backend().delete_job(job)

  ## TaskExecution functions

  @doc """
  Returns the list of task_executions.
  """
  def list_task_executions, do: backend().list_task_executions()

  @doc """
  Returns the list of task executions for a specific job.
  """
  def list_task_executions_for_job(job_id), do: backend().list_task_executions_for_job(job_id)

  @doc """
  Gets a single task_execution.

  Raises `Ecto.NoResultsError` if the TaskExecution does not exist.
  """
  def get_task_execution!(id), do: backend().get_task_execution!(id)

  @doc """
  Creates a task_execution.
  """
  def create_task_execution(attrs \\ %{}), do: backend().create_task_execution(attrs)

  @doc """
  Updates a task_execution.
  """
  def update_task_execution(%TaskExecution{} = task_execution, attrs) do
    backend().update_task_execution(task_execution, attrs)
  end

  @doc """
  Deletes a task_execution.
  """
  def delete_task_execution(%TaskExecution{} = task_execution) do
    backend().delete_task_execution(task_execution)
  end

  @doc """
  Atomically claims a task for execution by a worker.

  Returns {:ok, :claimed} if successfully claimed.
  Returns {:error, :already_claimed} if already claimed by another worker.
  Returns {:error, :already_completed} if task is already completed.
  """
  def claim_task(job_id, task_id, worker_id) do
    backend().claim_task(job_id, task_id, worker_id)
  end

  @doc """
  Gets the current job state computed from task executions.

  Returns a map with:
  - :pending_tasks - MapSet of task IDs still pending
  - :running_tasks - Map of task_id => worker_node for running tasks
  - :completed_tasks - MapSet of successfully completed task IDs
  - :failed_tasks - MapSet of failed task IDs
  - :skipped_tasks - MapSet of skipped task IDs (upstream_failed)
  """
  def get_job_state(job_id), do: backend().get_job_state(job_id)

  ## WorkerHeartbeat functions

  @doc """
  Records or updates a worker heartbeat.
  """
  def upsert_worker_heartbeat(node, capacity, active_tasks) do
    backend().upsert_worker_heartbeat(node, capacity, active_tasks)
  end

  @doc """
  Gets all active worker heartbeats.
  Returns workers that have been seen in the last 30 seconds.
  """
  def get_active_workers, do: backend().get_active_workers()

  @doc """
  Gets a specific worker heartbeat by node name.
  """
  def get_worker_heartbeat(node), do: backend().get_worker_heartbeat(node)
end
