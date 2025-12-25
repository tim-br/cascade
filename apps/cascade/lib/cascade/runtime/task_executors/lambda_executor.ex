defmodule Cascade.Runtime.TaskExecutors.LambdaExecutor do
  @moduledoc """
  Executes tasks on AWS Lambda.

  This executor:
  - Invokes the specified Lambda function
  - Passes the task payload and context
  - Optionally stores results in S3 for large outputs
  - Handles Lambda-specific errors and timeouts
  """

  require Logger
  alias Cascade.AWS.{LambdaClient, S3Client}

  @doc """
  Executes a task on AWS Lambda.

  ## Parameters
    - task_config: Task configuration containing Lambda function details
    - payload: Execution payload with job_id, task_id, context

  ## Task Config
    - "function_name" (required): Lambda function name or ARN
    - "timeout" (optional): Execution timeout in seconds, default: 300
    - "memory" (optional): Memory allocation (informational)
    - "invocation_type" (optional): "sync" or "async", default: "sync"
    - "store_output_to_s3" (optional): Whether to store results in S3, default: false
    - "output_s3_key" (optional): S3 key pattern for output, supports {{job_id}}, {{task_id}}

  ## Returns
    - {:ok, result} on success
    - {:error, reason} on failure
  """
  def execute(task_config, payload) do
    function_name = get_config(task_config, "function_name")
    timeout = get_config(task_config, "timeout", 300) * 1000  # Convert to milliseconds
    invocation_type = String.to_atom(get_config(task_config, "invocation_type", "sync"))
    store_to_s3 = get_config(task_config, "store_output_to_s3", false)

    if is_nil(function_name) do
      {:error, "No Lambda function name specified"}
    else
      execute_lambda(function_name, payload, task_config, invocation_type, timeout, store_to_s3)
    end
  end

  # Private functions

  defp execute_lambda(function_name, payload, task_config, invocation_type, timeout, store_to_s3) do
    job_id = payload.job_id
    task_id = payload.task_id
    context = Map.get(payload, :context, %{})

    # Build Lambda payload
    lambda_payload = LambdaClient.build_payload(
      job_id,
      task_id,
      context,
      task_config
    )

    # Invoke Lambda
    result = LambdaClient.invoke(
      function_name,
      lambda_payload,
      invocation_type: invocation_type,
      timeout: timeout
    )

    case result do
      {:ok, :async_invoked} ->
        Logger.info("LambdaExecutor: Async invocation successful for #{function_name}")
        {:ok, %{status: "async_invoked", function: function_name}}

      {:ok, lambda_result} ->
        handle_lambda_result(lambda_result, job_id, task_id, store_to_s3, task_config)

      {:error, {:function_error, error_type, message}} ->
        error_msg = "Lambda function error (#{error_type}): #{message}"
        Logger.error("LambdaExecutor: #{error_msg}")
        {:error, error_msg}

      {:error, :rate_limited} ->
        Logger.warning("LambdaExecutor: Rate limited - task should be retried")
        {:error, "AWS Lambda rate limit exceeded"}

      {:error, reason} ->
        error_msg = "Lambda invocation failed: #{inspect(reason)}"
        Logger.error("LambdaExecutor: #{error_msg}")
        {:error, error_msg}
    end
  end

  defp handle_lambda_result(lambda_result, job_id, task_id, store_to_s3, task_config) do
    if store_to_s3 do
      store_result_to_s3(lambda_result, job_id, task_id, task_config)
    else
      {:ok, lambda_result}
    end
  end

  defp store_result_to_s3(result, job_id, task_id, task_config) do
    # Generate S3 key for output
    s3_key = get_output_s3_key(task_config, job_id, task_id)

    # Encode result as JSON
    case Jason.encode(result) do
      {:ok, json_data} ->
        # Upload to S3
        case S3Client.upload(s3_key, json_data, content_type: "application/json") do
          {:ok, location} ->
            Logger.info("LambdaExecutor: Stored result to #{location}")

            # Return reference to S3 location instead of full result
            {:ok, %{
              "result_location" => location,
              "result_s3_key" => s3_key,
              "result_size_bytes" => byte_size(json_data)
            }}

          {:error, reason} ->
            Logger.error("LambdaExecutor: Failed to store result to S3: #{inspect(reason)}")
            # Fall back to returning result directly
            {:ok, result}
        end

      {:error, reason} ->
        Logger.error("LambdaExecutor: Failed to encode result as JSON: #{inspect(reason)}")
        {:ok, result}
    end
  end

  defp get_output_s3_key(task_config, job_id, task_id) do
    pattern = get_config(task_config, "output_s3_key", "results/{{job_id}}/{{task_id}}.json")

    pattern
    |> String.replace("{{job_id}}", job_id)
    |> String.replace("{{task_id}}", task_id)
  end

  defp get_config(task_config, key, default \\ nil) do
    # Check both top-level and nested config
    task_config[key] || get_in(task_config, ["config", key]) || default
  end
end
