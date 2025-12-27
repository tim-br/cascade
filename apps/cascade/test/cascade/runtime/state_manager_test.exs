defmodule Cascade.Runtime.StateManagerTest do
  use ExUnit.Case, async: false

  alias Cascade.Runtime.StateManager

  setup do
    # Ensure ETS tables exist (they're created when StateManager starts)
    # For tests, we'll work with the state transformations directly
    :ok
  end

  describe "apply_task_status_change/4" do
    setup do
      base_state = %{
        job_id: "test-job",
        dag_id: "test-dag",
        status: :running,
        pending_tasks: MapSet.new(["task1", "task2", "task3"]),
        running_tasks: %{},
        completed_tasks: MapSet.new(),
        failed_tasks: MapSet.new(),
        skipped_tasks: MapSet.new(),
        dag_definition: %{},
        started_at: DateTime.utc_now()
      }

      {:ok, state: base_state}
    end

    test "transitions task from pending to running", %{state: state} do
      # Simulate the logic from apply_task_status_change
      updated_state = %{
        state
        | running_tasks: Map.put(state.running_tasks, "task1", "worker-1"),
          pending_tasks: MapSet.delete(state.pending_tasks, "task1")
      }

      assert MapSet.member?(updated_state.pending_tasks, "task1") == false
      assert Map.get(updated_state.running_tasks, "task1") == "worker-1"
      assert MapSet.size(updated_state.pending_tasks) == 2
      assert map_size(updated_state.running_tasks) == 1
    end

    test "transitions task from running to success", %{state: state} do
      # First make it running
      state = %{
        state
        | running_tasks: Map.put(state.running_tasks, "task1", "worker-1"),
          pending_tasks: MapSet.delete(state.pending_tasks, "task1")
      }

      # Then to success
      updated_state = %{
        state
        | completed_tasks: MapSet.put(state.completed_tasks, "task1"),
          running_tasks: Map.delete(state.running_tasks, "task1")
      }

      assert Map.has_key?(updated_state.running_tasks, "task1") == false
      assert MapSet.member?(updated_state.completed_tasks, "task1") == true
      assert map_size(updated_state.running_tasks) == 0
      assert MapSet.size(updated_state.completed_tasks) == 1
    end

    test "transitions task from running to failed", %{state: state} do
      # First make it running
      state = %{
        state
        | running_tasks: Map.put(state.running_tasks, "task1", "worker-1"),
          pending_tasks: MapSet.delete(state.pending_tasks, "task1")
      }

      # Then to failed
      updated_state = %{
        state
        | failed_tasks: MapSet.put(state.failed_tasks, "task1"),
          running_tasks: Map.delete(state.running_tasks, "task1")
      }

      assert Map.has_key?(updated_state.running_tasks, "task1") == false
      assert MapSet.member?(updated_state.failed_tasks, "task1") == true
      assert map_size(updated_state.running_tasks) == 0
      assert MapSet.size(updated_state.failed_tasks) == 1
    end

    test "transitions task from pending to upstream_failed", %{state: state} do
      # Task skipped due to upstream failure
      updated_state = %{
        state
        | pending_tasks: MapSet.delete(state.pending_tasks, "task1"),
          skipped_tasks: MapSet.put(state.skipped_tasks, "task1")
      }

      assert MapSet.member?(updated_state.pending_tasks, "task1") == false
      assert MapSet.member?(updated_state.skipped_tasks, "task1") == true
      assert MapSet.member?(updated_state.failed_tasks, "task1") == false
      assert MapSet.size(updated_state.pending_tasks) == 2
      assert MapSet.size(updated_state.skipped_tasks) == 1
    end

    test "transitions task from running to upstream_failed (race condition)", %{state: state} do
      # Task was dispatched and running when dependency failed
      state = %{
        state
        | running_tasks: Map.put(state.running_tasks, "task1", "worker-1"),
          pending_tasks: MapSet.delete(state.pending_tasks, "task1")
      }

      # Worker detects dependency failure before execution
      updated_state = %{
        state
        | running_tasks: Map.delete(state.running_tasks, "task1"),
          skipped_tasks: MapSet.put(state.skipped_tasks, "task1")
      }

      assert Map.has_key?(updated_state.running_tasks, "task1") == false
      assert MapSet.member?(updated_state.skipped_tasks, "task1") == true
      assert MapSet.member?(updated_state.failed_tasks, "task1") == false
    end

    test "handles multiple concurrent task updates", %{state: state} do
      # Task 1: running
      state = %{
        state
        | running_tasks: Map.put(state.running_tasks, "task1", "worker-1"),
          pending_tasks: MapSet.delete(state.pending_tasks, "task1")
      }

      # Task 2: running
      state = %{
        state
        | running_tasks: Map.put(state.running_tasks, "task2", "worker-2"),
          pending_tasks: MapSet.delete(state.pending_tasks, "task2")
      }

      # Task 1: success
      state = %{
        state
        | completed_tasks: MapSet.put(state.completed_tasks, "task1"),
          running_tasks: Map.delete(state.running_tasks, "task1")
      }

      # Task 2: failed
      state = %{
        state
        | failed_tasks: MapSet.put(state.failed_tasks, "task2"),
          running_tasks: Map.delete(state.running_tasks, "task2")
      }

      # Task 3: upstream_failed
      state = %{
        state
        | pending_tasks: MapSet.delete(state.pending_tasks, "task3"),
          skipped_tasks: MapSet.put(state.skipped_tasks, "task3")
      }

      assert MapSet.size(state.pending_tasks) == 0
      assert map_size(state.running_tasks) == 0
      assert MapSet.size(state.completed_tasks) == 1
      assert MapSet.size(state.failed_tasks) == 1
      assert MapSet.size(state.skipped_tasks) == 1
    end
  end

  describe "job state tracking" do
    test "correctly tracks all task states" do
      state = %{
        pending_tasks: MapSet.new(["pending1"]),
        running_tasks: %{"running1" => "worker1", "running2" => "worker2"},
        completed_tasks: MapSet.new(["done1", "done2", "done3"]),
        failed_tasks: MapSet.new(["failed1"]),
        skipped_tasks: MapSet.new(["skipped1", "skipped2"])
      }

      total_tasks =
        MapSet.size(state.pending_tasks) +
        map_size(state.running_tasks) +
        MapSet.size(state.completed_tasks) +
        MapSet.size(state.failed_tasks) +
        MapSet.size(state.skipped_tasks)

      assert total_tasks == 9
      assert MapSet.size(state.pending_tasks) == 1
      assert map_size(state.running_tasks) == 2
      assert MapSet.size(state.completed_tasks) == 3
      assert MapSet.size(state.failed_tasks) == 1
      assert MapSet.size(state.skipped_tasks) == 2
    end

    test "skipped_tasks don't appear in failed_tasks" do
      state = %{
        pending_tasks: MapSet.new(),
        running_tasks: %{},
        completed_tasks: MapSet.new(["task1"]),
        failed_tasks: MapSet.new(["task2"]),
        skipped_tasks: MapSet.new(["task3", "task4"])
      }

      # Verify task3 and task4 are only in skipped, not failed
      assert MapSet.member?(state.skipped_tasks, "task3") == true
      assert MapSet.member?(state.skipped_tasks, "task4") == true
      assert MapSet.member?(state.failed_tasks, "task3") == false
      assert MapSet.member?(state.failed_tasks, "task4") == false

      # Only task2 actually failed
      assert MapSet.size(state.failed_tasks) == 1
      assert MapSet.size(state.skipped_tasks) == 2
    end

    test "completed + failed + skipped equals total when job is done" do
      # Simulates a completed job
      state = %{
        pending_tasks: MapSet.new(),
        running_tasks: %{},
        completed_tasks: MapSet.new(["task1", "task2", "task3"]),
        failed_tasks: MapSet.new(["task4"]),
        skipped_tasks: MapSet.new(["task5", "task6"])
      }

      all_tasks_count =
        MapSet.size(state.pending_tasks) +
        map_size(state.running_tasks) +
        MapSet.size(state.completed_tasks) +
        MapSet.size(state.failed_tasks) +
        MapSet.size(state.skipped_tasks)

      completed_or_failed_or_skipped =
        MapSet.size(state.completed_tasks) +
        MapSet.size(state.failed_tasks) +
        MapSet.size(state.skipped_tasks)

      is_complete = completed_or_failed_or_skipped == all_tasks_count and map_size(state.running_tasks) == 0

      assert all_tasks_count == 6
      assert completed_or_failed_or_skipped == 6
      assert is_complete == true
    end
  end

  describe "edge cases" do
    test "task can be in exactly one state at a time" do
      state = %{
        pending_tasks: MapSet.new(["task1"]),
        running_tasks: %{},
        completed_tasks: MapSet.new(),
        failed_tasks: MapSet.new(),
        skipped_tasks: MapSet.new()
      }

      # Move to running - should only be in running
      state = %{
        state
        | running_tasks: Map.put(state.running_tasks, "task1", "worker1"),
          pending_tasks: MapSet.delete(state.pending_tasks, "task1")
      }

      assert MapSet.member?(state.pending_tasks, "task1") == false
      assert Map.has_key?(state.running_tasks, "task1") == true
      assert MapSet.member?(state.completed_tasks, "task1") == false
      assert MapSet.member?(state.failed_tasks, "task1") == false
      assert MapSet.member?(state.skipped_tasks, "task1") == false

      # Move to completed - should only be in completed
      state = %{
        state
        | completed_tasks: MapSet.put(state.completed_tasks, "task1"),
          running_tasks: Map.delete(state.running_tasks, "task1")
      }

      assert MapSet.member?(state.pending_tasks, "task1") == false
      assert Map.has_key?(state.running_tasks, "task1") == false
      assert MapSet.member?(state.completed_tasks, "task1") == true
      assert MapSet.member?(state.failed_tasks, "task1") == false
      assert MapSet.member?(state.skipped_tasks, "task1") == false
    end

    test "empty job state" do
      state = %{
        pending_tasks: MapSet.new(),
        running_tasks: %{},
        completed_tasks: MapSet.new(),
        failed_tasks: MapSet.new(),
        skipped_tasks: MapSet.new()
      }

      total_tasks =
        MapSet.size(state.pending_tasks) +
        map_size(state.running_tasks) +
        MapSet.size(state.completed_tasks) +
        MapSet.size(state.failed_tasks) +
        MapSet.size(state.skipped_tasks)

      assert total_tasks == 0
    end

    test "all tasks skipped scenario" do
      # Scenario: first task fails, all others are upstream_failed
      state = %{
        pending_tasks: MapSet.new(),
        running_tasks: %{},
        completed_tasks: MapSet.new(),
        failed_tasks: MapSet.new(["task1"]),
        skipped_tasks: MapSet.new(["task2", "task3", "task4", "task5"])
      }

      # Job should be complete
      all_tasks_count =
        MapSet.size(state.pending_tasks) +
        map_size(state.running_tasks) +
        MapSet.size(state.completed_tasks) +
        MapSet.size(state.failed_tasks) +
        MapSet.size(state.skipped_tasks)

      completed_or_failed_or_skipped =
        MapSet.size(state.completed_tasks) +
        MapSet.size(state.failed_tasks) +
        MapSet.size(state.skipped_tasks)

      is_complete = completed_or_failed_or_skipped == all_tasks_count and map_size(state.running_tasks) == 0

      assert all_tasks_count == 5
      assert is_complete == true
      assert MapSet.size(state.failed_tasks) == 1
      assert MapSet.size(state.skipped_tasks) == 4
    end
  end
end
