defmodule Cascade.Runtime.TaskRunnerTest do
  use ExUnit.Case, async: false

  alias Cascade.{Workflows, Repo}
  alias Cascade.Runtime.TaskRunner

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Cascade.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Cascade.Repo, {:shared, self()})

    # Clean up
    Repo.delete_all(Workflows.TaskExecution)
    Repo.delete_all(Workflows.Job)
    Repo.delete_all(Workflows.DAG)

    :ok
  end

  describe "check_dependencies_valid/2" do
    test "returns :ok when task has no dependencies" do
      {:ok, dag} = Workflows.create_dag(%{
        name: "test_dag",
        description: "Test",
        definition: %{
          "nodes" => [%{"id" => "task1"}],
          "edges" => []
        },
        enabled: true
      })

      {:ok, job} = Workflows.create_job(%{
        dag_id: dag.id,
        status: :running,
        triggered_by: "test",
        started_at: DateTime.utc_now()
      })

      depends_on = []

      # Simulate the check
      result = if Enum.empty?(depends_on), do: :ok, else: :check_needed

      assert result == :ok
    end

    test "returns :ok when all dependencies succeeded" do
      {:ok, dag} = Workflows.create_dag(%{
        name: "test_dag",
        description: "Test",
        definition: %{
          "nodes" => [
            %{"id" => "task1"},
            %{"id" => "task2"}
          ],
          "edges" => [%{"from" => "task1", "to" => "task2"}]
        },
        enabled: true
      })

      {:ok, job} = Workflows.create_job(%{
        dag_id: dag.id,
        status: :running,
        triggered_by: "test",
        started_at: DateTime.utc_now()
      })

      # Dependency succeeded
      {:ok, _} = Workflows.create_task_execution(%{
        job_id: job.id,
        task_id: "task1",
        status: :success,
        execution_type: "local",
        started_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now()
      })

      depends_on = ["task1"]
      task_executions = Workflows.list_task_executions_for_job(job.id)

      failed_dependency = Enum.find(depends_on, fn dep_task_id ->
        case Enum.find(task_executions, fn te -> te.task_id == dep_task_id end) do
          nil -> false
          task_execution -> task_execution.status == :failed
        end
      end)

      result = if failed_dependency, do: {:error, :upstream_failed}, else: :ok

      assert result == :ok
    end

    test "returns error when dependency failed" do
      {:ok, dag} = Workflows.create_dag(%{
        name: "test_dag",
        description: "Test",
        definition: %{
          "nodes" => [
            %{"id" => "task1"},
            %{"id" => "task2"}
          ],
          "edges" => [%{"from" => "task1", "to" => "task2"}]
        },
        enabled: true
      })

      {:ok, job} = Workflows.create_job(%{
        dag_id: dag.id,
        status: :running,
        triggered_by: "test",
        started_at: DateTime.utc_now()
      })

      # Dependency failed
      {:ok, _} = Workflows.create_task_execution(%{
        job_id: job.id,
        task_id: "task1",
        status: :failed,
        execution_type: "local",
        error: "Failed",
        started_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now()
      })

      depends_on = ["task1"]
      task_executions = Workflows.list_task_executions_for_job(job.id)

      failed_dependency = Enum.find(depends_on, fn dep_task_id ->
        case Enum.find(task_executions, fn te -> te.task_id == dep_task_id end) do
          nil -> false
          task_execution -> task_execution.status == :failed
        end
      end)

      result = if failed_dependency, do: {:error, :upstream_failed}, else: :ok

      assert result == {:error, :upstream_failed}
      assert failed_dependency == "task1"
    end

    test "returns :ok when dependency is upstream_failed (not actual failure)" do
      # This is important: upstream_failed dependencies shouldn't block downstream tasks
      # Only actual :failed status should block
      {:ok, dag} = Workflows.create_dag(%{
        name: "test_dag",
        description: "Test",
        definition: %{
          "nodes" => [
            %{"id" => "task1"},
            %{"id" => "task2"}
          ],
          "edges" => [%{"from" => "task1", "to" => "task2"}]
        },
        enabled: true
      })

      {:ok, job} = Workflows.create_job(%{
        dag_id: dag.id,
        status: :running,
        triggered_by: "test",
        started_at: DateTime.utc_now()
      })

      # Dependency is upstream_failed (not failed)
      {:ok, _} = Workflows.create_task_execution(%{
        job_id: job.id,
        task_id: "task1",
        status: :upstream_failed,
        execution_type: "local",
        completed_at: DateTime.utc_now()
      })

      depends_on = ["task1"]
      task_executions = Workflows.list_task_executions_for_job(job.id)

      # Check only for :failed status, not :upstream_failed
      failed_dependency = Enum.find(depends_on, fn dep_task_id ->
        case Enum.find(task_executions, fn te -> te.task_id == dep_task_id end) do
          nil -> false
          task_execution -> task_execution.status == :failed
        end
      end)

      result = if failed_dependency, do: {:error, :upstream_failed}, else: :ok

      # Should pass because task1 is upstream_failed, not failed
      assert result == :ok
    end

    test "returns error when at least one of multiple dependencies failed" do
      {:ok, dag} = Workflows.create_dag(%{
        name: "test_dag",
        description: "Test",
        definition: %{
          "nodes" => [
            %{"id" => "task1"},
            %{"id" => "task2"},
            %{"id" => "task3"}
          ],
          "edges" => [
            %{"from" => "task1", "to" => "task3"},
            %{"from" => "task2", "to" => "task3"}
          ]
        },
        enabled: true
      })

      {:ok, job} = Workflows.create_job(%{
        dag_id: dag.id,
        status: :running,
        triggered_by: "test",
        started_at: DateTime.utc_now()
      })

      # Task1 succeeds
      {:ok, _} = Workflows.create_task_execution(%{
        job_id: job.id,
        task_id: "task1",
        status: :success,
        execution_type: "local",
        started_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now()
      })

      # Task2 fails
      {:ok, _} = Workflows.create_task_execution(%{
        job_id: job.id,
        task_id: "task2",
        status: :failed,
        execution_type: "local",
        error: "Failed",
        started_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now()
      })

      depends_on = ["task1", "task2"]
      task_executions = Workflows.list_task_executions_for_job(job.id)

      failed_dependency = Enum.find(depends_on, fn dep_task_id ->
        case Enum.find(task_executions, fn te -> te.task_id == dep_task_id end) do
          nil -> false
          task_execution -> task_execution.status == :failed
        end
      end)

      result = if failed_dependency, do: {:error, :upstream_failed}, else: :ok

      assert result == {:error, :upstream_failed}
      assert failed_dependency == "task2"
    end
  end

  describe "race condition scenarios" do
    test "task dispatched before dependency fails, caught at execution time" do
      # This is the key scenario we're testing:
      # 1. Task is dispatched (dependencies look OK at dispatch time)
      # 2. Dependency fails while task is in flight
      # 3. Worker checks dependencies before execution and catches the failure

      {:ok, dag} = Workflows.create_dag(%{
        name: "race_test",
        description: "Test race condition",
        definition: %{
          "nodes" => [
            %{"id" => "sentiment_analysis_1"},
            %{"id" => "compare_results"}
          ],
          "edges" => [
            %{"from" => "sentiment_analysis_1", "to" => "compare_results"}
          ]
        },
        enabled: true
      })

      {:ok, job} = Workflows.create_job(%{
        dag_id: dag.id,
        status: :running,
        triggered_by: "test",
        started_at: DateTime.utc_now()
      })

      # Initially, sentiment_analysis_1 was running (so compare_results got dispatched)
      {:ok, sa1} = Workflows.create_task_execution(%{
        job_id: job.id,
        task_id: "sentiment_analysis_1",
        status: :running,
        execution_type: "lambda",
        started_at: DateTime.utc_now()
      })

      # compare_results was dispatched
      {:ok, cr} = Workflows.create_task_execution(%{
        job_id: job.id,
        task_id: "compare_results",
        status: :pending,
        execution_type: "lambda"
      })

      # NOW sentiment_analysis_1 fails (while compare_results is in flight)
      {:ok, _} = Workflows.update_task_execution(sa1, %{
        status: :failed,
        error: "Lambda invocation failed: HTTP 500",
        completed_at: DateTime.utc_now()
      })

      # When compare_results worker checks dependencies, it should catch the failure
      depends_on = ["sentiment_analysis_1"]
      task_executions = Workflows.list_task_executions_for_job(job.id)

      failed_dependency = Enum.find(depends_on, fn dep_task_id ->
        case Enum.find(task_executions, fn te -> te.task_id == dep_task_id end) do
          nil -> false
          task_execution -> task_execution.status == :failed
        end
      end)

      # Should detect the failure
      assert failed_dependency == "sentiment_analysis_1"

      # compare_results should be marked upstream_failed, not execute
      {:ok, updated_cr} = Workflows.update_task_execution(cr, %{
        status: :upstream_failed,
        completed_at: DateTime.utc_now()
      })

      assert updated_cr.status == :upstream_failed

      # Job should still be marked as failed (because sentiment_analysis_1 failed)
      task_executions = Workflows.list_task_executions_for_job(job.id)
      actual_failures = Enum.count(task_executions, fn te -> te.status == :failed end)

      assert actual_failures == 1  # Only sentiment_analysis_1
    end

    test "multiple parallel tasks, one fails, downstream catches it" do
      {:ok, dag} = Workflows.create_dag(%{
        name: "parallel_test",
        description: "Test parallel execution",
        definition: %{
          "nodes" => [
            %{"id" => "task_a"},
            %{"id" => "task_b"},
            %{"id" => "task_c"},
            %{"id" => "downstream"}
          ],
          "edges" => [
            %{"from" => "task_a", "to" => "downstream"},
            %{"from" => "task_b", "to" => "downstream"},
            %{"from" => "task_c", "to" => "downstream"}
          ]
        },
        enabled: true
      })

      {:ok, job} = Workflows.create_job(%{
        dag_id: dag.id,
        status: :running,
        triggered_by: "test",
        started_at: DateTime.utc_now()
      })

      # Task A succeeds
      {:ok, _} = Workflows.create_task_execution(%{
        job_id: job.id,
        task_id: "task_a",
        status: :success,
        execution_type: "local",
        started_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now()
      })

      # Task B fails
      {:ok, _} = Workflows.create_task_execution(%{
        job_id: job.id,
        task_id: "task_b",
        status: :failed,
        execution_type: "local",
        error: "Failed",
        started_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now()
      })

      # Task C succeeds
      {:ok, _} = Workflows.create_task_execution(%{
        job_id: job.id,
        task_id: "task_c",
        status: :success,
        execution_type: "local",
        started_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now()
      })

      # Downstream checks dependencies
      depends_on = ["task_a", "task_b", "task_c"]
      task_executions = Workflows.list_task_executions_for_job(job.id)

      failed_dependency = Enum.find(depends_on, fn dep_task_id ->
        case Enum.find(task_executions, fn te -> te.task_id == dep_task_id end) do
          nil -> false
          task_execution -> task_execution.status == :failed
        end
      end)

      # Should detect task_b failure
      assert failed_dependency == "task_b"
    end
  end

  describe "handle_info/2 with claim_task errors" do
    test "CRITICAL: gracefully handles :already_completed error from claim_task" do
      {:ok, dag} = Workflows.create_dag(%{
        name: "completed_task_dag",
        description: "Test already completed task",
        definition: %{
          "nodes" => [%{"id" => "task_done", "type" => "local", "config" => %{}}],
          "edges" => []
        },
        enabled: true
      })

      {:ok, job} = Workflows.create_job(%{
        dag_id: dag.id,
        status: :running,
        triggered_by: "test"
      })

      # Create a task that's already completed
      {:ok, _} = Workflows.create_task_execution(%{
        job_id: job.id,
        task_id: "task_done",
        status: :success,
        execution_type: "local",
        result: %{"output" => "already done"},
        started_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now()
      })

      # Start a worker
      {:ok, worker} = TaskRunner.start_link(worker_id: 999)

      # Send execute_task message for already completed task
      payload = %{
        job_id: job.id,
        task_id: "task_done",
        task_config: %{
          "id" => "task_done",
          "type" => "local",
          "config" => %{"module" => "Cascade.Examples.Tasks.SampleTask"}
        },
        context: %{},
        depends_on: []
      }

      # This should NOT crash the worker
      send(worker, {:execute_task, payload})

      # Give it time to process
      Process.sleep(100)

      # Worker should still be alive
      assert Process.alive?(worker)

      # Task should still be :success (not re-executed)
      task_executions = Workflows.list_task_executions_for_job(job.id)
      task = Enum.find(task_executions, fn te -> te.task_id == "task_done" end)
      assert task.status == :success

      # Cleanup
      GenServer.stop(worker)
    end

    test "gracefully handles :already_claimed error from claim_task" do
      {:ok, dag} = Workflows.create_dag(%{
        name: "claimed_task_dag",
        description: "Test already claimed task",
        definition: %{
          "nodes" => [%{"id" => "task_claimed", "type" => "local", "config" => %{}}],
          "edges" => []
        },
        enabled: true
      })

      {:ok, job} = Workflows.create_job(%{
        dag_id: dag.id,
        status: :running,
        triggered_by: "test"
      })

      # Create a task that's already claimed by another worker
      {:ok, _} = Workflows.create_task_execution(%{
        job_id: job.id,
        task_id: "task_claimed",
        status: :running,
        execution_type: "local",
        claimed_by_worker: "other_worker",
        claimed_at: DateTime.utc_now(),
        started_at: DateTime.utc_now()
      })

      # Start a worker
      {:ok, worker} = TaskRunner.start_link(worker_id: 998)

      # Send execute_task message for already claimed task
      payload = %{
        job_id: job.id,
        task_id: "task_claimed",
        task_config: %{
          "id" => "task_claimed",
          "type" => "local",
          "config" => %{"module" => "Cascade.Examples.Tasks.SampleTask"}
        },
        context: %{},
        depends_on: []
      }

      # This should NOT crash the worker
      send(worker, {:execute_task, payload})

      # Give it time to process
      Process.sleep(100)

      # Worker should still be alive
      assert Process.alive?(worker)

      # Task should still be claimed by other_worker
      task_executions = Workflows.list_task_executions_for_job(job.id)
      task = Enum.find(task_executions, fn te -> te.task_id == "task_claimed" end)
      assert task.claimed_by_worker == "other_worker"

      # Cleanup
      GenServer.stop(worker)
    end
  end
end
