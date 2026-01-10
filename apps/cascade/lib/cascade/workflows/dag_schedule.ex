defmodule Cascade.Workflows.DagSchedule do
  @moduledoc """
  Schema for DAG schedule state.

  Tracks cron scheduling metadata for each DAG, enabling:
  - Restart resilience (last_triggered_at prevents duplicates)
  - Efficient polling (pre-computed next_run_at)
  - Failure tracking (consecutive_failures for monitoring)
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:dag_id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "dag_schedules" do
    field :cron_expression, :string
    field :last_triggered_at, :utc_datetime
    field :next_run_at, :utc_datetime
    field :is_active, :boolean, default: true
    field :last_job_id, :binary_id
    field :consecutive_failures, :integer, default: 0

    belongs_to :dag, Cascade.Workflows.DAG,
      foreign_key: :dag_id,
      define_field: false

    timestamps()
  end

  @doc false
  def changeset(schedule, attrs) do
    schedule
    |> cast(attrs, [
      :dag_id,
      :cron_expression,
      :last_triggered_at,
      :next_run_at,
      :is_active,
      :last_job_id,
      :consecutive_failures
    ])
    |> validate_required([:dag_id, :cron_expression, :next_run_at])
    |> validate_cron_expression()
    |> foreign_key_constraint(:dag_id)
  end

  defp validate_cron_expression(changeset) do
    case get_change(changeset, :cron_expression) do
      nil ->
        changeset

      expr ->
        case Crontab.CronExpression.Parser.parse(expr) do
          {:ok, _} -> changeset
          {:error, reason} -> add_error(changeset, :cron_expression, "invalid: #{inspect(reason)}")
        end
    end
  end
end
