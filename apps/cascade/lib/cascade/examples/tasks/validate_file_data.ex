defmodule Cascade.Examples.Tasks.ValidateFileData do
  @moduledoc """
  Validates file data.
  """

  require Logger

  def run(context) do
    Logger.info("ValidateFileData: Validating file data for job #{context.job_id}")
    Process.sleep(600)
    {:ok, %{valid_records: 2970, invalid_records: 30, validation_time: DateTime.utc_now()}}
  end
end
