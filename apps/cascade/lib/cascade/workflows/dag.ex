defmodule Cascade.Workflows.DAG do
  @moduledoc """
  Schema for DAG (Directed Acyclic Graph) definitions.

  A DAG represents a workflow with tasks and their dependencies.
  The definition field contains a language-agnostic JSON structure:

  %{
    "nodes" => [
      %{"id" => "task1", "type" => "local|lambda", "config" => %{...}},
      %{"id" => "task2", "type" => "local|lambda", "config" => %{...}}
    ],
    "edges" => [
      %{"from" => "task1", "to" => "task2", "type" => "success|failure|always"}
    ],
    "metadata" => %{"timeout" => 3600, "retry_policy" => %{...}}
  }
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "dags" do
    field :name, :string
    field :description, :string
    field :schedule, :string
    field :enabled, :boolean, default: true
    field :definition, :map
    field :version, :integer, default: 1
    field :compiled_at, :utc_datetime

    has_many :jobs, Cascade.Workflows.Job

    timestamps()
  end

  @doc false
  def changeset(dag, attrs) do
    dag
    |> cast(attrs, [:name, :description, :schedule, :enabled, :definition, :version, :compiled_at])
    |> validate_required([:name, :definition])
    |> unique_constraint(:name)
    |> validate_definition()
  end

  defp validate_definition(changeset) do
    case get_change(changeset, :definition) do
      nil ->
        changeset

      definition ->
        if valid_definition?(definition) do
          changeset
        else
          add_error(changeset, :definition, "invalid DAG definition structure")
        end
    end
  end

  defp valid_definition?(%{"nodes" => nodes, "edges" => edges}) when is_list(nodes) and is_list(edges) do
    true
  end

  defp valid_definition?(_), do: false
end
