defmodule Cascade.Examples.Tasks.LoadData do
  @moduledoc """
  Simulates loading data to a destination.
  """

  require Logger

  def run(context) do
    Logger.info("LoadData: Starting data load for job #{context.job_id}")

    # Simulate some work
    Process.sleep(1000)

    # 50% chance to fail (for testing error handling and retries)
    if :rand.uniform() < 0.5 do
      Logger.error("LoadData: Simulated failure (50% chance)")
      {:error, "Simulated load failure for testing"}
    else
      result = %{
        records_loaded: 1000,
        destination: "warehouse",
        timestamp: DateTime.utc_now()
      }

      Logger.info("LoadData: Loaded #{result.records_loaded} records")

      {:ok, result}
    end
  end
end
