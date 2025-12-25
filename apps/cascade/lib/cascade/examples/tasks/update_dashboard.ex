defmodule Cascade.Examples.Tasks.UpdateDashboard do
  @moduledoc """
  Updates analytics dashboard.
  """

  require Logger

  def run(context) do
    Logger.info("UpdateDashboard: Updating dashboard for job #{context.job_id}")
    Process.sleep(600)
    {:ok, %{widgets_updated: 12, refresh_time: "500ms", timestamp: DateTime.utc_now()}}
  end
end
