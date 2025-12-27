defmodule Cascade.Examples.Tasks.TaskAFlaky do
  @moduledoc """
  A FAST task with 50% failure rate for testing.
  Runs in ~1 second.
  """

  require Logger

  def run(context) do
    Logger.info("TaskAFlaky: Starting execution for job #{context.job_id}")

    # Simulate work (~1 second)
    Process.sleep(1000)

    # 50% failure rate
    if :rand.uniform(100) <= 50 do
      Logger.error("TaskAFlaky: Failed after 1 second (50% chance)")
      {:error, "Random failure - 50% chance"}
    else
      result = %{
        status: "success",
        timestamp: DateTime.utc_now(),
        data: "Task A completed successfully"
      }

      Logger.info("TaskAFlaky: Completed successfully")
      {:ok, result}
    end
  end
end
