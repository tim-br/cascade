defmodule Cascade.Examples.Tasks.TransformTransactions do
  @moduledoc """
  Transforms transaction data.
  """

  require Logger

  def run(context) do
    Logger.info("TransformTransactions: Transforming transaction data for job #{context.job_id}")
    Process.sleep(3500)
    {:ok, %{transactions_transformed: 12000, aggregations_computed: 450, timestamp: DateTime.utc_now()}}
  end
end
