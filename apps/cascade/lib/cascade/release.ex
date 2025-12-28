defmodule Cascade.Release do
  @moduledoc """
  Release tasks for production deployment.

  These tasks are run using:
    bin/init eval "Cascade.Release.migrate()"
    bin/init eval "Cascade.Release.load_dags()"
  """

  @app :cascade

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Load all cloud-only DAGs (for production deployment).
  """
  def load_dags do
    load_app()
    start_repos()

    IO.puts("Loading cloud-only DAGs...")

    # Load cloud test pipeline
    result1 = case Cascade.Examples.DAGLoader.load_cloud_only_dag() do
      {:ok, dag} ->
        IO.puts("✓ Loaded DAG: #{dag.name}")
        :ok

      {:error, reason} ->
        IO.puts("✗ Error loading cloud_test_pipeline: #{inspect(reason)}")
        {:error, reason}
    end

    # Load literary analysis pipeline
    result2 = case Cascade.Examples.DAGLoader.load_literary_analysis_dag() do
      {:ok, dag} ->
        IO.puts("✓ Loaded DAG: #{dag.name}")
        :ok

      {:error, reason} ->
        IO.puts("✗ Error loading literary_analysis_pipeline: #{inspect(reason)}")
        {:error, reason}
    end

    result3 = case Cascade.Examples.DAGLoader.load_test_flaky_dag() do
      {:ok, dag} ->
        IO.puts("✓ Loaded DAG: #{dag.name}")
        :ok

      {:error, reason} ->
        IO.puts("✗ Error loading flaky dag: #{inspect(reason)}")
        {:error, reason}
    end

    # Return error if any failed
    case {result1, result2, result3} do
      {:ok, :ok, :ok} -> :ok
      _ -> {:error, "One or more DAGs failed to load"}
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end

  defp start_repos do
    # Ensure required apps are started
    Application.ensure_all_started(:ssl)
    Application.ensure_all_started(:postgrex)
    Application.ensure_all_started(:ecto)
    Application.ensure_all_started(:ecto_sql)
    Application.ensure_all_started(:telemetry)

    for repo <- repos() do
      {:ok, _} = repo.start_link(pool_size: 2)
    end
  end
end
