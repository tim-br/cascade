defmodule Cascade.Repo.Migrations.CreateDags do
  use Ecto.Migration

  def change do
    create table(:dags, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :schedule, :string
      add :enabled, :boolean, default: true, null: false
      add :definition, :map, null: false
      add :version, :integer, default: 1, null: false
      add :compiled_at, :utc_datetime

      timestamps()
    end

    create unique_index(:dags, [:name])
    create index(:dags, [:enabled])
  end
end
