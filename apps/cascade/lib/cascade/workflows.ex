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
    DAG
    |> order_by([d], asc: d.name)
    |> Repo.all()
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
