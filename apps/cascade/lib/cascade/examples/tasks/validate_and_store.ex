defmodule Cascade.Examples.Tasks.ValidateAndStore do
  @moduledoc """
  Validates Lambda results and stores to database.

  In a real scenario, this would:
  - Download aggregated results from S3
  - Validate data quality
  - Store to database
  - Update metrics
  """

  require Logger

  def run(context) do
    Logger.info("ValidateAndStore: Validating and storing Lambda results (job: #{context.job_id})")

    Process.sleep(1500)

    result = %{
      records_validated: 30000,
      records_stored: 29850,
      errors: 150,
      validation_passed: true,
      database_rows_inserted: 29850,
      timestamp: DateTime.utc_now()
    }

    Logger.info("ValidateAndStore: Stored #{result.records_stored} records to database")

    {:ok, result}
  end
end
