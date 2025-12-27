defmodule Mix.Tasks.Cascade.LoadDag do
  @moduledoc """
  Mix task to load example DAGs into the database.

  ## Usage

      # Load a specific DAG
      mix cascade.load_dag test_flaky
      mix cascade.load_dag etl
      mix cascade.load_dag complex
      mix cascade.load_dag hybrid
      mix cascade.load_dag cloud_only
      mix cascade.load_dag literary_analysis

      # Load all example DAGs
      mix cascade.load_dag all

      # List available DAGs
      mix cascade.load_dag list

  ## Examples

      # Load the test flaky DAG
      $ mix cascade.load_dag test_flaky
      Loading test_flaky_dag...
      ✓ Successfully loaded DAG: test_flaky_dag (id: 123e4567-e89b-12d3-a456-426614174000)

      # Load all DAGs
      $ mix cascade.load_dag all
      Loading all example DAGs...
      ✓ etl_pipeline
      ✓ complex_data_processing
      ✓ hybrid_lambda_local
      ✓ cloud_only_test
      ✓ literary_analysis_pipeline
      ✓ test_flaky_dag
      All DAGs loaded successfully!

  """

  use Mix.Task

  @shortdoc "Load example DAGs into the database"

  @impl Mix.Task
  def run(args) do
    # Start the application
    Mix.Task.run("app.start")

    case args do
      ["test_flaky"] ->
        load_dag("test_flaky", &Cascade.Examples.DAGLoader.load_test_flaky_dag/0)

      ["etl"] ->
        load_dag("etl", &Cascade.Examples.DAGLoader.load_etl_dag/0)

      ["complex"] ->
        load_dag("complex", &Cascade.Examples.DAGLoader.load_complex_dag/0)

      ["hybrid"] ->
        load_dag("hybrid", &Cascade.Examples.DAGLoader.load_hybrid_dag/0)

      ["cloud_only"] ->
        load_dag("cloud_only", &Cascade.Examples.DAGLoader.load_cloud_only_dag/0)

      ["literary_analysis"] ->
        load_dag("literary_analysis", &Cascade.Examples.DAGLoader.load_literary_analysis_dag/0)

      ["all"] ->
        load_all_dags()

      ["list"] ->
        list_available_dags()

      [] ->
        show_usage()

      _ ->
        Mix.shell().error("Unknown DAG: #{Enum.join(args, " ")}")
        show_usage()
        exit({:shutdown, 1})
    end
  end

  defp load_dag(name, loader_fn) do
    Mix.shell().info("Loading #{name} DAG...")

    case loader_fn.() do
      {:ok, dag} ->
        Mix.shell().info("✓ Successfully loaded DAG: #{dag.name} (id: #{dag.id})")
        :ok

      {:error, %Ecto.Changeset{} = changeset} ->
        Mix.shell().error("✗ Failed to load #{name} DAG:")
        Mix.shell().error(inspect(changeset.errors, pretty: true))
        exit({:shutdown, 1})

      {:error, reason} ->
        Mix.shell().error("✗ Failed to load #{name} DAG: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp load_all_dags do
    Mix.shell().info("Loading all example DAGs...")

    dags = [
      {"etl", &Cascade.Examples.DAGLoader.load_etl_dag/0},
      {"complex", &Cascade.Examples.DAGLoader.load_complex_dag/0},
      {"hybrid", &Cascade.Examples.DAGLoader.load_hybrid_dag/0},
      {"cloud_only", &Cascade.Examples.DAGLoader.load_cloud_only_dag/0},
      {"literary_analysis", &Cascade.Examples.DAGLoader.load_literary_analysis_dag/0},
      {"test_flaky", &Cascade.Examples.DAGLoader.load_test_flaky_dag/0}
    ]

    results =
      Enum.map(dags, fn {name, loader_fn} ->
        case loader_fn.() do
          {:ok, dag} ->
            Mix.shell().info("  ✓ #{dag.name}")
            :ok

          {:error, reason} ->
            Mix.shell().error("  ✗ #{name}: #{inspect(reason)}")
            :error
        end
      end)

    if Enum.all?(results, &(&1 == :ok)) do
      Mix.shell().info("\nAll DAGs loaded successfully!")
      :ok
    else
      Mix.shell().error("\nSome DAGs failed to load")
      exit({:shutdown, 1})
    end
  end

  defp list_available_dags do
    Mix.shell().info("""
    Available DAGs:

      test_flaky         - Test DAG with flaky tasks (task_a: 1s/50% fail, task_a2: 15s/50% fail)
      etl                - ETL pipeline example
      complex            - Complex data processing pipeline
      hybrid             - Hybrid Lambda/local task execution
      cloud_only         - Cloud-only test DAG
      literary_analysis  - Literary analysis pipeline
      all                - Load all example DAGs

    Usage: mix cascade.load_dag <dag_name>
    """)
  end

  defp show_usage do
    Mix.shell().info("""
    Usage: mix cascade.load_dag <dag_name>

    Available DAGs:
      test_flaky, etl, complex, hybrid, cloud_only, literary_analysis, all

    For more information: mix help cascade.load_dag
    """)
  end
end
