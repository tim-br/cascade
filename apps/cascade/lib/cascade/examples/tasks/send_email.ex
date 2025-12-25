defmodule Cascade.Examples.Tasks.SendEmail do
  @moduledoc """
  Sends completion email.
  """

  require Logger

  def run(context) do
    Logger.info("SendEmail: Sending completion email for job #{context.job_id}")
    Process.sleep(400)
    {:ok, %{emails_sent: 3, recipients: ["team@example.com", "manager@example.com"], timestamp: DateTime.utc_now()}}
  end
end
