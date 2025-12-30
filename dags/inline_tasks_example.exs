# Inline Tasks Example - Similar to Airflow's Python DAG files
# Tasks are defined right here in the DAG file!

# Define custom task modules inline
defmodule InlineTasks.FetchWeatherData do
  @moduledoc """
  Fetch weather data from a mock API
  """

  def run(payload) do
    context = Map.get(payload, :context, %{})
    city = Map.get(context, "city", "San Francisco")

    # Simulate API call
    IO.puts("FetchWeatherData: Fetching weather for #{city}...")
    Process.sleep(500)

    # Mock weather data
    weather_data = %{
      "city" => city,
      "temperature" => 72,
      "conditions" => "Sunny",
      "humidity" => 65,
      "wind_speed" => 12,
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    IO.puts("FetchWeatherData: Retrieved weather data for #{city}")
    {:ok, weather_data}
  end
end

defmodule InlineTasks.AnalyzeWeather do
  @moduledoc """
  Analyze weather data and provide recommendations
  """

  def run(payload) do
    context = Map.get(payload, :context, %{})
    upstream_results = Map.get(context, "upstream_results", %{})

    # Get weather data from upstream task
    weather_data = Map.get(upstream_results, "fetch_weather", %{})
    temperature = Map.get(weather_data, "temperature", 0)
    conditions = Map.get(weather_data, "conditions", "Unknown")

    IO.puts("AnalyzeWeather: Analyzing temperature=#{temperature}°F, conditions=#{conditions}")

    # Determine recommendations
    recommendations = cond do
      temperature > 80 -> ["Stay hydrated", "Use sunscreen", "Avoid outdoor exercise"]
      temperature > 65 -> ["Perfect weather for outdoor activities", "Light jacket recommended"]
      temperature > 50 -> ["Bring a jacket", "Good for a brisk walk"]
      true -> ["Bundle up", "Hot drinks recommended", "Stay warm indoors"]
    end

    analysis = %{
      "temperature" => temperature,
      "conditions" => conditions,
      "comfort_level" => get_comfort_level(temperature),
      "recommendations" => recommendations,
      "analyzed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    IO.puts("AnalyzeWeather: Comfort level is #{analysis["comfort_level"]}")
    {:ok, analysis}
  end

  defp get_comfort_level(temp) when temp > 85, do: "Too Hot"
  defp get_comfort_level(temp) when temp > 65, do: "Comfortable"
  defp get_comfort_level(temp) when temp > 50, do: "Cool"
  defp get_comfort_level(_temp), do: "Cold"
end

defmodule InlineTasks.SendNotification do
  @moduledoc """
  Send weather notification (mock)
  """

  def run(payload) do
    context = Map.get(payload, :context, %{})
    upstream_results = Map.get(context, "upstream_results", %{})

    # Get analysis from upstream task
    analysis = Map.get(upstream_results, "analyze_weather", %{})
    weather_data = Map.get(upstream_results, "fetch_weather", %{})

    city = Map.get(weather_data, "city", "Unknown")
    temperature = Map.get(weather_data, "temperature", 0)
    comfort = Map.get(analysis, "comfort_level", "Unknown")
    recommendations = Map.get(analysis, "recommendations", [])

    # Build notification message
    message = """

    🌤️  WEATHER NOTIFICATION for #{city}
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    Temperature: #{temperature}°F
    Comfort Level: #{comfort}

    Recommendations:
    #{Enum.map_join(recommendations, "\n", fn rec -> "  • #{rec}" end)}
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    """

    IO.puts(message)

    notification_result = %{
      "sent_to" => Map.get(context, "notification_email", "user@example.com"),
      "city" => city,
      "sent_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "message_preview" => "Weather update for #{city}: #{temperature}°F, #{comfort}"
    }

    {:ok, notification_result}
  end
end

defmodule InlineTasks.LogToDatabase do
  @moduledoc """
  Log weather data to database (mock)
  """

  def run(payload) do
    context = Map.get(payload, :context, %{})
    upstream_results = Map.get(context, "upstream_results", %{})

    weather_data = Map.get(upstream_results, "fetch_weather", %{})
    analysis = Map.get(upstream_results, "analyze_weather", %{})

    # Simulate database write
    IO.puts("LogToDatabase: Writing weather record to database...")
    Process.sleep(300)

    record = %{
      "city" => Map.get(weather_data, "city"),
      "temperature" => Map.get(weather_data, "temperature"),
      "conditions" => Map.get(weather_data, "conditions"),
      "comfort_level" => Map.get(analysis, "comfort_level"),
      "timestamp" => Map.get(weather_data, "timestamp"),
      "record_id" => :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
    }

    IO.puts("LogToDatabase: Record saved with ID #{record["record_id"]}")
    {:ok, record}
  end
end

# Return the DAG definition
# This gets evaluated by the DAG loader
%{
  "nodes" => [
    %{
      "id" => "fetch_weather",
      "type" => "local",
      "config" => %{
        "module" => "InlineTasks.FetchWeatherData",
        "timeout" => 30
      }
    },
    %{
      "id" => "analyze_weather",
      "type" => "local",
      "config" => %{
        "module" => "InlineTasks.AnalyzeWeather",
        "timeout" => 30
      },
      "depends_on" => ["fetch_weather"]
    },
    %{
      "id" => "send_notification",
      "type" => "local",
      "config" => %{
        "module" => "InlineTasks.SendNotification",
        "timeout" => 20
      },
      "depends_on" => ["fetch_weather", "analyze_weather"]
    },
    %{
      "id" => "log_to_database",
      "type" => "local",
      "config" => %{
        "module" => "InlineTasks.LogToDatabase",
        "timeout" => 20
      },
      "depends_on" => ["fetch_weather", "analyze_weather"]
    }
  ],
  "edges" => [
    %{"from" => "fetch_weather", "to" => "analyze_weather"},
    %{"from" => "fetch_weather", "to" => "send_notification"},
    %{"from" => "analyze_weather", "to" => "send_notification"},
    %{"from" => "fetch_weather", "to" => "log_to_database"},
    %{"from" => "analyze_weather", "to" => "log_to_database"}
  ],
  "description" => "Weather monitoring pipeline with inline task definitions (Airflow-style)",
  "enabled" => true
}
