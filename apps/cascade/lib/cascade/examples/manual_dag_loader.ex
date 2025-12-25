defmodule Cascade.Examples.ManualDAGLoader do
  @moduledoc """
  Manual DAG loader that bypasses the DSL to create a working DAG.
  This is a workaround until the DSL macro is fixed.
  """

  alias Cascade.Workflows
  alias Cascade.DSL.Validator

  @doc """
  Loads a working ETL DAG with proper module configuration.
  """
  def load_working_etl_dag do
    # Manual DAG definition with all config properly set
    definition = %{
      "name" => "working_etl_pipeline",
      "nodes" => [
        %{
          "id" => "extract",
          "type" => "local",
          "config" => %{
            "module" => "Cascade.Examples.Tasks.ExtractData",
            "timeout" => 300
          }
        },
        %{
          "id" => "transform",
          "type" => "local",
          "config" => %{
            "module" => "Cascade.Examples.Tasks.TransformData",
            "timeout" => 300
          }
        },
        %{
          "id" => "load",
          "type" => "local",
          "config" => %{
            "module" => "Cascade.Examples.Tasks.LoadData",
            "timeout" => 300
          }
        },
        %{
          "id" => "notify",
          "type" => "local",
          "config" => %{
            "module" => "Cascade.Examples.Tasks.SendNotification",
            "timeout" => 60
          }
        }
      ],
      "edges" => [
        %{"from" => "extract", "to" => "transform", "type" => "success"},
        %{"from" => "transform", "to" => "load", "type" => "success"},
        %{"from" => "load", "to" => "notify", "type" => "success"}
      ],
      "metadata" => %{
        "description" => "Working ETL pipeline (manual)",
        "schedule" => "0 2 * * *"
      }
    }

    # Validate
    case Validator.validate(definition) do
      {:ok, validated_def} ->
        # Check if DAG already exists
        case Workflows.get_dag_by_name("working_etl_pipeline") do
          nil ->
            # Create new DAG
            Workflows.create_dag(%{
              name: "working_etl_pipeline",
              description: "Working ETL Pipeline (bypasses DSL)",
              schedule: "0 2 * * *",
              definition: validated_def,
              compiled_at: DateTime.utc_now(),
              enabled: true
            })

          existing_dag ->
            # Update existing DAG
            Workflows.update_dag(existing_dag, %{
              description: "Working ETL Pipeline (bypasses DSL)",
              schedule: "0 2 * * *",
              definition: validated_def,
              compiled_at: DateTime.utc_now(),
              version: existing_dag.version + 1
            })
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
