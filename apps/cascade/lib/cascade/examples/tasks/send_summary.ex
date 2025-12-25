defmodule Cascade.Examples.Tasks.SendSummary do
  @moduledoc """
  Sends summary notification of pipeline execution.

  In a real scenario, this would:
  - Generate execution summary
  - Send email/Slack notification
  - Update monitoring dashboard
  """

  require Logger

  def run(context) do
    Logger.info("SendSummary: Sending pipeline summary (job: #{context.job_id})")

    Process.sleep(500)

    result = %{
      summary_sent: true,
      recipients: ["team@example.com", "data-eng@example.com"],
      notification_type: "email",
      includes_metrics: true,
      timestamp: DateTime.utc_now()
    }

    Logger.info("SendSummary: Summary notification sent successfully")

    {:ok, result}
  end
end
