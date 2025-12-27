defmodule Cascade.Examples.TestFlakyDAG do
  @moduledoc """
  Test DAG for debugging task re-execution issues.

  This DAG has:
  - Task A: Slow (15s) with 50% failure rate
  - Task A2: Slow (15s) with 50% failure rate
  - Task B: Slow (15s) that depends on both Task A and Task A2

  Used to verify that tasks don't get re-executed while other tasks are running.
  """

  use Cascade.DSL

  dag "test_flaky_dag",
    description: "Test DAG: Task A (1s) + Task A2 (15s) -> Task B (15s)",
    schedule: nil,
    tasks: [
      task_a: [
        type: :local,
        module: Cascade.Examples.Tasks.TaskAFlaky,
        timeout: 30
      ],
      task_a2: [
        type: :local,
        module: Cascade.Examples.Tasks.TaskA2Flaky,
        timeout: 30
      ],
      task_b: [
        type: :local,
        module: Cascade.Examples.Tasks.TaskBSlow,
        depends_on: [:task_a, :task_a2],
        timeout: 30
      ]
    ]
end
