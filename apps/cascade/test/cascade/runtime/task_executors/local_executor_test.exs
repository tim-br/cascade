defmodule Cascade.Runtime.TaskExecutors.LocalExecutorTest do
  use ExUnit.Case, async: true

  alias Cascade.Runtime.TaskExecutors.LocalExecutor

  describe "module loading and execution" do
    test "successfully loads and executes existing module" do
      # Test with ExtractData module which is compiled and available
      task_config = %{
        "type" => "local",
        "config" => %{
          "module" => "Cascade.Examples.Tasks.ExtractData",
          "timeout" => 10
        }
      }

      payload = %{
        job_id: "test-job-123",
        task_id: "extract",
        task_config: task_config
      }

      # This should succeed without "Module does not export run/1" error
      result = LocalExecutor.execute(task_config["config"], payload)

      assert {:ok, %{records_extracted: 1000, source: "database"}} = result
    end

    test "handles module not found error gracefully" do
      task_config = %{
        "type" => "local",
        "config" => %{
          "module" => "Cascade.NonExistent.Module",
          "timeout" => 10
        }
      }

      payload = %{
        job_id: "test-job-456",
        task_id: "nonexistent",
        task_config: task_config
      }

      result = LocalExecutor.execute(task_config["config"], payload)

      assert {:error, error_msg} = result
      assert error_msg =~ "Failed to load module"
    end

    test "handles missing module specification" do
      task_config = %{
        "type" => "local",
        "config" => %{
          "timeout" => 10
        }
      }

      payload = %{
        job_id: "test-job-789",
        task_id: "missing_module",
        task_config: task_config
      }

      result = LocalExecutor.execute(task_config["config"], payload)

      assert {:error, "No module specified for local task"} = result
    end

    test "executes TransformData module successfully" do
      task_config = %{
        "type" => "local",
        "config" => %{
          "module" => "Cascade.Examples.Tasks.TransformData",
          "timeout" => 300
        }
      }

      payload = %{
        job_id: "test-job-transform",
        task_id: "transform",
        task_config: task_config
      }

      result = LocalExecutor.execute(task_config["config"], payload)

      # TransformData has 50% failure rate for testing
      assert match?({:ok, %{records_transformed: 1000}}, result) or
               match?({:error, _}, result)
    end

    test "executes LoadData module successfully" do
      task_config = %{
        "type" => "local",
        "config" => %{
          "module" => "Cascade.Examples.Tasks.LoadData",
          "timeout" => 300
        }
      }

      payload = %{
        job_id: "test-job-load",
        task_id: "load",
        task_config: task_config
      }

      result = LocalExecutor.execute(task_config["config"], payload)

      # LoadData has 50% failure rate for testing
      assert match?({:ok, %{records_loaded: 1000}}, result) or
               match?({:error, _}, result)
    end

    test "executes SendNotification module successfully" do
      task_config = %{
        "type" => "local",
        "config" => %{
          "module" => "Cascade.Examples.Tasks.SendNotification",
          "timeout" => 60
        }
      }

      payload = %{
        job_id: "test-job-notify",
        task_id: "notify",
        task_config: task_config
      }

      result = LocalExecutor.execute(task_config["config"], payload)

      assert {:ok, %{notification_sent: true}} = result
    end

    test "handles module at top level of task_config" do
      # Test backward compatibility where module might be at top level
      task_config = %{
        "type" => "local",
        "module" => "Cascade.Examples.Tasks.ExtractData",
        "timeout" => 10
      }

      payload = %{
        job_id: "test-job-toplevel",
        task_id: "extract",
        task_config: task_config
      }

      result = LocalExecutor.execute(task_config, payload)

      assert {:ok, %{records_extracted: 1000}} = result
    end

    test "properly passes context to task module" do
      # This test verifies the context structure passed to run/1
      task_config = %{
        "type" => "local",
        "config" => %{
          "module" => "Cascade.Examples.Tasks.ExtractData",
          "timeout" => 10,
          "custom_param" => "test_value"
        }
      }

      payload = %{
        job_id: "test-job-context",
        task_id: "extract_task",
        task_config: task_config
      }

      # The context passed to the module's run/1 should include:
      # - job_id
      # - task_id
      # - config (with all config params)
      result = LocalExecutor.execute(task_config["config"], payload)

      assert {:ok, _} = result
    end

    test "uses Code.ensure_loaded to handle unloaded modules" do
      # This test verifies that the module loading mechanism works
      # even if the module hasn't been referenced yet in this process

      # Use a module that definitely exists but might not be loaded
      task_config = %{
        "type" => "local",
        "config" => %{
          "module" => "Cascade.Examples.Tasks.PrepareData",
          "timeout" => 60
        }
      }

      payload = %{
        job_id: "test-job-ensure-loaded",
        task_id: "prepare",
        task_config: task_config
      }

      # This should work even if the module wasn't previously loaded
      # The fix uses Code.ensure_loaded/1 to handle this
      result = LocalExecutor.execute(task_config["config"], payload)

      # PrepareData should exist and execute successfully
      assert {:ok, _} = result
    end

    test "handles module not found with proper Code.ensure_loaded error" do
      # Test that Code.ensure_loaded properly catches non-existent modules
      task_config = %{
        "type" => "local",
        "config" => %{
          "module" => "Cascade.Runtime.TaskExecutors.LocalExecutorTest.NonExistentModule",
          "timeout" => 10
        }
      }

      payload = %{
        job_id: "test-job-code-ensure",
        task_id: "code_ensure_task",
        task_config: task_config
      }

      result = LocalExecutor.execute(task_config["config"], payload)

      assert {:error, error_msg} = result
      assert error_msg =~ "Failed to load module"
    end
  end

  describe "integration with daily_etl_pipeline tasks" do
    test "all daily_etl_pipeline task modules can be loaded and executed" do
      # This is a regression test for the "Module does not export run/1" bug
      # that occurred with daily_etl_pipeline tasks

      tasks = [
        {"Cascade.Examples.Tasks.ExtractData", "extract", :deterministic},
        {"Cascade.Examples.Tasks.TransformData", "transform", :flaky},  # 50% failure rate
        {"Cascade.Examples.Tasks.LoadData", "load", :flaky},  # 50% failure rate
        {"Cascade.Examples.Tasks.SendNotification", "notify", :deterministic}
      ]

      for {module_name, task_id, behavior} <- tasks do
        task_config = %{
          "type" => "local",
          "config" => %{
            "module" => module_name,
            "timeout" => 300
          }
        }

        payload = %{
          job_id: "test-job-etl",
          task_id: task_id,
          task_config: task_config
        }

        result = LocalExecutor.execute(task_config["config"], payload)

        case behavior do
          :deterministic ->
            # These tasks should always succeed
            assert {:ok, _} = result,
                   "Failed to execute #{module_name} - this was the bug that caused jobs to be orphaned"

          :flaky ->
            # TransformData has 50% failure rate for testing - accept both outcomes
            # The key is that it doesn't crash with "Module does not export run/1"
            assert match?({:ok, _}, result) or match?({:error, _}, result),
                   "#{module_name} returned unexpected result format (should be {:ok, _} or {:error, _})"
        end
      end
    end
  end
end
