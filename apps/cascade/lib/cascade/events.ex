defmodule Cascade.Events do
  @moduledoc """
  Event structures and PubSub helpers for Cascade.

  Defines standardized events for job and task state changes, and provides
  helper functions for publishing events via Phoenix.PubSub.
  """

  @doc """
  Event emitted when a job's status changes.
  """
  defmodule JobEvent do
    @type t :: %__MODULE__{
            job_id: binary(),
            dag_id: binary(),
            status: atom(),
            timestamp: DateTime.t(),
            metadata: map()
          }

    defstruct [:job_id, :dag_id, :status, :timestamp, :metadata]
  end

  @doc """
  Event emitted when a task's status changes.
  """
  defmodule TaskEvent do
    @type t :: %__MODULE__{
            job_id: binary(),
            task_id: String.t(),
            status: atom(),
            worker_node: String.t() | nil,
            timestamp: DateTime.t(),
            result: map() | nil,
            error: String.t() | nil
          }

    defstruct [:job_id, :task_id, :status, :worker_node, :timestamp, :result, :error]
  end

  @doc """
  Event emitted for worker heartbeats and status updates.
  """
  defmodule WorkerEvent do
    @type t :: %__MODULE__{
            node: atom(),
            status: atom(),
            capacity: integer(),
            active_tasks: integer(),
            timestamp: DateTime.t()
          }

    defstruct [:node, :status, :capacity, :active_tasks, :timestamp]
  end

  ## PubSub Topics

  @doc "Topic for global DAG updates"
  def dag_updates_topic, do: "dag_updates"

  @doc "Topic for cluster-wide heartbeats"
  def cluster_heartbeat_topic, do: "cluster:heartbeat"

  @doc "Topic for scheduler trigger requests"
  def scheduler_triggers_topic, do: "scheduler:triggers"

  @doc "Topic for job-specific events"
  def job_topic(job_id), do: "jobs:#{job_id}"

  @doc "Topic for job task events"
  def job_tasks_topic(job_id), do: "jobs:#{job_id}:tasks"

  @doc "Topic for DAG-specific events"
  def dag_topic(dag_id), do: "dag:#{dag_id}"

  @doc "Topic for worker-specific task assignments"
  def worker_topic(node), do: "worker:#{node}"

  @doc "Topic for broadcasting to all workers"
  def workers_broadcast_topic, do: "workers:broadcast"

  ## Event Publishers

  @doc """
  Publishes a job event to the appropriate PubSub topics.
  """
  def publish_job_event(%JobEvent{} = event) do
    Phoenix.PubSub.broadcast(
      Cascade.PubSub,
      job_topic(event.job_id),
      {:job_event, event}
    )

    Phoenix.PubSub.broadcast(
      Cascade.PubSub,
      dag_topic(event.dag_id),
      {:job_event, event}
    )
  end

  @doc """
  Publishes a task event to the appropriate PubSub topics.
  """
  def publish_task_event(%TaskEvent{} = event) do
    Phoenix.PubSub.broadcast(
      Cascade.PubSub,
      job_tasks_topic(event.job_id),
      {:task_event, event}
    )

    Phoenix.PubSub.broadcast(
      Cascade.PubSub,
      job_topic(event.job_id),
      {:task_event, event}
    )
  end

  @doc """
  Publishes a worker event to the cluster heartbeat topic.
  """
  def publish_worker_event(%WorkerEvent{} = event) do
    Phoenix.PubSub.broadcast(
      Cascade.PubSub,
      cluster_heartbeat_topic(),
      {:worker_event, event}
    )
  end

  @doc """
  Broadcasts a message to a specific worker node.
  """
  def send_to_worker(node, message) do
    IO.puts("sending to worker")
    IO.puts("#{inspect(message)}")

    Phoenix.PubSub.broadcast(
      Cascade.PubSub,
      worker_topic(node),
      message
    )
  end

  @doc """
  Broadcasts a message to all workers.
  """
  def broadcast_to_workers(message) do
    Phoenix.PubSub.broadcast(
      Cascade.PubSub,
      workers_broadcast_topic(),
      message
    )
  end
end
