defmodule Cascade.Examples.Tasks.ValidateDatabaseData do
  @moduledoc """
  Validates database data.
  """

  require Logger

  def run(context) do
    Logger.info("ValidateDatabaseData: Validating database data for job #{context.job_id}")
    Process.sleep(1000)
    {:ok, %{valid_records: 7920, invalid_records: 80, validation_time: DateTime.utc_now()}}
  end
end
