defmodule Cascade.DagLoader.S3Source do
  @moduledoc """
  Loads DAG definitions from an S3 bucket.

  Scans for .json and .exs files in the specified bucket/prefix.
  """

  require Logger

  @doc """
  Load all DAG files from S3 bucket.

  Returns list of {name, content, source_info} tuples.
  """
  def load_dags(%{type: :s3, bucket: bucket, prefix: prefix}) do
    Logger.debug("☁️  [S3_SOURCE] Scanning S3: s3://#{bucket}/#{prefix}")

    case list_s3_objects(bucket, prefix) do
      {:ok, objects} ->
        objects
        |> Enum.filter(&valid_extension?/1)
        |> Enum.map(fn object ->
          load_dag_from_s3(bucket, object)
        end)
        |> Enum.reject(&is_nil/1)

      {:error, reason} ->
        Logger.error("Failed to list S3 bucket #{bucket}/#{prefix}: #{inspect(reason)}")
        []
    end
  end

  defp list_s3_objects(bucket, prefix) do
    request =
      ExAws.S3.list_objects_v2(bucket, prefix: prefix)

    case ExAws.request(request) do
      {:ok, %{body: %{contents: contents}}} ->
        keys = Enum.map(contents, & &1.key)
        {:ok, keys}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error ->
      Logger.error("Exception listing S3 objects: #{inspect(error)}")
      {:error, error}
  end

  defp valid_extension?(key) do
    ext = Path.extname(key)
    ext in [".json", ".exs"]
  end

  defp load_dag_from_s3(bucket, key) do
    request = ExAws.S3.get_object(bucket, key)

    case ExAws.request(request) do
      {:ok, %{body: content}} ->
        # Extract name from key (remove prefix and extension)
        name =
          key
          |> Path.basename()
          |> Path.rootname()

        extension = Path.extname(key)

        source_info = %{
          source: "s3://#{bucket}/#{key}",
          extension: extension,
          bucket: bucket,
          key: key
        }

        {name, content, source_info}

      {:error, reason} ->
        Logger.error("Failed to read S3 object #{bucket}/#{key}: #{inspect(reason)}")
        nil
    end
  rescue
    error ->
      Logger.error("Exception reading S3 object #{bucket}/#{key}: #{inspect(error)}")
      nil
  end
end
