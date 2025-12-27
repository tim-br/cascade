defmodule Cascade.Runtime.StatePersistenceTest do
  use Cascade.DataCase, async: false

  alias Cascade.Runtime.Scheduler
  alias Cascade.Workflows

  require Logger

  @moduledoc """
  Tests to verify that task status updates are persisted to Postgres in real-time.

  Current bug: Tasks show as "pending" in the database even after they've completed.
  The `started_at` field is nil, and status updates happen in ETS but don't sync to Postgres.
  """

  setup do
    # Load the test flaky DAG
    {:ok, dag} = Cascade.Examples.DAGLoader.load_test_flaky_dag()
    %{dag: dag}
  end

  @tag timeout: 60_000
  test "task status updates are persisted to Postgres within 2 seconds", %{dag: dag} do
    # Start a job
    {:ok, job} = Scheduler.trigger_job(dag.id, "persistence_test", %{})

    IO.puts("\n=== Testing Status Persistence to Postgres ===")
    IO.puts("Job ID: #{job.id}")
    IO.puts("Polling database every 500ms for 25 seconds...")
    IO.puts("")

    # Poll the database every 500ms for 25 seconds
    poll_interval = 500
    max_polls = 50  # 25 seconds

    status_timeline = poll_task_status(job.id, poll_interval, max_polls)

    # Print timeline
    IO.puts("\n=== Status Timeline (from Postgres) ===")
    Enum.each(status_timeline, fn {timestamp, snapshot} ->
      IO.puts("Time #{timestamp}ms:")
      Enum.each(snapshot, fn {task_id, status, started_at, completed_at} ->
        started = if started_at, do: "started", else: "NOT_STARTED"
        completed = if completed_at, do: "completed", else: "not_completed"
        IO.puts("  #{task_id}: #{status} (#{started}, #{completed})")
      end)
    end)

    # Analyze the timeline to find issues
    issues = analyze_status_timeline(status_timeline)

    if issues != [] do
      IO.puts("\n=== Issues Found ===")
      Enum.each(issues, fn issue ->
        IO.puts("❌ #{issue}")
      end)

      flunk("Status persistence issues detected:\n" <> Enum.join(issues, "\n"))
    else
      IO.puts("\n✅ All status updates persisted to Postgres in real-time")
    end
  end

  @tag timeout: 60_000
  test "started_at field is populated when task transitions to running", %{dag: dag} do
    {:ok, job} = Scheduler.trigger_job(dag.id, "started_at_test", %{})

    IO.puts("\n=== Testing started_at Field Population ===")
    IO.puts("Job ID: #{job.id}")

    # Wait for tasks to start
    Process.sleep(2000)

    # Check that running/completed tasks have started_at populated
    task_executions = Workflows.list_task_executions_for_job(job.id)

    started_or_completed_tasks =
      Enum.filter(task_executions, fn te ->
        te.status in [:running, :success, :failed, :upstream_failed]
      end)

    issues =
      Enum.flat_map(started_or_completed_tasks, fn te ->
        if te.started_at == nil do
          ["Task #{te.task_id} has status #{te.status} but started_at is nil"]
        else
          []
        end
      end)

    if issues != [] do
      IO.puts("\n=== Issues Found ===")
      Enum.each(issues, fn issue ->
        IO.puts("❌ #{issue}")
      end)

      flunk("started_at field not populated:\n" <> Enum.join(issues, "\n"))
    else
      IO.puts("✅ All running/completed tasks have started_at populated")
    end
  end

  @tag timeout: 60_000
  test "task_a and task_a2 start in parallel (within 200ms of each other)", %{dag: dag} do
    {:ok, job} = Scheduler.trigger_job(dag.id, "parallel_start_test", %{})

    IO.puts("\n=== Testing Parallel Task Start ===")
    IO.puts("Job ID: #{job.id}")

    # Wait for both tasks to start (need to wait longer if only 1 worker since task_a2 takes 15s)
    Process.sleep(20000)

    # Get task executions
    task_executions = Workflows.list_task_executions_for_job(job.id)
    task_a = Enum.find(task_executions, fn te -> te.task_id == "task_a" end)
    task_a2 = Enum.find(task_executions, fn te -> te.task_id == "task_a2" end)

    # Check that both tasks have started_at timestamps
    if task_a.started_at == nil do
      flunk("task_a has no started_at timestamp")
    end

    if task_a2.started_at == nil do
      flunk("task_a2 has no started_at timestamp")
    end

    # Calculate time difference in milliseconds
    time_diff_ms = abs(DateTime.diff(task_a.started_at, task_a2.started_at, :millisecond))

    IO.puts("task_a started at: #{task_a.started_at}")
    IO.puts("task_a2 started at: #{task_a2.started_at}")
    IO.puts("Time difference: #{time_diff_ms}ms")

    if time_diff_ms > 200 do
      flunk("Tasks did not start in parallel. Time difference: #{time_diff_ms}ms (expected ≤ 200ms)")
    else
      IO.puts("✅ Tasks started in parallel (within #{time_diff_ms}ms)")
    end
  end

  # Helper function to poll task status from Postgres
  defp poll_task_status(job_id, interval_ms, max_polls) do
    start_time = System.monotonic_time(:millisecond)

    Enum.reduce(1..max_polls, [], fn _poll_num, acc ->
      current_time = System.monotonic_time(:millisecond) - start_time

      # Query Postgres for current task status
      task_executions = Workflows.list_task_executions_for_job(job_id)

      snapshot =
        Enum.map(task_executions, fn te ->
          {te.task_id, te.status, te.started_at, te.completed_at}
        end)
        |> Enum.sort()

      # Sleep before next poll
      Process.sleep(interval_ms)

      [{current_time, snapshot} | acc]
    end)
    |> Enum.reverse()
  end

  # Analyze the timeline to find status persistence issues
  defp analyze_status_timeline(timeline) do
    # For each task, find when it first appeared as "running" and check if started_at was set
    task_transitions = build_task_transitions(timeline)

    Enum.flat_map(task_transitions, fn {task_id, transitions} ->
      # Find first "running" transition
      first_running = Enum.find(transitions, fn {_time, status, _started, _completed} ->
        status == :running
      end)

      # Find first "success/failed" transition
      first_completed = Enum.find(transitions, fn {_time, status, _started, _completed} ->
        status in [:success, :failed, :upstream_failed]
      end)

      # Check that started_at is populated when running
      started_at_issues = if first_running do
        {time, _status, started_at, _completed_at} = first_running
        if started_at == nil do
          ["Task #{task_id} transitioned to 'running' at #{time}ms but started_at is nil"]
        else
          []
        end
      else
        []
      end

      # Check that completed_at is populated when completed
      completed_at_issues = if first_completed do
        {time, status, started_at, completed_at} = first_completed
        issues = if completed_at == nil do
          ["Task #{task_id} transitioned to completed state at #{time}ms but completed_at is nil"]
        else
          []
        end

        # Also check that started_at is populated for completed tasks
        # BUT: upstream_failed tasks may never have started, so started_at can be nil for them
        issues ++ if started_at == nil && status != :upstream_failed do
          ["Task #{task_id} completed at #{time}ms but started_at is nil (status: #{status})"]
        else
          []
        end
      else
        []
      end

      # Check for tasks stuck in "pending" for too long (>3 seconds after job start)
      # This would indicate status not being updated in Postgres
      stuck_in_pending = Enum.take_while(transitions, fn {time, status, _started, _completed} ->
        status == :pending && time > 3000
      end)

      pending_issues = if length(stuck_in_pending) > 0 do
        {last_time, _, _, _} = List.last(stuck_in_pending)
        if first_running || first_completed do
          # Task eventually ran/completed, so it was stuck
          ["Task #{task_id} stuck in 'pending' status until #{last_time}ms (delayed Postgres update)"]
        else
          # Task might legitimately be pending
          []
        end
      else
        []
      end

      started_at_issues ++ completed_at_issues ++ pending_issues
    end)
  end

  # Build a map of task_id => list of {timestamp, status, started_at, completed_at}
  defp build_task_transitions(timeline) do
    # Get all unique task IDs
    all_task_ids =
      timeline
      |> Enum.flat_map(fn {_time, snapshot} ->
        Enum.map(snapshot, fn {task_id, _status, _started, _completed} -> task_id end)
      end)
      |> Enum.uniq()

    # For each task, build its timeline
    Map.new(all_task_ids, fn task_id ->
      transitions =
        Enum.map(timeline, fn {timestamp, snapshot} ->
          case Enum.find(snapshot, fn {tid, _s, _st, _ct} -> tid == task_id end) do
            {^task_id, status, started_at, completed_at} ->
              {timestamp, status, started_at, completed_at}
            nil ->
              {timestamp, :not_found, nil, nil}
          end
        end)
        |> Enum.reject(fn {_t, status, _s, _c} -> status == :not_found end)

      {task_id, transitions}
    end)
  end
end
