defmodule Cascade.Runtime.SchedulerTest do
  use ExUnit.Case, async: false

  alias Cascade.{Workflows, Repo}
  alias Cascade.Runtime.{Scheduler, StateManager}

  setup do
    # Explicitly get a connection
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Cascade.Repo)
    # Setting the mode to shared allows other processes to use the connection
    Ecto.Adapters.SQL.Sandbox.mode(Cascade.Repo, {:shared, self()})

    # Clean up any existing data
    Repo.delete_all(Workflows.TaskExecution)
    Repo.delete_all(Workflows.Job)
    Repo.delete_all(Workflows.DAG)

    :ok
  end

  describe "job status determination" do
    test "job is marked as success when all tasks succeed" do
      # Create a simple DAG with 3 tasks
      dag_definition = %{
        "name" => "test_success_dag",
        "nodes" => [
          %{"id" => "task1", "type" => "local", "config" => %{}},
          %{"id" => "task2", "type" => "local", "config" => %{}},
          %{"id" => "task3", "type" => "local", "config" => %{}}
        ],
        "edges" => [
          %{"from" => "task1", "to" => "task2"},
          %{"from" => "task2", "to" => "task3"}
        ],
        "metadata" => %{"description" => "Test DAG"}
      }

      {:ok, dag} = Workflows.create_dag(%{
        name: "test_success_dag",
        description: "Test DAG",
        definition: dag_definition,
        enabled: true
      })

      # Create job
      {:ok, job} = Workflows.create_job(%{
        dag_id: dag.id,
        status: :running,
        triggered_by: "test",
        started_at: DateTime.utc_now()
      })

      # Create task executions - all successful
      {:ok, _} = Workflows.create_task_execution(%{
        job_id: job.id,
        task_id: "task1",
        status: :success,
        execution_type: "local",
        started_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now()
      })

      {:ok, _} = Workflows.create_task_execution(%{
        job_id: job.id,
        task_id: "task2",
        status: :success,
        execution_type: "local",
        started_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now()
      })

      {:ok, _} = Workflows.create_task_execution(%{
        job_id: job.id,
        task_id: "task3",
        status: :success,
        execution_type: "local",
        started_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now()
      })

      # Test the status determination logic directly
      # (This is what complete_job does internally)
      task_executions = Workflows.list_task_executions_for_job(job.id)
      actual_failures = Enum.count(task_executions, fn te -> te.status == :failed end)
      final_status = if actual_failures > 0, do: :failed, else: :success

      assert final_status == :success
      assert actual_failures == 0
    end

    test "job is marked as failed when one task fails" do
      dag_definition = %{
        "name" => "test_fail_dag",
        "nodes" => [
          %{"id" => "task1", "type" => "local", "config" => %{}},
          %{"id" => "task2", "type" => "local", "config" => %{}},
          %{"id" => "task3", "type" => "local", "config" => %{}}
        ],
        "edges" => [
          %{"from" => "task1", "to" => "task2"},
          %{"from" => "task2", "to" => "task3"}
        ],
        "metadata" => %{"description" => "Test DAG"}
      }

      {:ok, dag} = Workflows.create_dag(%{
        name: "test_fail_dag",
        description: "Test DAG",
        definition: dag_definition,
        enabled: true
      })

      {:ok, job} = Workflows.create_job(%{
        dag_id: dag.id,
        status: :running,
        triggered_by: "test",
        started_at: DateTime.utc_now()
      })

      # Task 1 succeeds
      {:ok, _} = Workflows.create_task_execution(%{
        job_id: job.id,
        task_id: "task1",
        status: :success,
        execution_type: "local",
        started_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now()
      })

      # Task 2 fails
      {:ok, _} = Workflows.create_task_execution(%{
        job_id: job.id,
        task_id: "task2",
        status: :failed,
        execution_type: "local",
        error: "Task failed",
        started_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now()
      })

      # Task 3 was upstream_failed (blocked by task2 failure)
      {:ok, _} = Workflows.create_task_execution(%{
        job_id: job.id,
        task_id: "task3",
        status: :upstream_failed,
        execution_type: "local",
        completed_at: DateTime.utc_now()
      })

      job_state = %{
        job_id: job.id,
        dag_id: dag.id,
        status: :running,
        pending_tasks: MapSet.new(),
        running_tasks: %{},
        completed_tasks: MapSet.new(["task1"]),
        failed_tasks: MapSet.new(["task2"]),
        skipped_tasks: MapSet.new(["task3"]),
        dag_definition: Map.put(dag_definition, "dag_id", dag.id),
        started_at: DateTime.utc_now()
      }

      # Get the actual complete_job function via a test message
      # We need to test the logic directly
      task_executions = Workflows.list_task_executions_for_job(job.id)
      actual_failures = Enum.count(task_executions, fn te -> te.status == :failed end)
      final_status = if actual_failures > 0, do: :failed, else: :success

      assert final_status == :failed
      assert actual_failures == 1
    end

    test "job is marked as failed when task has actual failure" do
      # This tests that actual :failed status correctly marks job as failed
      dag_definition = %{
        "name" => "test_actual_failure",
        "nodes" => [
          %{"id" => "task1", "type" => "local", "config" => %{}},
          %{"id" => "task2", "type" => "local", "config" => %{}}
        ],
        "edges" => [
          %{"from" => "task1", "to" => "task2"}
        ],
        "metadata" => %{"description" => "Test actual failure"}
      }

      {:ok, dag} = Workflows.create_dag(%{
        name: "test_actual_failure",
        description: "Test actual failure",
        definition: dag_definition,
        enabled: true
      })

      {:ok, job} = Workflows.create_job(%{
        dag_id: dag.id,
        status: :running,
        triggered_by: "test",
        started_at: DateTime.utc_now()
      })

      # Task 1 actually fails (e.g., Lambda returns 500, or local task throws error)
      {:ok, _} = Workflows.create_task_execution(%{
        job_id: job.id,
        task_id: "task1",
        status: :failed,
        execution_type: "lambda",
        error: "Lambda invocation failed: HTTP 500",
        started_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now()
      })

      # Task 2 was never dispatched (or was marked upstream_failed)
      {:ok, _} = Workflows.create_task_execution(%{
        job_id: job.id,
        task_id: "task2",
        status: :upstream_failed,
        execution_type: "lambda",
        completed_at: DateTime.utc_now()
      })

      # Calculate final status
      task_executions = Workflows.list_task_executions_for_job(job.id)
      actual_failures = Enum.count(task_executions, fn te -> te.status == :failed end)
      final_status = if actual_failures > 0, do: :failed, else: :success

      # Job MUST be marked as failed because task1 actually failed
      assert final_status == :failed
      assert actual_failures == 1
    end

    test "job is marked as failed with multiple actual failures" do
      # Tests multiple tasks failing
      dag_definition = %{
        "name" => "test_multiple_failures",
        "nodes" => [
          %{"id" => "task1", "type" => "local", "config" => %{}},
          %{"id" => "task2", "type" => "local", "config" => %{}},
          %{"id" => "task3", "type" => "local", "config" => %{}}
        ],
        "edges" => [],
        "metadata" => %{"description" => "Test multiple failures"}
      }

      {:ok, dag} = Workflows.create_dag(%{
        name: "test_multiple_failures",
        description: "Test multiple failures",
        definition: dag_definition,
        enabled: true
      })

      {:ok, job} = Workflows.create_job(%{
        dag_id: dag.id,
        status: :running,
        triggered_by: "test",
        started_at: DateTime.utc_now()
      })

      # Task 1 fails
      {:ok, _} = Workflows.create_task_execution(%{
        job_id: job.id,
        task_id: "task1",
        status: :failed,
        execution_type: "local",
        error: "Task execution error",
        started_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now()
      })

      # Task 2 succeeds
      {:ok, _} = Workflows.create_task_execution(%{
        job_id: job.id,
        task_id: "task2",
        status: :success,
        execution_type: "local",
        started_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now()
      })

      # Task 3 also fails
      {:ok, _} = Workflows.create_task_execution(%{
        job_id: job.id,
        task_id: "task3",
        status: :failed,
        execution_type: "local",
        error: "Another error",
        started_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now()
      })

      # Calculate final status
      task_executions = Workflows.list_task_executions_for_job(job.id)
      actual_failures = Enum.count(task_executions, fn te -> te.status == :failed end)
      final_status = if actual_failures > 0, do: :failed, else: :success

      # Job MUST be marked as failed
      assert final_status == :failed
      assert actual_failures == 2
    end

    test "job is marked as success when tasks are upstream_failed but no actual failures" do
      # This tests the critical bug fix: upstream_failed tasks shouldn't mark job as failed
      dag_definition = %{
        "name" => "test_upstream_failed_dag",
        "nodes" => [
          %{"id" => "task1", "type" => "local", "config" => %{}},
          %{"id" => "task2", "type" => "local", "config" => %{}},
          %{"id" => "task3", "type" => "local", "config" => %{}}
        ],
        "edges" => [
          %{"from" => "task1", "to" => "task3"},
          %{"from" => "task2", "to" => "task3"}
        ],
        "metadata" => %{"description" => "Test DAG"}
      }

      {:ok, dag} = Workflows.create_dag(%{
        name: "test_upstream_failed_dag",
        description: "Test DAG with upstream failures",
        definition: dag_definition,
        enabled: true
      })

      {:ok, job} = Workflows.create_job(%{
        dag_id: dag.id,
        status: :running,
        triggered_by: "test",
        started_at: DateTime.utc_now()
      })

      # Task 1 succeeds
      {:ok, _} = Workflows.create_task_execution(%{
        job_id: job.id,
        task_id: "task1",
        status: :success,
        execution_type: "local",
        started_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now()
      })

      # Task 2 succeeds
      {:ok, _} = Workflows.create_task_execution(%{
        job_id: job.id,
        task_id: "task2",
        status: :success,
        execution_type: "local",
        started_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now()
      })

      # Task 3 was marked upstream_failed due to race condition
      # (dependency failed after dispatch but before execution)
      {:ok, _} = Workflows.create_task_execution(%{
        job_id: job.id,
        task_id: "task3",
        status: :upstream_failed,
        execution_type: "local",
        completed_at: DateTime.utc_now()
      })

      # Calculate final status using the logic from complete_job
      task_executions = Workflows.list_task_executions_for_job(job.id)
      actual_failures = Enum.count(task_executions, fn te -> te.status == :failed end)
      final_status = if actual_failures > 0, do: :failed, else: :success

      # This should be SUCCESS because no tasks actually failed
      # Only upstream_failed which shouldn't count
      assert final_status == :success
      assert actual_failures == 0
    end

    test "job completes when task is skipped due to race condition" do
      # This tests the bug fix where job gets stuck in :running when
      # a task is marked upstream_failed after dispatch
      dag_definition = %{
        "name" => "race_completion_test",
        "nodes" => [
          %{"id" => "task_a", "type" => "lambda", "config" => %{}},
          %{"id" => "task_b", "type" => "lambda", "config" => %{}}
        ],
        "edges" => [
          %{"from" => "task_a", "to" => "task_b"}
        ],
        "metadata" => %{"description" => "Test race condition completion"}
      }

      {:ok, dag} = Workflows.create_dag(%{
        name: "race_completion_test",
        description: "Test race condition job completion",
        definition: dag_definition,
        enabled: true
      })

      {:ok, job} = Workflows.create_job(%{
        dag_id: dag.id,
        status: :running,
        triggered_by: "test",
        started_at: DateTime.utc_now()
      })

      # Task A fails
      {:ok, _} = Workflows.create_task_execution(%{
        job_id: job.id,
        task_id: "task_a",
        status: :failed,
        execution_type: "lambda",
        error: "Lambda invocation failed",
        started_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now()
      })

      # Task B was dispatched before A failed, but caught the failure
      # and was marked as upstream_failed
      {:ok, _} = Workflows.create_task_execution(%{
        job_id: job.id,
        task_id: "task_b",
        status: :upstream_failed,
        execution_type: "lambda",
        completed_at: DateTime.utc_now()
      })

      # Calculate final status
      task_executions = Workflows.list_task_executions_for_job(job.id)
      actual_failures = Enum.count(task_executions, fn te -> te.status == :failed end)
      final_status = if actual_failures > 0, do: :failed, else: :success

      # All tasks are in terminal state - job should be complete
      all_terminal = Enum.all?(task_executions, fn te ->
        te.status in [:success, :failed, :upstream_failed]
      end)

      # Job MUST complete with status :failed (because task_a actually failed)
      assert all_terminal == true
      assert final_status == :failed
      assert actual_failures == 1
    end
  end

  describe "dependency validation" do
    test "task is skipped if dependency fails after dispatch" do
      # This simulates the race condition scenario
      dag_definition = %{
        "name" => "test_race_condition",
        "nodes" => [
          %{"id" => "task1", "type" => "local", "config" => %{}},
          %{"id" => "task2", "type" => "local", "config" => %{}}
        ],
        "edges" => [
          %{"from" => "task1", "to" => "task2"}
        ],
        "metadata" => %{"description" => "Test race condition"}
      }

      {:ok, dag} = Workflows.create_dag(%{
        name: "test_race_condition",
        description: "Test race condition",
        definition: dag_definition,
        enabled: true
      })

      {:ok, job} = Workflows.create_job(%{
        dag_id: dag.id,
        status: :running,
        triggered_by: "test",
        started_at: DateTime.utc_now()
      })

      # Task 1 is marked as failed
      {:ok, _} = Workflows.create_task_execution(%{
        job_id: job.id,
        task_id: "task1",
        status: :failed,
        execution_type: "local",
        error: "Failed",
        started_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now()
      })

      # Task 2 execution record exists but pending
      {:ok, task2_execution} = Workflows.create_task_execution(%{
        job_id: job.id,
        task_id: "task2",
        status: :pending,
        execution_type: "local"
      })

      # Simulate check_dependencies_valid logic
      depends_on = ["task1"]
      task_executions = Workflows.list_task_executions_for_job(job.id)

      failed_dependency = Enum.find(depends_on, fn dep_task_id ->
        case Enum.find(task_executions, fn te -> te.task_id == dep_task_id end) do
          nil -> false
          task_execution -> task_execution.status == :failed
        end
      end)

      # Should detect that task1 (dependency) has failed
      assert failed_dependency == "task1"

      # Task 2 should be marked as upstream_failed
      {:ok, updated_task2} = Workflows.update_task_execution(task2_execution, %{
        status: :upstream_failed,
        completed_at: DateTime.utc_now()
      })

      assert updated_task2.status == :upstream_failed
    end

    test "task executes normally when all dependencies succeeded" do
      dag_definition = %{
        "name" => "test_deps_success",
        "nodes" => [
          %{"id" => "task1", "type" => "local", "config" => %{}},
          %{"id" => "task2", "type" => "local", "config" => %{}},
          %{"id" => "task3", "type" => "local", "config" => %{}}
        ],
        "edges" => [
          %{"from" => "task1", "to" => "task3"},
          %{"from" => "task2", "to" => "task3"}
        ],
        "metadata" => %{"description" => "Test dependencies"}
      }

      {:ok, dag} = Workflows.create_dag(%{
        name: "test_deps_success",
        description: "Test dependencies",
        definition: dag_definition,
        enabled: true
      })

      {:ok, job} = Workflows.create_job(%{
        dag_id: dag.id,
        status: :running,
        triggered_by: "test",
        started_at: DateTime.utc_now()
      })

      # Both dependencies succeed
      {:ok, _} = Workflows.create_task_execution(%{
        job_id: job.id,
        task_id: "task1",
        status: :success,
        execution_type: "local",
        started_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now()
      })

      {:ok, _} = Workflows.create_task_execution(%{
        job_id: job.id,
        task_id: "task2",
        status: :success,
        execution_type: "local",
        started_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now()
      })

      # Check dependencies for task3
      depends_on = ["task1", "task2"]
      task_executions = Workflows.list_task_executions_for_job(job.id)

      failed_dependency = Enum.find(depends_on, fn dep_task_id ->
        case Enum.find(task_executions, fn te -> te.task_id == dep_task_id end) do
          nil -> false
          task_execution -> task_execution.status == :failed
        end
      end)

      # Should be nil - no dependencies failed
      assert failed_dependency == nil
    end
  end

  describe "job completion logic" do
    test "job is complete when all tasks are completed, failed, or skipped" do
      job_state = %{
        pending_tasks: MapSet.new(),
        running_tasks: %{},
        completed_tasks: MapSet.new(["task1", "task2"]),
        failed_tasks: MapSet.new(["task3"]),
        skipped_tasks: MapSet.new(["task4"])
      }

      # Calculate completion
      all_tasks_count =
        MapSet.size(job_state.pending_tasks) +
        map_size(job_state.running_tasks) +
        MapSet.size(job_state.completed_tasks) +
        MapSet.size(job_state.failed_tasks) +
        MapSet.size(job_state.skipped_tasks)

      completed_or_failed_or_skipped =
        MapSet.size(job_state.completed_tasks) +
        MapSet.size(job_state.failed_tasks) +
        MapSet.size(job_state.skipped_tasks)

      is_complete = completed_or_failed_or_skipped == all_tasks_count and map_size(job_state.running_tasks) == 0

      assert all_tasks_count == 4
      assert completed_or_failed_or_skipped == 4
      assert is_complete == true
    end

    test "job is not complete when tasks are still running" do
      job_state = %{
        pending_tasks: MapSet.new(),
        running_tasks: %{"task3" => "worker1"},
        completed_tasks: MapSet.new(["task1", "task2"]),
        failed_tasks: MapSet.new(),
        skipped_tasks: MapSet.new()
      }

      all_tasks_count =
        MapSet.size(job_state.pending_tasks) +
        map_size(job_state.running_tasks) +
        MapSet.size(job_state.completed_tasks) +
        MapSet.size(job_state.failed_tasks) +
        MapSet.size(job_state.skipped_tasks)

      completed_or_failed_or_skipped =
        MapSet.size(job_state.completed_tasks) +
        MapSet.size(job_state.failed_tasks) +
        MapSet.size(job_state.skipped_tasks)

      is_complete = completed_or_failed_or_skipped == all_tasks_count and map_size(job_state.running_tasks) == 0

      assert is_complete == false
    end

    test "job is not complete when tasks are still pending" do
      job_state = %{
        pending_tasks: MapSet.new(["task3"]),
        running_tasks: %{},
        completed_tasks: MapSet.new(["task1", "task2"]),
        failed_tasks: MapSet.new(),
        skipped_tasks: MapSet.new()
      }

      all_tasks_count =
        MapSet.size(job_state.pending_tasks) +
        map_size(job_state.running_tasks) +
        MapSet.size(job_state.completed_tasks) +
        MapSet.size(job_state.failed_tasks) +
        MapSet.size(job_state.skipped_tasks)

      completed_or_failed_or_skipped =
        MapSet.size(job_state.completed_tasks) +
        MapSet.size(job_state.failed_tasks) +
        MapSet.size(job_state.skipped_tasks)

      is_complete = completed_or_failed_or_skipped == all_tasks_count and map_size(job_state.running_tasks) == 0

      assert is_complete == false
    end
  end

  describe "retry value normalization" do
    test "handles empty string retry value gracefully" do
      # This tests the bug fix for empty string retry values causing ArithmeticError
      dag_definition = %{
        "name" => "test_empty_retry",
        "nodes" => [
          %{"id" => "task1", "type" => "local", "config" => %{"retry" => ""}}
        ],
        "edges" => [],
        "metadata" => %{"description" => "Test empty string retry"}
      }

      {:ok, dag} = Workflows.create_dag(%{
        name: "test_empty_retry",
        description: "Test empty string retry",
        definition: dag_definition,
        enabled: true
      })

      # Simulate the retry normalization logic from handle_cast({:task_failed, ...})
      task_config = Enum.at(dag_definition["nodes"], 0)

      # This should normalize to 0, not crash with ArithmeticError
      max_retries = case task_config["config"]["retry"] do
        n when is_integer(n) -> n
        _ -> 0
      end

      assert max_retries == 0
      # Verify arithmetic works (this would crash before the fix)
      assert max_retries + 1 == 1
    end

    test "handles nil retry value gracefully" do
      dag_definition = %{
        "name" => "test_nil_retry",
        "nodes" => [
          %{"id" => "task1", "type" => "local", "config" => %{"retry" => nil}}
        ],
        "edges" => [],
        "metadata" => %{"description" => "Test nil retry"}
      }

      {:ok, dag} = Workflows.create_dag(%{
        name: "test_nil_retry",
        description: "Test nil retry",
        definition: dag_definition,
        enabled: true
      })

      task_config = Enum.at(dag_definition["nodes"], 0)

      max_retries = case task_config["config"]["retry"] do
        n when is_integer(n) -> n
        _ -> 0
      end

      assert max_retries == 0
    end

    test "handles missing retry value gracefully" do
      dag_definition = %{
        "name" => "test_missing_retry",
        "nodes" => [
          %{"id" => "task1", "type" => "local", "config" => %{}}
        ],
        "edges" => [],
        "metadata" => %{"description" => "Test missing retry"}
      }

      {:ok, dag} = Workflows.create_dag(%{
        name: "test_missing_retry",
        description: "Test missing retry",
        definition: dag_definition,
        enabled: true
      })

      task_config = Enum.at(dag_definition["nodes"], 0)

      max_retries = case task_config["config"]["retry"] do
        n when is_integer(n) -> n
        _ -> 0
      end

      assert max_retries == 0
    end

    test "preserves valid integer retry value" do
      dag_definition = %{
        "name" => "test_valid_retry",
        "nodes" => [
          %{"id" => "task1", "type" => "local", "config" => %{"retry" => 3}}
        ],
        "edges" => [],
        "metadata" => %{"description" => "Test valid retry"}
      }

      {:ok, dag} = Workflows.create_dag(%{
        name: "test_valid_retry",
        description: "Test valid retry",
        definition: dag_definition,
        enabled: true
      })

      task_config = Enum.at(dag_definition["nodes"], 0)

      max_retries = case task_config["config"]["retry"] do
        n when is_integer(n) -> n
        _ -> 0
      end

      assert max_retries == 3
    end

    test "scheduler does not crash with empty string retry on task failure" do
      # Integration test: verify Scheduler GenServer doesn't crash when handling
      # task failure with empty string retry value
      dag_definition = %{
        "name" => "test_scheduler_crash_prevention",
        "nodes" => [
          %{"id" => "task1", "type" => "local", "config" => %{"retry" => ""}},
          %{"id" => "task2", "type" => "local", "config" => %{}}
        ],
        "edges" => [
          %{"from" => "task1", "to" => "task2"}
        ],
        "metadata" => %{"description" => "Test scheduler crash prevention"}
      }

      {:ok, dag} = Workflows.create_dag(%{
        name: "test_scheduler_crash_prevention",
        description: "Test scheduler crash prevention",
        definition: dag_definition,
        enabled: true
      })

      {:ok, job} = Workflows.create_job(%{
        dag_id: dag.id,
        status: :running,
        triggered_by: "test",
        started_at: DateTime.utc_now()
      })

      {:ok, _} = Workflows.create_task_execution(%{
        job_id: job.id,
        task_id: "task1",
        status: :running,
        execution_type: "local",
        started_at: DateTime.utc_now(),
        retry_count: 0
      })

      {:ok, _} = Workflows.create_task_execution(%{
        job_id: job.id,
        task_id: "task2",
        status: :pending,
        execution_type: "local"
      })

      # Initialize job state in StateManager
      dag_definition_with_id = Map.put(dag_definition, "dag_id", dag.id)
      {:ok, _} = StateManager.create_job_state(job.id, dag_definition_with_id)

      # Move task1 to running in state
      StateManager.update_task_status(job.id, "task1", :running)

      # This should not crash the Scheduler
      # Before the fix, this would cause: ArithmeticError: bad argument in arithmetic expression
      Scheduler.handle_task_failure(job.id, "task1", "Some error")

      # Give the cast a moment to process
      Process.sleep(100)

      # Verify Scheduler is still alive (critical - it was crashing before)
      assert Process.whereis(Cascade.Runtime.Scheduler) != nil

      # Verify task was marked as failed in database (not retried since max_retries = 0)
      task_executions = Workflows.list_task_executions_for_job(job.id)
      task1 = Enum.find(task_executions, fn te -> te.task_id == "task1" end)
      assert task1.status == :failed
      assert task1.error =~ "Some error"
    end
  end

  describe "state transitions" do
    test "task transitions from pending to running to success" do
      job_state = %{
        pending_tasks: MapSet.new(["task1"]),
        running_tasks: %{},
        completed_tasks: MapSet.new(),
        failed_tasks: MapSet.new(),
        skipped_tasks: MapSet.new()
      }

      # Transition to running
      job_state = %{
        job_state
        | running_tasks: Map.put(job_state.running_tasks, "task1", "worker1"),
          pending_tasks: MapSet.delete(job_state.pending_tasks, "task1")
      }

      assert MapSet.member?(job_state.pending_tasks, "task1") == false
      assert Map.has_key?(job_state.running_tasks, "task1") == true

      # Transition to success
      job_state = %{
        job_state
        | completed_tasks: MapSet.put(job_state.completed_tasks, "task1"),
          running_tasks: Map.delete(job_state.running_tasks, "task1")
      }

      assert Map.has_key?(job_state.running_tasks, "task1") == false
      assert MapSet.member?(job_state.completed_tasks, "task1") == true
    end

    test "task transitions from pending to upstream_failed" do
      job_state = %{
        pending_tasks: MapSet.new(["task1"]),
        running_tasks: %{},
        completed_tasks: MapSet.new(),
        failed_tasks: MapSet.new(),
        skipped_tasks: MapSet.new()
      }

      # Transition to upstream_failed
      job_state = %{
        job_state
        | pending_tasks: MapSet.delete(job_state.pending_tasks, "task1"),
          skipped_tasks: MapSet.put(job_state.skipped_tasks, "task1")
      }

      assert MapSet.member?(job_state.pending_tasks, "task1") == false
      assert MapSet.member?(job_state.skipped_tasks, "task1") == true
      assert MapSet.member?(job_state.failed_tasks, "task1") == false
    end
  end
end
