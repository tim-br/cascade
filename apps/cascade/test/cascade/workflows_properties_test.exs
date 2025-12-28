defmodule Cascade.WorkflowsPropertiesTest do
  use Cascade.DataCase, async: false
  use PropCheck

  alias Cascade.Workflows
  alias Cascade.Workflows.{DAG, Job, TaskExecution}

  @moduledoc """
  Property-based tests for Workflows module, specifically testing
  the claim_task function's guarantees under various scenarios.
  """

  # Generator for task status
  defp task_status_gen do
    oneof([:pending, :running, :success, :failed, :upstream_failed])
  end

  # Generator for worker IDs
  defp worker_id_gen do
    let n <- integer(1, 10) do
      "worker_#{n}"
    end
  end

  describe "claim_task properties" do
    property "completed tasks can never be claimed", [:verbose] do
      forall status <- oneof([:success, :upstream_failed]) do
        # Setup
        {:ok, dag, job} = create_test_dag_and_job()

        {:ok, task} =
          Workflows.create_task_execution(%{
            job_id: job.id,
            task_id: "test_task",
            status: status,
            execution_type: "local",
            completed_at: DateTime.utc_now()
          })

        # Property: Completed tasks should never be claimable
        result = Workflows.claim_task(job.id, "test_task", "any_worker")

        # Cleanup
        cleanup_test_data(dag, job)

        result == {:error, :already_completed}
      end
    end

    property "failed tasks can always be claimed (for retry)", [:verbose] do
      forall worker_id <- worker_id_gen() do
        # Setup
        {:ok, dag, job} = create_test_dag_and_job()

        {:ok, task} =
          Workflows.create_task_execution(%{
            job_id: job.id,
            task_id: "test_task",
            status: :failed,
            execution_type: "local",
            error: "Previous failure",
            completed_at: DateTime.utc_now()
          })

        # Property: Failed tasks should always be claimable (allows retry)
        result = Workflows.claim_task(job.id, "test_task", worker_id)

        # Cleanup
        cleanup_test_data(dag, job)

        result == {:ok, :claimed}
      end
    end

    property "same worker can claim a task multiple times (idempotent)", [:verbose] do
      forall {worker_id, claim_count} <- {worker_id_gen(), integer(1, 5)} do
        # Setup
        {:ok, dag, job} = create_test_dag_and_job()

        {:ok, task} =
          Workflows.create_task_execution(%{
            job_id: job.id,
            task_id: "test_task",
            status: :pending,
            execution_type: "local"
          })

        # Property: Same worker claiming N times should always succeed
        results =
          Enum.map(1..claim_count, fn _ ->
            Workflows.claim_task(job.id, "test_task", worker_id)
          end)

        # Cleanup
        cleanup_test_data(dag, job)

        # All claims should succeed
        Enum.all?(results, fn result -> result == {:ok, :claimed} end)
      end
    end

    property "different workers cannot claim the same pending task", [:verbose] do
      forall {worker1, worker2} <- {worker_id_gen(), worker_id_gen()} do
        implies worker1 != worker2 do
          # Setup
          {:ok, dag, job} = create_test_dag_and_job()

          {:ok, task} =
            Workflows.create_task_execution(%{
              job_id: job.id,
              task_id: "test_task",
              status: :pending,
              execution_type: "local"
            })

          # First worker claims
          {:ok, :claimed} = Workflows.claim_task(job.id, "test_task", worker1)

          # Property: Second worker cannot claim
          result = Workflows.claim_task(job.id, "test_task", worker2)

          # Cleanup
          cleanup_test_data(dag, job)

          result == {:error, :already_claimed}
        end
      end
    end

    property "claim preserves task status for non-terminal states", [:verbose] do
      forall {initial_status, worker_id} <- {oneof([:pending, :running, :failed]), worker_id_gen()} do
        # Setup
        {:ok, dag, job} = create_test_dag_and_job()

        attrs = %{
          job_id: job.id,
          task_id: "test_task",
          status: initial_status,
          execution_type: :local
        }

        attrs =
          if initial_status == :failed do
            Map.put(attrs, :error, "Previous error")
          else
            attrs
          end

        {:ok, task} = Workflows.create_task_execution(attrs)

        # Claim the task
        Workflows.claim_task(job.id, "test_task", worker_id)

        # Get updated task
        updated_task = get_task_execution(job.id, "test_task")

        # Cleanup
        cleanup_test_data(dag, job)

        # Property: Status should remain the same after claim
        # (claim doesn't change status, only marks ownership)
        updated_task.status == initial_status
      end
    end

    property "successful claim sets claimed_by_worker and claimed_at", [:verbose] do
      forall worker_id <- worker_id_gen() do
        # Setup
        {:ok, dag, job} = create_test_dag_and_job()

        {:ok, task} =
          Workflows.create_task_execution(%{
            job_id: job.id,
            task_id: "test_task",
            status: :pending,
            execution_type: "local"
          })

        # Claim the task
        {:ok, :claimed} = Workflows.claim_task(job.id, "test_task", worker_id)

        # Get updated task
        updated_task = get_task_execution(job.id, "test_task")

        # Cleanup
        cleanup_test_data(dag, job)

        # Property: claimed_by_worker should be set correctly
        # and claimed_at should not be nil
        updated_task.claimed_by_worker == worker_id and
          updated_task.claimed_at != nil
      end
    end
  end

  describe "claim_task safety properties" do
    property "CRITICAL: successful tasks cannot transition back to running", [:verbose] do
      forall worker_id <- worker_id_gen() do
        # Setup
        {:ok, dag, job} = create_test_dag_and_job()

        {:ok, task} =
          Workflows.create_task_execution(%{
            job_id: job.id,
            task_id: "test_task",
            status: :success,
            execution_type: "local",
            result: %{"output" => "completed"},
            completed_at: DateTime.utc_now()
          })

        # Try to claim the successful task
        claim_result = Workflows.claim_task(job.id, "test_task", worker_id)

        # Get task status after claim attempt
        task_after = get_task_execution(job.id, "test_task")

        # Cleanup
        cleanup_test_data(dag, job)

        # Property: Claim should fail AND status should remain :success
        claim_result == {:error, :already_completed} and
          task_after.status == :success
      end
    end

    property "CRITICAL: upstream_failed tasks cannot be re-executed", [:verbose] do
      forall worker_id <- worker_id_gen() do
        # Setup
        {:ok, dag, job} = create_test_dag_and_job()

        {:ok, task} =
          Workflows.create_task_execution(%{
            job_id: job.id,
            task_id: "test_task",
            status: :upstream_failed,
            execution_type: "local",
            completed_at: DateTime.utc_now()
          })

        # Try to claim the skipped task
        claim_result = Workflows.claim_task(job.id, "test_task", worker_id)

        # Get task status after claim attempt
        task_after = get_task_execution(job.id, "test_task")

        # Cleanup
        cleanup_test_data(dag, job)

        # Property: Claim should fail AND status should remain :upstream_failed
        claim_result == {:error, :already_completed} and
          task_after.status == :upstream_failed
      end
    end
  end

  # Helper functions

  defp create_test_dag_and_job do
    dag_name = "test_dag_#{:rand.uniform(1_000_000)}"

    {:ok, dag} =
      Workflows.create_dag(%{
        name: dag_name,
        description: "Property test DAG",
        definition: %{
          "nodes" => [%{"id" => "test_task", "type" => "local", "config" => %{}}],
          "edges" => []
        },
        enabled: true
      })

    {:ok, job} =
      Workflows.create_job(%{
        dag_id: dag.id,
        triggered_by: "property_test",
        status: :running
      })

    {:ok, dag, job}
  end

  defp cleanup_test_data(dag, job) do
    # Delete in correct order due to foreign key constraints
    Cascade.Repo.delete_all(
      from te in TaskExecution,
        where: te.job_id == ^job.id
    )

    Cascade.Repo.delete(job)
    Cascade.Repo.delete(dag)
  end

  defp get_task_execution(job_id, task_id) do
    task_executions = Workflows.list_task_executions_for_job(job_id)
    Enum.find(task_executions, fn te -> te.task_id == task_id end)
  end
end
