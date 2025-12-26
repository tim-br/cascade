#!/usr/bin/env elixir

# Load the literary analysis DAG

alias Cascade.Examples.DAGLoader

IO.puts("\n=== Loading Literary Analysis DAG ===\n")

case DAGLoader.load_literary_analysis_dag() do
  {:ok, dag} ->
    IO.puts("✓ Literary Analysis DAG loaded successfully!")
    IO.puts("  Name: #{dag.name}")
    IO.puts("  Description: #{dag.description}")
    IO.puts("  Version: #{dag.version}")
    IO.puts("  Tasks: #{length(dag.definition["nodes"])}")
    IO.puts("  Enabled: #{dag.enabled}")
    IO.puts("\n=== Task List ===")

    dag.definition["nodes"]
    |> Enum.each(fn node ->
      deps = if node["depends_on"], do: " (depends on: #{inspect(node["depends_on"])})", else: ""
      IO.puts("  - #{node["id"]}: #{node["type"]}#{deps}")
    end)

    IO.puts("\n✓ DAG is ready for execution!")

  {:error, reason} ->
    IO.puts("✗ Failed to load DAG: #{inspect(reason)}")
    System.halt(1)
end
