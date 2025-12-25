defmodule Cascade.Examples.Tasks.TransformData do
  @moduledoc """
  Simulates transforming data.
  """

  require Logger

  def run(context) do
    Logger.info("TransformData: Starting data transformation for job #{context.job_id}")

    # Simulate some work
    Process.sleep(1500)

    result = %{
      records_transformed: 1000,
      transformations_applied: ["clean", "normalize", "enrich"],
      timestamp: DateTime.utc_now()
    }

    Logger.info("TransformData: Transformed #{result.records_transformed} records")

    {:ok, result}
  end
end
