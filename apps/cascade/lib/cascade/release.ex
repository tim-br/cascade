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
  Load the cloud-only DAG (for production deployment).
  """
  def load_dags do
    load_app()
    start_repos()

    IO.puts("Loading cloud-only DAG...")

    case Cascade.Examples.DAGLoader.load_cloud_only_dag() do
      {:ok, dag} ->
        IO.puts("✓ Loaded DAG: #{dag.name}")
        :ok

      {:error, reason} ->
        IO.puts("✗ Error loading DAG: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end

  defp start_repos do
    for repo <- repos() do
      {:ok, _} = repo.start_link(pool_size: 2)
    end
  end
end
