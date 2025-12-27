defmodule Cascade.AWS.LambdaClient do
  @moduledoc """
  Lambda client for invoking AWS Lambda functions.

  Provides functions to:
  - Invoke Lambda functions synchronously (RequestResponse)
  - Invoke Lambda functions asynchronously (Event)
  - Handle Lambda responses and errors
  """

  require Logger

  @default_timeout 300_000  # 5 minutes in milliseconds

  @doc """
  Invokes a Lambda function.

  ## Parameters
    - function_name: Name or ARN of the Lambda function
    - payload: Map or string to send as the event payload
    - opts: Optional parameters
      - :invocation_type - :sync (RequestResponse) or :async (Event), default: :sync
      - :timeout - Timeout in milliseconds, default: 300_000 (5 minutes)
      - :qualifier - Function version or alias, default: "$LATEST"

  ## Returns
    - {:ok, result} on success (for sync invocations)
    - {:ok, :async_invoked} on success (for async invocations)
    - {:error, reason} on failure
  """
  def invoke(function_name, payload, opts \\ []) do
    invocation_type = Keyword.get(opts, :invocation_type, :sync)
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    qualifier = Keyword.get(opts, :qualifier, "$LATEST")

    # Convert payload to JSON if it's a map
    json_payload = case payload do
      payload when is_binary(payload) -> payload
      payload when is_map(payload) -> Jason.encode!(payload)
    end

    Logger.info("🚀 [LAMBDA_CLIENT] Invoking #{function_name} (#{invocation_type})")
    Logger.debug("📦 [LAMBDA_PAYLOAD] #{json_payload}")

    # Map invocation type to AWS API parameter
    invoke_type = case invocation_type do
      :sync -> "RequestResponse"
      :async -> "Event"
    end

    # ExAws.Lambda.invoke expects a map for options
    opts = %{
      "InvocationType" => invoke_type,
      "Qualifier" => qualifier
    }

    request = ExAws.Lambda.invoke(function_name, json_payload, opts)

    case ExAws.request(request, recv_timeout: timeout) do
      {:ok, %{"statusCode" => 200, "body" => body} = response} ->
        handle_lambda_response(body, response, invocation_type)

      {:ok, %{"statusCode" => 202}} when invocation_type == :async ->
        Logger.info("LambdaClient: Async invocation successful")
        {:ok, :async_invoked}

      {:ok, response} ->
        status = response["statusCode"] || response[:status_code] || "unknown"
        Logger.error("❌ [LAMBDA_HTTP_ERROR] function=#{function_name}, status=#{status}")
        Logger.error("Full response: #{inspect(response, pretty: true, limit: :infinity)}")
        {:error, "Lambda invocation failed: HTTP #{status}"}

      {:error, {:http_error, 429, _}} ->
        Logger.error("LambdaClient: Rate limited by AWS Lambda")
        {:error, :rate_limited}

      {:error, {:http_error, status, message}} ->
        Logger.error("LambdaClient: HTTP error #{status}: #{inspect(message)}")
        {:error, "HTTP #{status}: #{inspect(message)}"}

      {:error, %{status_code: status, body: body}} ->
        # ExAws error response with status code
        Logger.error("LambdaClient: Lambda error #{status}: #{inspect(body)}")
        {:error, "Lambda error HTTP #{status}"}

      {:error, reason} ->
        Logger.error("LambdaClient: Invocation error: #{inspect(reason)}")
        {:error, inspect(reason)}
    end
  end

  @doc """
  Invokes a Lambda function asynchronously.

  This is a convenience wrapper around `invoke/3` with `invocation_type: :async`.

  ## Returns
    - {:ok, :async_invoked} on success
    - {:error, reason} on failure
  """
  def invoke_async(function_name, payload, opts \\ []) do
    opts = Keyword.put(opts, :invocation_type, :async)
    invoke(function_name, payload, opts)
  end

  # Private helpers

  defp handle_lambda_response(body, response, invocation_type) do
    # Check for function errors in the response headers (if headers exist)
    headers = response["headers"] || response[:headers] || %{}
    function_error = headers["x-amz-function-error"] || headers["X-Amz-Function-Error"]

    cond do
      # Function returned an error
      function_error ->
        handle_function_error(body, function_error)

      # Async invocation - no response body
      invocation_type == :async ->
        Logger.info("LambdaClient: Async invocation successful")
        {:ok, :async_invoked}

      # Sync invocation - parse response
      true ->
        handle_success_response(body)
    end
  end

  defp handle_function_error(body, error_type) when is_map(body) do
    Logger.error("LambdaClient: Lambda function error (#{error_type})")
    error_message = Map.get(body, "errorMessage", "Unknown error")
    Logger.error("LambdaClient: Error message: #{error_message}")
    {:error, {:function_error, error_type, error_message}}
  end

  defp handle_function_error(body, error_type) when is_binary(body) do
    Logger.error("LambdaClient: Lambda function error (#{error_type})")

    case Jason.decode(body) do
      {:ok, error_data} ->
        error_message = Map.get(error_data, "errorMessage", "Unknown error")
        Logger.error("LambdaClient: Error message: #{error_message}")
        {:error, {:function_error, error_type, error_message}}

      {:error, _} ->
        {:error, {:function_error, error_type, body}}
    end
  end

  defp handle_function_error(body, error_type) do
    Logger.error("LambdaClient: Lambda function error (#{error_type})")
    {:error, {:function_error, error_type, inspect(body)}}
  end

  defp handle_success_response(body) when is_map(body) do
    # Body is already decoded (ExAws did it for us)
    Logger.info("LambdaClient: Invocation successful")
    Logger.debug("LambdaClient: Result: #{inspect(body)}")
    {:ok, body}
  end

  defp handle_success_response(body) when is_binary(body) do
    # Body is a JSON string, decode it
    case Jason.decode(body) do
      {:ok, result} ->
        Logger.info("LambdaClient: Invocation successful")
        Logger.debug("LambdaClient: Result: #{inspect(result)}")
        {:ok, result}

      {:error, reason} ->
        # If JSON decode fails, return raw body
        Logger.warning("LambdaClient: Could not decode response as JSON: #{inspect(reason)}")
        {:ok, body}
    end
  end

  defp handle_success_response(body) do
    # Unknown body type, just return it
    Logger.info("LambdaClient: Invocation successful")
    {:ok, body}
  end

  @doc """
  Builds a standard Cascade Lambda payload.

  ## Parameters
    - job_id: The job ID
    - task_id: The task ID
    - context: Task execution context
    - task_config: Task configuration

  ## Returns
    - Map with standard payload structure
  """
  def build_payload(job_id, task_id, context, task_config) do
    %{
      "job_id" => job_id,
      "task_id" => task_id,
      "context" => context,
      "config" => task_config,
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end
end
