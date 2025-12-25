defmodule Cascade.DSL.Validator do
  @moduledoc """
  Validates DAG definitions.

  Ensures:
  - No cycles in the dependency graph
  - All dependencies reference valid tasks
  - Task IDs are unique
  - Required fields are present
  """

  @doc """
  Validates a compiled DAG definition.

  Returns `{:ok, definition}` if valid, `{:error, reason}` otherwise.
  """
  def validate(definition) do
    with :ok <- validate_structure(definition),
         :ok <- validate_node_ids(definition),
         :ok <- validate_dependencies(definition),
         :ok <- validate_acyclic(definition) do
      {:ok, definition}
    end
  end

  defp validate_structure(%{"nodes" => nodes, "edges" => edges}) when is_list(nodes) and is_list(edges) do
    :ok
  end

  defp validate_structure(_) do
    {:error, "DAG definition must have 'nodes' and 'edges' lists"}
  end

  defp validate_node_ids(%{"nodes" => nodes}) do
    ids = Enum.map(nodes, & &1["id"])
    unique_ids = Enum.uniq(ids)

    if length(ids) == length(unique_ids) do
      :ok
    else
      duplicates = ids -- unique_ids
      {:error, "Duplicate task IDs found: #{inspect(duplicates)}"}
    end
  end

  defp validate_dependencies(%{"nodes" => nodes, "edges" => edges}) do
    node_ids = MapSet.new(nodes, & &1["id"])

    invalid_deps =
      edges
      |> Enum.flat_map(fn edge -> [edge["from"], edge["to"]] end)
      |> Enum.reject(&MapSet.member?(node_ids, &1))
      |> Enum.uniq()

    if Enum.empty?(invalid_deps) do
      :ok
    else
      {:error, "Invalid task dependencies: #{inspect(invalid_deps)}"}
    end
  end

  defp validate_acyclic(%{"nodes" => nodes, "edges" => edges}) do
    # Build a graph using libgraph
    graph =
      Enum.reduce(nodes, Graph.new(), fn node, g ->
        Graph.add_vertex(g, node["id"])
      end)

    graph =
      Enum.reduce(edges, graph, fn edge, g ->
        Graph.add_edge(g, edge["from"], edge["to"])
      end)

    if Graph.is_acyclic?(graph) do
      :ok
    else
      {:error, "DAG contains cycles"}
    end
  end

  @doc """
  Performs topological sort on a DAG definition.

  Returns `{:ok, sorted_task_ids}` or `{:error, reason}`.
  """
  def topological_sort(%{"nodes" => nodes, "edges" => edges}) do
    graph =
      Enum.reduce(nodes, Graph.new(), fn node, g ->
        Graph.add_vertex(g, node["id"])
      end)

    graph =
      Enum.reduce(edges, graph, fn edge, g ->
        Graph.add_edge(g, edge["from"], edge["to"])
      end)

    case Graph.topsort(graph) do
      false -> {:error, "Cannot perform topological sort, graph contains cycles"}
      sorted -> {:ok, sorted}
    end
  end

  @doc """
  Gets tasks that are ready to run (no pending dependencies).

  Returns list of task IDs that have no pending dependencies.
  """
  def get_ready_tasks(definition, completed_tasks, failed_tasks \\ []) do
    completed_set = MapSet.new(completed_tasks)
    failed_set = MapSet.new(failed_tasks)

    definition["nodes"]
    |> Enum.map(& &1["id"])
    |> Enum.reject(&MapSet.member?(completed_set, &1))
    |> Enum.reject(&MapSet.member?(failed_set, &1))
    |> Enum.filter(fn task_id ->
      dependencies = get_task_dependencies(definition, task_id)
      Enum.all?(dependencies, &MapSet.member?(completed_set, &1))
    end)
  end

  @doc """
  Gets the dependencies for a specific task.
  """
  def get_task_dependencies(definition, task_id) do
    definition["edges"]
    |> Enum.filter(&(&1["to"] == task_id))
    |> Enum.map(& &1["from"])
  end
end
