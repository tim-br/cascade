defmodule Cascade.DagLoader.Validator do
  @moduledoc """
  Validates DAG definitions before loading.

  Ensures DAG has required fields and valid structure.
  """

  require Logger

  @required_fields ["nodes"]

  @doc """
  Validate a DAG definition.

  Returns :ok if valid, {:error, reason} otherwise.
  """
  def validate_dag(dag_definition) when is_map(dag_definition) do
    with :ok <- validate_required_fields(dag_definition),
         :ok <- validate_nodes(dag_definition),
         :ok <- validate_edges(dag_definition),
         :ok <- validate_no_cycles(dag_definition) do
      :ok
    end
  end

  def validate_dag(_) do
    {:error, "DAG definition must be a map"}
  end

  defp validate_required_fields(dag_definition) do
    missing_fields =
      Enum.filter(@required_fields, fn field ->
        not Map.has_key?(dag_definition, field)
      end)

    if Enum.empty?(missing_fields) do
      :ok
    else
      {:error, "Missing required fields: #{Enum.join(missing_fields, ", ")}"}
    end
  end

  defp validate_nodes(dag_definition) do
    nodes = Map.get(dag_definition, "nodes", [])

    cond do
      not is_list(nodes) ->
        {:error, "nodes must be a list"}

      Enum.empty?(nodes) ->
        {:error, "DAG must have at least one node"}

      true ->
        # Validate each node has required fields
        invalid_nodes =
          Enum.filter(nodes, fn node ->
            not (is_map(node) and Map.has_key?(node, "id") and Map.has_key?(node, "type"))
          end)

        if Enum.empty?(invalid_nodes) do
          # Check for duplicate node IDs
          node_ids = Enum.map(nodes, & &1["id"])
          duplicate_ids = node_ids -- Enum.uniq(node_ids)

          if Enum.empty?(duplicate_ids) do
            :ok
          else
            {:error, "Duplicate node IDs: #{Enum.join(duplicate_ids, ", ")}"}
          end
        else
          {:error, "All nodes must have 'id' and 'type' fields"}
        end
    end
  end

  defp validate_edges(dag_definition) do
    edges = Map.get(dag_definition, "edges", [])
    nodes = Map.get(dag_definition, "nodes", [])
    node_ids = MapSet.new(nodes, & &1["id"])

    cond do
      not is_list(edges) ->
        {:error, "edges must be a list"}

      true ->
        # Validate each edge references existing nodes
        invalid_edges =
          Enum.filter(edges, fn edge ->
            not (is_map(edge) and
                   Map.has_key?(edge, "from") and
                   Map.has_key?(edge, "to") and
                   MapSet.member?(node_ids, edge["from"]) and
                   MapSet.member?(node_ids, edge["to"]))
          end)

        if Enum.empty?(invalid_edges) do
          :ok
        else
          {:error, "All edges must have valid 'from' and 'to' node IDs"}
        end
    end
  end

  defp validate_no_cycles(dag_definition) do
    nodes = Map.get(dag_definition, "nodes", [])
    edges = Map.get(dag_definition, "edges", [])

    # Build adjacency list
    graph =
      Enum.reduce(edges, %{}, fn edge, acc ->
        from = edge["from"]
        to = edge["to"]
        Map.update(acc, from, [to], &[to | &1])
      end)

    # Try topological sort - if it fails, there's a cycle
    node_ids = Enum.map(nodes, & &1["id"])

    case topological_sort(node_ids, graph) do
      {:ok, _sorted} ->
        :ok

      {:error, :cycle} ->
        {:error, "DAG contains a cycle (circular dependency)"}
    end
  end

  # Simple topological sort using Kahn's algorithm
  defp topological_sort(nodes, graph) do
    # Calculate in-degrees
    in_degrees =
      Enum.reduce(nodes, %{}, fn node, acc ->
        Map.put(acc, node, 0)
      end)

    in_degrees =
      Enum.reduce(graph, in_degrees, fn {_from, tos}, acc ->
        Enum.reduce(tos, acc, fn to, acc2 ->
          Map.update(acc2, to, 1, &(&1 + 1))
        end)
      end)

    # Find nodes with no incoming edges
    queue =
      Enum.filter(nodes, fn node ->
        Map.get(in_degrees, node, 0) == 0
      end)

    do_topological_sort(queue, graph, in_degrees, [])
  end

  defp do_topological_sort([], _graph, in_degrees, sorted) do
    # Check if all nodes were processed
    if Enum.all?(in_degrees, fn {_node, degree} -> degree == 0 end) do
      {:ok, Enum.reverse(sorted)}
    else
      {:error, :cycle}
    end
  end

  defp do_topological_sort([node | rest], graph, in_degrees, sorted) do
    # Mark this node as processed
    in_degrees = Map.put(in_degrees, node, 0)

    # Reduce in-degrees of neighbors
    neighbors = Map.get(graph, node, [])

    {new_queue, new_in_degrees} =
      Enum.reduce(neighbors, {rest, in_degrees}, fn neighbor, {queue_acc, degrees_acc} ->
        new_degree = Map.get(degrees_acc, neighbor, 1) - 1
        degrees_acc = Map.put(degrees_acc, neighbor, new_degree)

        # Add to queue if in-degree becomes 0
        if new_degree == 0 do
          {[neighbor | queue_acc], degrees_acc}
        else
          {queue_acc, degrees_acc}
        end
      end)

    do_topological_sort(new_queue, graph, new_in_degrees, [node | sorted])
  end
end
