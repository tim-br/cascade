defmodule Cascade.Repo.Migrations.CreateJobs do
  use Ecto.Migration

  def change do
    create table(:jobs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :dag_id, references(:dags, type: :binary_id, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "pending"
      add :triggered_by, :string, null: false
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime
      add :error, :text
      add :context, :map, default: %{}

      timestamps()
    end

    create index(:jobs, [:dag_id])
    create index(:jobs, [:status])
    create index(:jobs, [:inserted_at])
  end
end
