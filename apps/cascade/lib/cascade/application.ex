defmodule Cascade.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Run migrations automatically for SQLite in containerized environments
    # For Postgres, use manual migration commands
    maybe_run_migrations()

    children = [
      # Infrastructure
      Cascade.Repo,
      {DNSCluster, query: Application.get_env(:cascade, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Cascade.PubSub},

      # DAG Loader (loads DAGs from directory/S3)
      Cascade.DagLoader,

      # Cascade Runtime
      {Cascade.Runtime.StateManager, []},
      {Cascade.Runtime.WorkerSupervisor, []},
      {Cascade.Runtime.Scheduler, []},
      {Cascade.Runtime.Executor, []}
    ]

    opts = [strategy: :one_for_one, name: Cascade.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        # Start worker pool after supervisor is up
        start_worker_pool()
        {:ok, pid}

      error ->
        error
    end
  end

  defp maybe_run_migrations do
    backend = Application.get_env(:cascade, :storage_backend, Cascade.Storage.SQLiteBackend)
    auto_migrate = System.get_env("AUTO_MIGRATE", "true") == "true"

    # Auto-migrate for SQLite (single-node, file-based)
    # For Postgres, disable auto-migrate and require explicit migration commands
    if backend == Cascade.Storage.SQLiteBackend and auto_migrate do
      Cascade.Release.migrate()
    end
  end

  defp start_worker_pool do
    # Start worker processes
    # Can be configured via environment variable
    worker_count =
      case System.get_env("CASCADE_WORKERS") do
        # Use default (2x schedulers)
        nil -> nil
        count -> String.to_integer(count)
      end

    Cascade.Runtime.WorkerSupervisor.start_workers(worker_count)
  end
end
