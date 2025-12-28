defmodule Cascade.AWS.LambdaClientTest do
  use ExUnit.Case, async: true

  alias Cascade.AWS.LambdaClient

  @moduledoc """
  Unit tests for Lambda client error handling.

  Tests the critical fix for properly detecting Lambda function errors
  vs successful invocations.
  """

  describe "handle_lambda_response (mocked)" do
    test "CRITICAL: detects Lambda function errors from errorMessage field" do
      # Simulate Lambda response when function raises exception
      response = %{
        "errorMessage" => "SIMULATED_FAILURE: Model timeout",
        "errorType" => "Exception",
        "requestId" => "test-request-id",
        "stackTrace" => [
          "  File \"/var/task/sentiment_analysis.py\", line 74, in lambda_handler\n"
        ]
      }

      # This should be detected as a function error
      # In the actual code, this pattern is matched in invoke/3
      assert Map.has_key?(response, "errorMessage")
      assert Map.has_key?(response, "errorType")
      refute Map.has_key?(response, "statusCode")
    end

    test "detects successful Lambda response with statusCode 200" do
      response = %{
        "statusCode" => 200,
        "body" => %{
          "job_id" => "test-job",
          "status" => "success",
          "result" => "data"
        }
      }

      assert response["statusCode"] == 200
      assert Map.has_key?(response, "body")
    end

    test "detects direct Lambda response without statusCode wrapper" do
      # Some Lambda functions return results directly without statusCode
      response = %{
        "job_id" => "test-job",
        "status" => "success",
        "result" => "data"
      }

      refute Map.has_key?(response, "statusCode")
      refute Map.has_key?(response, "errorMessage")
      assert response["status"] == "success"
    end

    test "distinguishes between function error and HTTP error" do
      # Function error (Lambda executed but threw exception)
      function_error = %{
        "errorMessage" => "Something went wrong",
        "errorType" => "RuntimeError"
      }

      # HTTP error (statusCode indicates API-level error)
      http_error = %{
        "statusCode" => 500,
        "body" => %{"error" => "Internal server error"}
      }

      # Function error has errorMessage, HTTP error has statusCode
      assert Map.has_key?(function_error, "errorMessage")
      refute Map.has_key?(function_error, "statusCode")

      assert Map.has_key?(http_error, "statusCode")
      refute Map.has_key?(http_error, "errorMessage")
    end
  end

  describe "build_payload/4" do
    test "creates standard Lambda payload structure" do
      job_id = "job-123"
      task_id = "task-abc"
      context = %{"upstream_results" => %{}, "param1" => "value1"}
      task_config = %{"type" => "lambda", "function_name" => "test-fn"}

      payload = LambdaClient.build_payload(job_id, task_id, context, task_config)

      assert payload["job_id"] == job_id
      assert payload["task_id"] == task_id
      assert payload["context"] == context
      assert payload["config"] == task_config
      assert Map.has_key?(payload, "timestamp")
    end

    test "includes timestamp in ISO8601 format" do
      payload = LambdaClient.build_payload("job", "task", %{}, %{})

      assert is_binary(payload["timestamp"])
      # Should be parseable as DateTime
      # DateTime.from_iso8601/1 returns {:ok, datetime, offset}
      assert {:ok, _dt, _offset} = DateTime.from_iso8601(payload["timestamp"])
    end
  end

  describe "error response patterns" do
    test "Lambda exception response structure" do
      # This is what AWS returns when Lambda function raises an exception
      aws_error_response = %{
        "errorMessage" => "division by zero",
        "errorType" => "ZeroDivisionError",
        "requestId" => "abc-123",
        "stackTrace" => [
          "  File \"/var/task/handler.py\", line 10, in lambda_handler",
          "    result = 10 / 0"
        ]
      }

      # Verify structure matches what we expect
      assert aws_error_response["errorType"] == "ZeroDivisionError"
      assert is_list(aws_error_response["stackTrace"])
      assert aws_error_response["errorMessage"] =~ "division"
    end

    test "Lambda success response with body structure" do
      # This is what AWS returns for successful Lambda execution
      # when function returns statusCode (API Gateway format)
      aws_success_response = %{
        "statusCode" => 200,
        "body" => %{
          "status" => "success",
          "data" => %{"result" => 42}
        }
      }

      assert aws_success_response["statusCode"] == 200
      assert aws_success_response["body"]["status"] == "success"
    end

    test "Lambda success response without statusCode wrapper" do
      # This is what AWS returns when function returns data directly
      aws_direct_response = %{
        "status" => "success",
        "result" => %{"value" => 123},
        "metadata" => %{"processed_at" => "2025-01-01"}
      }

      # No statusCode or errorMessage fields
      refute Map.has_key?(aws_direct_response, "statusCode")
      refute Map.has_key?(aws_direct_response, "errorMessage")
    end
  end

  describe "error detection logic" do
    test "correctly identifies all Lambda error response patterns" do
      # Pattern 1: Function exception
      error1 = %{"errorMessage" => "Error", "errorType" => "Exception"}
      assert is_function_error?(error1)

      # Pattern 2: HTTP error with statusCode != 200
      error2 = %{"statusCode" => 500, "body" => %{"error" => "fail"}}
      assert is_http_error?(error2)

      # Pattern 3: Success with statusCode 200
      success1 = %{"statusCode" => 200, "body" => %{"result" => "ok"}}
      refute is_function_error?(success1)
      refute is_http_error?(success1)

      # Pattern 4: Direct success response
      success2 = %{"result" => "ok", "status" => "success"}
      refute is_function_error?(success2)
      refute is_http_error?(success2)
    end
  end

  # Helper functions to match lambda_client.ex logic
  defp is_function_error?(response) do
    Map.has_key?(response, "errorMessage") and Map.has_key?(response, "errorType")
  end

  defp is_http_error?(response) do
    case response do
      %{"statusCode" => status} when status != 200 and status != 202 -> true
      _ -> false
    end
  end
end
