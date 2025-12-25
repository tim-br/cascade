defmodule Cascade.Examples.Tasks.FetchDatabaseData do
  @moduledoc """
  Fetches data from database source.
  """

  require Logger

  def run(context) do
    Logger.info("FetchDatabaseData: Fetching data from database for job #{context.job_id}")
    Process.sleep(2500)
    {:ok, %{source: "database", records: 8000, timestamp: DateTime.utc_now()}}
  end
end
