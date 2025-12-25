defmodule Cascade.Examples.DAGLoader do
  @moduledoc """
  Helper module to load example DAGs into the database.
  """

  alias Cascade.Workflows
  alias Cascade.DSL.Validator

  @doc """
  Loads the ETL DAG into the database.

  Returns {:ok, dag} on success, {:error, reason} on failure.
  """
  def load_etl_dag do
    # Get the DAG definition from the module
    definition = Cascade.Examples.ETLDAG.get_dag_definition()

    # Validate the definition
    case Validator.validate(definition) do
      {:ok, validated_def} ->
        # Check if DAG already exists
        case Workflows.get_dag_by_name(definition["name"]) do
          nil ->
            # Create new DAG
            Workflows.create_dag(%{
              name: definition["name"],
              description: definition["metadata"]["description"],
              schedule: definition["metadata"]["schedule"],
              definition: validated_def,
              compiled_at: DateTime.utc_now(),
              enabled: true
            })

          existing_dag ->
            # Update existing DAG
            Workflows.update_dag(existing_dag, %{
              description: definition["metadata"]["description"],
              schedule: definition["metadata"]["schedule"],
              definition: validated_def,
              compiled_at: DateTime.utc_now(),
              version: existing_dag.version + 1
            })
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Loads all example DAGs.
  """
  def load_all do
    load_etl_dag()
  end
end
