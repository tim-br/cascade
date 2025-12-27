defmodule Cascade.Repo.Migrations.AddTaskClaimFields do
  use Ecto.Migration

  def change do
    alter table(:task_executions) do
      add :claimed_by_worker, :string
      add :claimed_at, :utc_datetime
    end

    # Index for efficient claim lookups
    create index(:task_executions, [:job_id, :task_id, :claimed_by_worker])
  end
end
