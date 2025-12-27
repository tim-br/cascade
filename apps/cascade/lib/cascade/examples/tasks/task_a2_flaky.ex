defmodule Cascade.Examples.Tasks.TaskA2Flaky do
  @moduledoc """
  A SLOW task with 50% failure rate for testing.
  Runs in ~15 seconds.
  """

  require Logger

  def run(context) do
    Logger.info("TaskA2Flaky: Starting execution for job #{context.job_id}")

    # Simulate long work (15 seconds)
    Logger.info("TaskA2Flaky: Processing for 15 seconds...")
    Process.sleep(15_000)

    # 50% failure rate
    if :rand.uniform(100) <= 50 do
      Logger.error("TaskA2Flaky: Failed after 15 seconds (50% chance)")
      {:error, "Random failure - 50% chance"}
    else
      result = %{
        status: "success",
        timestamp: DateTime.utc_now(),
        data: "Task A2 completed successfully after 15 seconds"
      }

      Logger.info("TaskA2Flaky: Completed successfully after 15 seconds")
      {:ok, result}
    end
  end
end
