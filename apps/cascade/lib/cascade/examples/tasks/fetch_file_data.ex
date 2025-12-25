defmodule Cascade.Examples.Tasks.FetchFileData do
  @moduledoc """
  Fetches data from file source.
  """

  require Logger

  def run(context) do
    Logger.info("FetchFileData: Fetching data from files for job #{context.job_id}")
    Process.sleep(1500)
    {:ok, %{source: "files", records: 3000, timestamp: DateTime.utc_now()}}
  end
end
