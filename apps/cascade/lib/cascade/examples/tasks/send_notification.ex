defmodule Cascade.Examples.Tasks.SendNotification do
  @moduledoc """
  Simulates sending a notification.
  """

  require Logger

  def run(context) do
    Logger.info("SendNotification: Sending completion notification for job #{context.job_id}")

    # Simulate sending email/slack notification
    Process.sleep(500)

    result = %{
      notification_sent: true,
      recipients: ["team@example.com"],
      timestamp: DateTime.utc_now()
    }

    Logger.info("SendNotification: Notification sent successfully")

    {:ok, result}
  end
end
