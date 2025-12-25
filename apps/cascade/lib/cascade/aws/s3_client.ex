defmodule Cascade.AWS.S3Client do
  @moduledoc """
  S3 client for storing and retrieving task artifacts.

  Provides functions to:
  - Upload task results to S3
  - Download task inputs from S3
  - Generate pre-signed URLs for large files
  """

  require Logger
  alias Cascade.AWS.Config

  @doc """
  Uploads data to S3.

  ## Parameters
    - key: The S3 key (path) for the object
    - data: The data to upload (string or binary)
    - opts: Optional parameters
      - :content_type - MIME type (default: "application/json")
      - :metadata - Map of metadata key-value pairs

  ## Returns
    - {:ok, location} on success
    - {:error, reason} on failure
  """
  def upload(key, data, opts \\ []) do
    bucket = Config.s3_bucket()
    content_type = Keyword.get(opts, :content_type, "application/json")
    metadata = Keyword.get(opts, :metadata, %{})

    Logger.info("S3Client: Uploading to s3://#{bucket}/#{key}")

    request =
      ExAws.S3.put_object(bucket, key, data,
        content_type: content_type,
        metadata: metadata
      )

    case ExAws.request(request) do
      {:ok, %{status_code: 200}} ->
        location = "s3://#{bucket}/#{key}"
        Logger.info("S3Client: Upload successful: #{location}")
        {:ok, location}

      {:ok, response} ->
        Logger.error("S3Client: Upload failed with status #{response.status_code}")
        {:error, "S3 upload failed: HTTP #{response.status_code}"}

      {:error, reason} ->
        Logger.error("S3Client: Upload error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Downloads data from S3.

  ## Parameters
    - key: The S3 key (path) for the object

  ## Returns
    - {:ok, data} on success
    - {:error, reason} on failure
  """
  def download(key) do
    bucket = Config.s3_bucket()

    Logger.info("S3Client: Downloading from s3://#{bucket}/#{key}")

    request = ExAws.S3.get_object(bucket, key)

    case ExAws.request(request) do
      {:ok, %{status_code: 200, body: body}} ->
        Logger.info("S3Client: Download successful")
        {:ok, body}

      {:ok, response} ->
        Logger.error("S3Client: Download failed with status #{response.status_code}")
        {:error, "S3 download failed: HTTP #{response.status_code}"}

      {:error, reason} ->
        Logger.error("S3Client: Download error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Downloads and decodes JSON data from S3.

  ## Parameters
    - key: The S3 key (path) for the JSON object

  ## Returns
    - {:ok, decoded_data} on success
    - {:error, reason} on failure
  """
  def download_json(key) do
    case download(key) do
      {:ok, body} ->
        case Jason.decode(body) do
          {:ok, data} -> {:ok, data}
          {:error, reason} -> {:error, "Failed to decode JSON: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Generates a pre-signed URL for downloading an S3 object.

  ## Parameters
    - key: The S3 key (path) for the object
    - expires_in: Expiration time in seconds (default: 3600 = 1 hour)

  ## Returns
    - {:ok, url} on success
    - {:error, reason} on failure
  """
  def presigned_url(key, expires_in \\ 3600) do
    bucket = Config.s3_bucket()

    {:ok, url} = ExAws.Config.new(:s3)
                 |> ExAws.S3.presigned_url(:get, bucket, key, expires_in: expires_in)

    Logger.info("S3Client: Generated presigned URL for #{key} (expires in #{expires_in}s)")
    {:ok, url}
  rescue
    error ->
      Logger.error("S3Client: Failed to generate presigned URL: #{inspect(error)}")
      {:error, error}
  end

  @doc """
  Deletes an object from S3.

  ## Parameters
    - key: The S3 key (path) for the object

  ## Returns
    - :ok on success
    - {:error, reason} on failure
  """
  def delete(key) do
    bucket = Config.s3_bucket()

    Logger.info("S3Client: Deleting s3://#{bucket}/#{key}")

    request = ExAws.S3.delete_object(bucket, key)

    case ExAws.request(request) do
      {:ok, %{status_code: 204}} ->
        Logger.info("S3Client: Delete successful")
        :ok

      {:ok, response} ->
        Logger.error("S3Client: Delete failed with status #{response.status_code}")
        {:error, "S3 delete failed: HTTP #{response.status_code}"}

      {:error, reason} ->
        Logger.error("S3Client: Delete error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Constructs an S3 artifact key for a job/task.

  ## Parameters
    - job_id: The job ID
    - task_id: The task ID
    - filename: Optional filename (default: "result.json")

  ## Returns
    - S3 key string
  """
  def artifact_key(job_id, task_id, filename \\ "result.json") do
    "artifacts/#{job_id}/#{task_id}/#{filename}"
  end
end
