defmodule Cascade.Examples.Tasks.TransformCustomers do
  @moduledoc """
  Transforms customer data.
  """

  require Logger

  def run(context) do
    Logger.info("TransformCustomers: Transforming customer data for job #{context.job_id}")
    Process.sleep(3000)
    {:ok, %{customers_transformed: 4500, enrichment_applied: true, timestamp: DateTime.utc_now()}}
  end
end
