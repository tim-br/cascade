defmodule Cascade.Examples.Tasks.TaskBSlow do
  @moduledoc """
  A slow task that depends on Task A.
  Runs in 15 seconds.
  """

  require Logger

  def run(context) do
    Logger.info("TaskBSlow: Starting execution for job #{context.job_id}")

    # Get result from Task A (upstream dependency)
    task_a_result = get_in(context, [:upstream_results, "task_a"])

    Logger.info("TaskBSlow: Received from Task A: #{inspect(task_a_result)}")

    # Simulate long-running work (15 seconds)
    Logger.info("TaskBSlow: Processing for 15 seconds...")
    Process.sleep(15_000)

    result = %{
      status: "success",
      timestamp: DateTime.utc_now(),
      data: "Task B completed successfully",
      upstream_data: task_a_result
    }

    Logger.info("TaskBSlow: Completed successfully after 15 seconds")
    {:ok, result}
  end
end
