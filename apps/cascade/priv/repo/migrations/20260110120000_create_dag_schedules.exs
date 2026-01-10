defmodule Cascade.Repo.Migrations.CreateDagSchedules do
  use Ecto.Migration

  def change do
    create table(:dag_schedules, primary_key: false) do
      add :dag_id, references(:dags, type: :binary_id, on_delete: :delete_all),
          primary_key: true
      add :cron_expression, :string, null: false
      add :last_triggered_at, :utc_datetime
      add :next_run_at, :utc_datetime, null: false
      add :is_active, :boolean, default: true, null: false
      add :last_job_id, :binary_id
      add :consecutive_failures, :integer, default: 0, null: false

      timestamps()
    end

    create index(:dag_schedules, [:next_run_at])
    create index(:dag_schedules, [:is_active])
  end
end
