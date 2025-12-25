defmodule Cascade.Examples.Tasks.LoadWarehouse do
  @moduledoc """
  Loads data to data warehouse.
  """

  require Logger

  def run(context) do
    Logger.info("LoadWarehouse: Loading data to warehouse for job #{context.job_id}")
    Process.sleep(2500)
    {:ok, %{tables_updated: 8, records_inserted: 15000, timestamp: DateTime.utc_now()}}
  end
end
