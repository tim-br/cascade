# Reusable task library - Similar to Airflow's my_tasks/weather.py
# Define task modules that can be imported by multiple DAGs

defmodule ReusableTasks.DataPipeline do
  @moduledoc "Reusable data pipeline tasks"

  defmodule FetchFromAPI do
    def run(payload) do
      context = Map.get(payload, :context, %{})
      api_url = Map.get(context, "api_url", "https://api.example.com/data")

      IO.puts("FetchFromAPI: Calling #{api_url}...")
      Process.sleep(1000)

      data = %{
        "source" => api_url,
        "records" => 500,
        "fetched_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      }

      IO.puts("FetchFromAPI: Retrieved #{data["records"]} records")
      {:ok, data}
    end
  end

  defmodule ValidateData do
    def run(payload) do
      context = Map.get(payload, :context, %{})
      upstream_results = Map.get(context, "upstream_results", %{})

      fetch_result = Map.get(upstream_results, "fetch", %{})
      record_count = Map.get(fetch_result, "records", 0)

      IO.puts("ValidateData: Checking #{record_count} records...")
      Process.sleep(500)

      validation = %{
        "total_records" => record_count,
        "valid_records" => record_count,
        "invalid_records" => 0,
        "validated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      }

      IO.puts("ValidateData: All #{validation["valid_records"]} records valid!")
      {:ok, validation}
    end
  end

  defmodule SaveToWarehouse do
    def run(payload) do
      context = Map.get(payload, :context, %{})
      upstream_results = Map.get(context, "upstream_results", %{})

      validation = Map.get(upstream_results, "validate", %{})
      valid_count = Map.get(validation, "valid_records", 0)

      IO.puts("SaveToWarehouse: Saving #{valid_count} records to warehouse...")
      Process.sleep(800)

      result = %{
        "table" => "analytics.raw_data",
        "records_inserted" => valid_count,
        "partition" => Date.utc_today() |> Date.to_string(),
        "saved_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      }

      IO.puts("SaveToWarehouse: Saved to #{result["table"]}")
      {:ok, result}
    end
  end
end

# This file doesn't return a DAG - it's just a library
# DAGs will import these tasks using: Code.require_file("reusable_tasks.exs", "dags")
nil
