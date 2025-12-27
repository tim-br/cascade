defmodule Cascade.Repo.Migrations.CreateWorkerHeartbeats do
  use Ecto.Migration

  def change do
    create table(:worker_heartbeats, primary_key: false) do
      add :node, :string, primary_key: true
      add :last_seen, :utc_datetime, null: false
      add :capacity, :integer, default: 1
      add :active_tasks, :integer, default: 0

      timestamps()
    end

    # Index for efficient lookups of active workers
    create index(:worker_heartbeats, [:last_seen])
  end
end
