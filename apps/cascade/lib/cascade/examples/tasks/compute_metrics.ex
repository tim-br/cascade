defmodule Cascade.Examples.Tasks.ComputeMetrics do
  @moduledoc """
  Computes business metrics.
  """

  require Logger

  def run(context) do
    Logger.info("ComputeMetrics: Computing metrics for job #{context.job_id}")
    Process.sleep(2000)
    {:ok, %{metrics_computed: 150, kpis_calculated: 25, timestamp: DateTime.utc_now()}}
  end
end
