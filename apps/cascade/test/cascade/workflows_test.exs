defmodule Cascade.WorkflowsTest do
  use Cascade.DataCase, async: false

  alias Cascade.Workflows
  alias Cascade.Workflows.{DAG, Job, TaskExecution}

  describe "claim_task/3" do
    setup do
      # Create a test DAG
      {:ok, dag} =
        Workflows.create_dag(%{
          name: "test_claim_dag",
          description: "DAG for testing task claiming",
          definition: %{
            "nodes" => [
              %{"id" => "task_a", "type" => "local", "config" => %{"command" => "echo A"}},
              %{"id" => "task_b", "type" => "local", "config" => %{"command" => "echo B"}}
            ],
            "edges" => []
          },
          enabled: true
        })

      # Create a test job
      {:ok, job} =
        Workflows.create_job(%{
          dag_id: dag.id,
          triggered_by: "test",
          status: :running
        })

      # Create task executions
      {:ok, task_a} =
        Workflows.create_task_execution(%{
          job_id: job.id,
          task_id: "task_a",
          status: :pending,
          execution_type: "local"
        })

      {:ok, task_b} =
        Workflows.create_task_execution(%{
          job_id: job.id,
          task_id: "task_b",
          status: :pending,
          execution_type: "local"
        })

      %{job: job, dag: dag, task_a: task_a, task_b: task_b}
    end

    test "successfully claims an unclaimed task", %{job: job} do
      assert {:ok, :claimed} = Workflows.claim_task(job.id, "task_a", "worker_1")

      # Verify task was claimed
      task = get_task_execution!(job.id, "task_a")
      assert task.claimed_by_worker == "worker_1"
      assert task.claimed_at != nil
    end

    test "allows same worker to claim a task multiple times (idempotent)", %{job: job} do
      # First claim
      assert {:ok, :claimed} = Workflows.claim_task(job.id, "task_a", "worker_1")

      # Second claim by same worker - should succeed (idempotent)
      assert {:ok, :claimed} = Workflows.claim_task(job.id, "task_a", "worker_1")
    end

    test "rejects claim by different worker when task is already claimed", %{job: job} do
      # Worker 1 claims the task
      assert {:ok, :claimed} = Workflows.claim_task(job.id, "task_a", "worker_1")

      # Worker 2 tries to claim - should fail
      assert {:error, :already_claimed} = Workflows.claim_task(job.id, "task_a", "worker_2")
    end

    test "CRITICAL: rejects claim for successfully completed tasks", %{job: job} do
      # Complete the task successfully
      task = get_task_execution!(job.id, "task_a")

      {:ok, _} =
        Workflows.update_task_execution(task, %{
          status: :success,
          completed_at: DateTime.utc_now()
        })

      # Try to claim the completed task - should fail
      assert {:error, :already_completed} = Workflows.claim_task(job.id, "task_a", "worker_1")
    end

    test "CRITICAL: rejects claim for upstream_failed tasks", %{job: job} do
      # Mark task as upstream_failed
      task = get_task_execution!(job.id, "task_a")

      {:ok, _} =
        Workflows.update_task_execution(task, %{
          status: :upstream_failed,
          completed_at: DateTime.utc_now()
        })

      # Try to claim the skipped task - should fail
      assert {:error, :already_completed} = Workflows.claim_task(job.id, "task_a", "worker_1")
    end

    test "CRITICAL: allows claim for failed tasks (for retry)", %{job: job} do
      # Mark task as failed
      task = get_task_execution!(job.id, "task_a")

      {:ok, _} =
        Workflows.update_task_execution(task, %{
          status: :failed,
          error: "Something went wrong",
          completed_at: DateTime.utc_now()
        })

      # Try to claim the failed task - should succeed (allows retry)
      assert {:ok, :claimed} = Workflows.claim_task(job.id, "task_a", "worker_1")
    end

    test "CRITICAL: prevents re-execution of successful tasks by same worker", %{job: job} do
      # Worker claims and completes task
      assert {:ok, :claimed} = Workflows.claim_task(job.id, "task_a", "worker_1")

      task = get_task_execution!(job.id, "task_a")

      {:ok, _} =
        Workflows.update_task_execution(task, %{
          status: :success,
          result: %{"output" => "success"},
          completed_at: DateTime.utc_now()
        })

      # Same worker tries to claim again - should fail
      assert {:error, :already_completed} = Workflows.claim_task(job.id, "task_a", "worker_1")
    end

    test "rejects claim for non-existent task", %{job: job} do
      assert {:error, :task_not_found} =
               Workflows.claim_task(job.id, "non_existent_task", "worker_1")
    end

    test "handles concurrent claims with row-level locking", %{job: job} do
      # Simulate concurrent claims by multiple workers
      parent = self()

      worker1 =
        Task.async(fn ->
          result = Workflows.claim_task(job.id, "task_a", "worker_1")
          send(parent, {:worker1, result})
          result
        end)

      worker2 =
        Task.async(fn ->
          # Small delay to ensure race condition
          Process.sleep(5)
          result = Workflows.claim_task(job.id, "task_a", "worker_2")
          send(parent, {:worker2, result})
          result
        end)

      results = [Task.await(worker1), Task.await(worker2)]

      # Exactly one should succeed
      assert {:ok, :claimed} in results
      assert {:error, :already_claimed} in results
    end
  end

  describe "claim_task/3 with different task statuses" do
    setup do
      {:ok, dag} =
        Workflows.create_dag(%{
          name: "status_test_dag",
          description: "Testing claims with different statuses",
          definition: %{
            "nodes" => [%{"id" => "task_x", "type" => "local", "config" => %{}}],
            "edges" => []
          },
          enabled: true
        })

      {:ok, job} =
        Workflows.create_job(%{
          dag_id: dag.id,
          triggered_by: "status_test",
          status: :running
        })

      %{job: job, dag: dag}
    end

    test "claimable: pending task", %{job: job} do
      {:ok, _} =
        Workflows.create_task_execution(%{
          job_id: job.id,
          task_id: "task_pending",
          status: :pending,
          execution_type: "local"
        })

      assert {:ok, :claimed} = Workflows.claim_task(job.id, "task_pending", "worker_1")
    end

    test "claimable: running task by same worker", %{job: job} do
      {:ok, _} =
        Workflows.create_task_execution(%{
          job_id: job.id,
          task_id: "task_running",
          status: :running,
          execution_type: "local",
          claimed_by_worker: "worker_1",
          started_at: DateTime.utc_now()
        })

      assert {:ok, :claimed} = Workflows.claim_task(job.id, "task_running", "worker_1")
    end

    test "claimable: failed task (for retry)", %{job: job} do
      {:ok, _} =
        Workflows.create_task_execution(%{
          job_id: job.id,
          task_id: "task_failed",
          status: :failed,
          execution_type: "local",
          error: "Previous error",
          completed_at: DateTime.utc_now()
        })

      assert {:ok, :claimed} = Workflows.claim_task(job.id, "task_failed", "worker_1")
    end

    test "NOT claimable: success task", %{job: job} do
      {:ok, _} =
        Workflows.create_task_execution(%{
          job_id: job.id,
          task_id: "task_success",
          status: :success,
          execution_type: "local",
          result: %{"data" => "result"},
          completed_at: DateTime.utc_now()
        })

      assert {:error, :already_completed} = Workflows.claim_task(job.id, "task_success", "worker_1")
    end

    test "NOT claimable: upstream_failed task", %{job: job} do
      {:ok, _} =
        Workflows.create_task_execution(%{
          job_id: job.id,
          task_id: "task_skipped",
          status: :upstream_failed,
          execution_type: "local",
          completed_at: DateTime.utc_now()
        })

      assert {:error, :already_completed} =
               Workflows.claim_task(job.id, "task_skipped", "worker_1")
    end
  end

  # Helper function to get task execution by job_id and task_id
  defp get_task_execution!(job_id, task_id) do
    task_executions = Workflows.list_task_executions_for_job(job_id)
    Enum.find(task_executions, fn te -> te.task_id == task_id end)
  end
end
