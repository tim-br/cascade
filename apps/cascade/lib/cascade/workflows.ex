defmodule Cascade.Workflows do
  @moduledoc """
  The Workflows context.

  Provides functions for managing DAGs, Jobs, and TaskExecutions.
  """

  import Ecto.Query, warn: false
  alias Cascade.Repo

  alias Cascade.Workflows.{DAG, Job, TaskExecution}

  ## DAG functions

  @doc """
  Returns the list of dags.

  ## Examples

      iex> list_dags()
      [%DAG{}, ...]

  """
  def list_dags do
    Repo.all(DAG)
  end

  @doc """
  Returns the list of enabled dags.
  """
  def list_enabled_dags do
    DAG
    |> where([d], d.enabled == true)
    |> Repo.all()
  end

  @doc """
  Gets a single dag.

  Raises `Ecto.NoResultsError` if the DAG does not exist.

  ## Examples

      iex> get_dag!(123)
      %DAG{}

      iex> get_dag!(456)
      ** (Ecto.NoResultsError)

  """
  def get_dag!(id), do: Repo.get!(DAG, id)

  @doc """
  Gets a dag by name.
  """
  def get_dag_by_name(name) do
    Repo.get_by(DAG, name: name)
  end

  @doc """
  Creates a dag.

  ## Examples

      iex> create_dag(%{field: value})
      {:ok, %DAG{}}

      iex> create_dag(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_dag(attrs \\ %{}) do
    %DAG{}
    |> DAG.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a dag.

  ## Examples

      iex> update_dag(dag, %{field: new_value})
      {:ok, %DAG{}}

      iex> update_dag(dag, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_dag(%DAG{} = dag, attrs) do
    dag
    |> DAG.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a dag.

  ## Examples

      iex> delete_dag(dag)
      {:ok, %DAG{}}

      iex> delete_dag(dag)
      {:error, %Ecto.Changeset{}}

  """
  def delete_dag(%DAG{} = dag) do
    Repo.delete(dag)
  end

  ## Job functions

  @doc """
  Returns the list of jobs.
  """
  def list_jobs do
    Repo.all(Job)
  end

  @doc """
  Returns the list of jobs for a specific DAG.
  """
  def list_jobs_for_dag(dag_id) do
    Job
    |> where([j], j.dag_id == ^dag_id)
    |> order_by([j], desc: j.inserted_at)
    |> Repo.all()
  end

  @doc """
  Returns the list of active (running or pending) jobs.
  """
  def list_active_jobs do
    Job
    |> where([j], j.status in [:pending, :running])
    |> Repo.all()
  end

  @doc """
  Gets a single job.

  Raises `Ecto.NoResultsError` if the Job does not exist.
  """
  def get_job!(id), do: Repo.get!(Job, id)

  @doc """
  Gets a job with preloaded associations.
  """
  def get_job_with_details!(id) do
    Job
    |> where([j], j.id == ^id)
    |> preload([:dag, :task_executions])
    |> Repo.one!()
  end

  @doc """
  Creates a job.
  """
  def create_job(attrs \\ %{}) do
    %Job{}
    |> Job.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a job.
  """
  def update_job(%Job{} = job, attrs) do
    job
    |> Job.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a job.
  """
  def delete_job(%Job{} = job) do
    Repo.delete(job)
  end

  ## TaskExecution functions

  @doc """
  Returns the list of task_executions.
  """
  def list_task_executions do
    Repo.all(TaskExecution)
  end

  @doc """
  Returns the list of task executions for a specific job.
  """
  def list_task_executions_for_job(job_id) do
    TaskExecution
    |> where([te], te.job_id == ^job_id)
    |> order_by([te], asc: te.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a single task_execution.

  Raises `Ecto.NoResultsError` if the TaskExecution does not exist.
  """
  def get_task_execution!(id), do: Repo.get!(TaskExecution, id)

  @doc """
  Creates a task_execution.
  """
  def create_task_execution(attrs \\ %{}) do
    %TaskExecution{}
    |> TaskExecution.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a task_execution.
  """
  def update_task_execution(%TaskExecution{} = task_execution, attrs) do
    task_execution
    |> TaskExecution.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a task_execution.
  """
  def delete_task_execution(%TaskExecution{} = task_execution) do
    Repo.delete(task_execution)
  end
end
