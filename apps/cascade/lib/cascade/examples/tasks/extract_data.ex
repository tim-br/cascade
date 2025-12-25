defmodule Cascade.Examples.Tasks.ExtractData do
  @moduledoc """
  Simulates extracting data from a source.
  """

  require Logger

  def run(context) do
    Logger.info("ExtractData: Starting data extraction for job #{context.job_id}")

    # Simulate some work
    Process.sleep(1000)

    result = %{
      records_extracted: 1000,
      source: "database",
      timestamp: DateTime.utc_now()
    }

    Logger.info("ExtractData: Extracted #{result.records_extracted} records")

    {:ok, result}
  end
end
