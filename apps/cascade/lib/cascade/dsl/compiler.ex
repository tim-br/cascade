defmodule Cascade.DSL.Compiler do
  @moduledoc """
  Compiles the DSL into a language-agnostic JSON representation.
  The compiled format is:
  %{
    "name" => "dag_name",
    "nodes" => [%{"id" => "task1", "type" => "local", "config" => %{...}}],
    "edges" => [%{"from" => "task1", "to" => "task2"}],
    "metadata" => %{"description" => "...", "schedule" => "..."}
  }
  """

  @doc """
  Compiles the DAG definition from DSL format to JSON format.
  """
  def compile(dag_name, tasks, _module, opts \\ []) do
    IO.puts("IN COMPILE")
    IO.inspect(tasks, label: "RAW TASKS IN COMPILER")
    # Reverse tasks because they're accumulated in reverse order
    tasks = Enum.reverse(tasks)

    # Extract metadata from opts (keyword list)
    description = Keyword.get(opts, :description)
    schedule = Keyword.get(opts, :schedule)

    # Build nodes from tasks
    nodes =
      Enum.map(tasks, fn {task_id, config} ->
        %{
          "id" => to_string(task_id),
          "type" => to_string(config[:type] || :local),
          "config" => build_task_config(config)
        }
      end)

    # Build edges from dependencies
    edges = build_edges(tasks)

    # Compile into JSON structure
    return = %{
      "name" => dag_name,
      "nodes" => nodes,
      "edges" => edges,
      "metadata" => %{
        "description" => description,
        "schedule" => schedule
      }
    }

    IO.inspect(return, label: "RETURN VALUE")
    return
  end

  defp build_task_config(config) do
    config
    |> Map.drop([:id, :type, :depends_on])
    |> Enum.map(fn {k, v} -> {to_string(k), normalize_value(v)} end)
    |> Map.new()
  end

  defp normalize_value(value) when is_boolean(value), do: value
  defp normalize_value(nil), do: nil

  defp normalize_value(value) when is_atom(value) do
    if Atom.to_string(value) |> String.starts_with?("Elixir.") do
      value
      |> Module.split()
      |> Enum.join(".")
    else
      to_string(value)
    end
  end

  defp normalize_value(value) when is_list(value), do: Enum.map(value, &normalize_value/1)
  defp normalize_value(value), do: value

  defp build_edges(tasks) do
    tasks
    |> Enum.flat_map(fn {task_id, config} ->
      deps = config[:depends_on] || []

      Enum.map(deps, fn dep ->
        %{
          "from" => to_string(dep),
          "to" => to_string(task_id),
          "type" => "success"
        }
      end)
    end)
  end
end
