defmodule Cascade.Examples.Tasks do
  @moduledoc """
  Example task modules for testing Cascade.
  """

  defmodule ExtractData do
    @moduledoc """
    Simulates extracting data from a source.
    """

    require Logger

    def run(context) do
      Logger.info("ExtractData: Starting data extraction for job #{context.job_id}")

      # Simulate some work
      Process.sleep(1000)

      result = %{
        records_extracted: 1000,
        source: "database",
        timestamp: DateTime.utc_now()
      }

      Logger.info("ExtractData: Extracted #{result.records_extracted} records")

      {:ok, result}
    end
  end

  defmodule TransformData do
    @moduledoc """
    Simulates transforming data.
    """

    require Logger

    def run(context) do
      Logger.info("TransformData: Starting data transformation for job #{context.job_id}")

      # Simulate some work
      Process.sleep(1500)

      result = %{
        records_transformed: 1000,
        transformations_applied: ["clean", "normalize", "enrich"],
        timestamp: DateTime.utc_now()
      }

      Logger.info("TransformData: Transformed #{result.records_transformed} records")

      {:ok, result}
    end
  end

  defmodule LoadData do
    @moduledoc """
    Simulates loading data to a destination.
    """

    require Logger

    def run(context) do
      Logger.info("LoadData: Starting data load for job #{context.job_id}")

      # Simulate some work
      Process.sleep(1000)

      result = %{
        records_loaded: 1000,
        destination: "warehouse",
        timestamp: DateTime.utc_now()
      }

      Logger.info("LoadData: Loaded #{result.records_loaded} records")

      {:ok, result}
    end
  end

  defmodule SendNotification do
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
end
