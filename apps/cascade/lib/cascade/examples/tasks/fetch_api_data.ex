defmodule Cascade.Examples.Tasks.FetchAPIData do
  @moduledoc """
  Fetches data from API source.
  """

  require Logger

  def run(context) do
    Logger.info("FetchAPIData: Fetching data from API for job #{context.job_id}")
    Process.sleep(2000)
    {:ok, %{source: "api", records: 5000, timestamp: DateTime.utc_now()}}
  end
end
