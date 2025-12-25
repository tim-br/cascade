defmodule Cascade.Examples.Tasks.PrepareData do
  @moduledoc """
  Prepares data for Lambda processing.

  In a real scenario, this would:
  - Query database
  - Split data into chunks
  - Upload chunks to S3 for Lambda processing
  """

  require Logger

  def run(context) do
    Logger.info("PrepareData: Preparing data for Lambda processing (job: #{context.job_id})")

    Process.sleep(2000)

    result = %{
      total_records: 30000,
      chunks_created: 3,
      chunk_size: 10000,
      s3_prefix: "input/#{context.job_id}/",
      timestamp: DateTime.utc_now()
    }

    Logger.info(
      "PrepareData: Created #{result.chunks_created} chunks of #{result.chunk_size} records"
    )

    {:ok, result}
  end
end
