defmodule Cascade.Examples.Tasks.ValidateAPIData do
  @moduledoc """
  Validates API data.
  """

  require Logger

  def run(context) do
    Logger.info("ValidateAPIData: Validating API data for job #{context.job_id}")
    Process.sleep(800)
    {:ok, %{valid_records: 4950, invalid_records: 50, validation_time: DateTime.utc_now()}}
  end
end
