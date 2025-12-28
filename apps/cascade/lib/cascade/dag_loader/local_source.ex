defmodule Cascade.DagLoader.LocalSource do
  @moduledoc """
  Loads DAG definitions from a local directory.

  Scans for .json and .exs files in the specified directory.
  """

  require Logger

  @doc """
  Load all DAG files from local directory.

  Returns list of {name, content, source_info} tuples.
  """
  def load_dags(%{type: :local, path: dags_dir}) do
    Logger.debug("📂 [LOCAL_SOURCE] Scanning directory: #{dags_dir}")

    case File.ls(dags_dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&valid_extension?/1)
        |> Enum.map(fn filename ->
          load_dag_file(dags_dir, filename)
        end)
        |> Enum.reject(&is_nil/1)

      {:error, reason} ->
        Logger.error("Failed to list directory #{dags_dir}: #{inspect(reason)}")
        []
    end
  end

  defp valid_extension?(filename) do
    ext = Path.extname(filename)
    ext in [".json", ".exs"]
  end

  defp load_dag_file(dags_dir, filename) do
    file_path = Path.join(dags_dir, filename)

    case File.read(file_path) do
      {:ok, content} ->
        name = Path.rootname(filename)
        extension = Path.extname(filename)

        source_info = %{
          source: "local:#{file_path}",
          extension: extension,
          filename: filename,
          path: file_path
        }

        {name, content, source_info}

      {:error, reason} ->
        Logger.error("Failed to read DAG file #{file_path}: #{inspect(reason)}")
        nil
    end
  end
end
