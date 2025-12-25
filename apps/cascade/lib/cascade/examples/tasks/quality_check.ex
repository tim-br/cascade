defmodule Cascade.Examples.Tasks.QualityCheck do
  @moduledoc """
  Performs data quality checks.
  """

  require Logger

  def run(context) do
    Logger.info("QualityCheck: Running quality checks for job #{context.job_id}")
    Process.sleep(1200)
    {:ok, %{quality_score: 98.5, issues_found: 12, timestamp: DateTime.utc_now()}}
  end
end
