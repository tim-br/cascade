defmodule Cascade.Repo.Migrations.CreateTaskExecutions do
  use Ecto.Migration

  def change do
    create table(:task_executions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :job_id, references(:jobs, type: :binary_id, on_delete: :delete_all), null: false
      add :task_id, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :worker_node, :string
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime
      add :result, :map
      add :error, :text
      add :retry_count, :integer, default: 0, null: false
      add :execution_type, :string, null: false, default: "local"
      add :lambda_request_id, :string

      timestamps()
    end

    create index(:task_executions, [:job_id])
    create index(:task_executions, [:status])
    create index(:task_executions, [:task_id])
    create index(:task_executions, [:worker_node])
  end
end
