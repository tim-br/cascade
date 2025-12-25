defmodule Cascade.Workflows.TaskExecution do
  @moduledoc """
  Schema for Task Execution records.

  Tracks the execution of individual tasks within a job.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses [:pending, :queued, :running, :success, :failed, :skipped]

  schema "task_executions" do
    field :task_id, :string
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :worker_node, :string
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :result, :map
    field :error, :string
    field :retry_count, :integer, default: 0
    field :execution_type, :string, default: "local"
    field :lambda_request_id, :string

    belongs_to :job, Cascade.Workflows.Job

    timestamps()
  end

  @doc false
  def changeset(task_execution, attrs) do
    task_execution
    |> cast(attrs, [
      :job_id,
      :task_id,
      :status,
      :worker_node,
      :started_at,
      :completed_at,
      :result,
      :error,
      :retry_count,
      :execution_type,
      :lambda_request_id
    ])
    |> validate_required([:job_id, :task_id, :execution_type])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:execution_type, ["local", "lambda"])
    |> foreign_key_constraint(:job_id)
  end

  @doc "Returns list of valid task execution statuses"
  def statuses, do: @statuses
end
