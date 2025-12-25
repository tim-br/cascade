defmodule Cascade.Examples.Tasks.GenerateReports do
  @moduledoc """
  Generates business reports.
  """

  require Logger

  def run(context) do
    Logger.info("GenerateReports: Generating reports for job #{context.job_id}")
    Process.sleep(1800)
    {:ok, %{reports_generated: 5, formats: ["pdf", "excel", "html"], timestamp: DateTime.utc_now()}}
  end
end
