defmodule Cascade.Workflows.Job do
  @moduledoc """
  Schema for Job executions.

  A Job is a single execution instance of a DAG.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses [:pending, :running, :success, :failed, :cancelled]

  schema "jobs" do
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :triggered_by, :string
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :error, :string
    field :context, :map, default: %{}

    belongs_to :dag, Cascade.Workflows.DAG
    has_many :task_executions, Cascade.Workflows.TaskExecution

    timestamps()
  end

  @doc false
  def changeset(job, attrs) do
    job
    |> cast(attrs, [:dag_id, :status, :triggered_by, :started_at, :completed_at, :error, :context])
    |> validate_required([:dag_id, :triggered_by])
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:dag_id)
  end

  @doc "Returns list of valid job statuses"
  def statuses, do: @statuses
end
