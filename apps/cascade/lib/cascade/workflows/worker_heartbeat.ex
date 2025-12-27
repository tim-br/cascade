defmodule Cascade.Workflows.WorkerHeartbeat do
  @moduledoc """
  Schema for Worker Heartbeat records.

  Tracks the health and capacity of worker nodes.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:node, :string, autogenerate: false}

  schema "worker_heartbeats" do
    field :last_seen, :utc_datetime
    field :capacity, :integer, default: 1
    field :active_tasks, :integer, default: 0

    timestamps()
  end

  @doc false
  def changeset(worker_heartbeat, attrs) do
    worker_heartbeat
    |> cast(attrs, [:node, :last_seen, :capacity, :active_tasks])
    |> validate_required([:node, :last_seen])
    |> validate_number(:capacity, greater_than: 0)
    |> validate_number(:active_tasks, greater_than_or_equal_to: 0)
  end
end
