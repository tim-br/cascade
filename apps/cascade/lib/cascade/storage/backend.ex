defmodule Cascade.Storage.Backend do
  @moduledoc """
  Behaviour for pluggable storage backends.

  Defines the interface that all storage backends must implement.
  This allows Cascade to support multiple database backends:
  - SQLite (zero-config, local development)
  - Postgres (production, self-hosted)
  - DynamoDB (cloud-native, AWS)
  """

  alias Cascade.Workflows.{DAG, DagSchedule, Job, TaskExecution, WorkerHeartbeat}

  ## DAG functions

  @callback list_dags() :: [DAG.t()]
  @callback list_enabled_dags() :: [DAG.t()]
  @callback get_dag!(binary()) :: DAG.t()
  @callback get_dag_by_name(String.t()) :: DAG.t() | nil
  @callback create_dag(map()) :: {:ok, DAG.t()} | {:error, Ecto.Changeset.t()}
  @callback update_dag(DAG.t(), map()) :: {:ok, DAG.t()} | {:error, Ecto.Changeset.t()}
  @callback delete_dag(DAG.t()) :: {:ok, DAG.t()} | {:error, Ecto.Changeset.t()}

  ## Job functions

  @callback list_jobs() :: [Job.t()]
  @callback list_jobs_for_dag(binary()) :: [Job.t()]
  @callback list_active_jobs() :: [Job.t()]
  @callback get_job!(binary()) :: Job.t()
  @callback get_job_with_details!(binary()) :: Job.t()
  @callback create_job(map()) :: {:ok, Job.t()} | {:error, Ecto.Changeset.t()}
  @callback update_job(Job.t(), map()) :: {:ok, Job.t()} | {:error, Ecto.Changeset.t()}
  @callback delete_job(Job.t()) :: {:ok, Job.t()} | {:error, Ecto.Changeset.t()}

  ## TaskExecution functions

  @callback list_task_executions() :: [TaskExecution.t()]
  @callback list_task_executions_for_job(binary()) :: [TaskExecution.t()]
  @callback get_task_execution!(binary()) :: TaskExecution.t()
  @callback create_task_execution(map()) ::
              {:ok, TaskExecution.t()} | {:error, Ecto.Changeset.t()}
  @callback update_task_execution(TaskExecution.t(), map()) ::
              {:ok, TaskExecution.t()} | {:error, Ecto.Changeset.t()}
  @callback delete_task_execution(TaskExecution.t()) ::
              {:ok, TaskExecution.t()} | {:error, Ecto.Changeset.t()}
  @callback claim_task(binary(), String.t(), String.t()) :: {:ok, :claimed} | {:error, atom()}
  @callback get_job_state(binary()) :: {:ok, map()}

  ## WorkerHeartbeat functions

  @callback upsert_worker_heartbeat(String.t(), integer(), integer()) ::
              {:ok, WorkerHeartbeat.t()} | {:error, Ecto.Changeset.t()}
  @callback get_active_workers() :: [WorkerHeartbeat.t()]
  @callback get_worker_heartbeat(String.t()) :: WorkerHeartbeat.t() | nil

  ## DagSchedule functions

  @callback list_due_schedules(DateTime.t()) :: [DagSchedule.t()]
  @callback get_dag_schedule(binary()) :: DagSchedule.t() | nil
  @callback upsert_dag_schedule(map()) :: {:ok, DagSchedule.t()} | {:error, Ecto.Changeset.t()}
  @callback update_dag_schedule(DagSchedule.t(), map()) ::
              {:ok, DagSchedule.t()} | {:error, Ecto.Changeset.t()}
  @callback deactivate_dag_schedule(binary()) :: :ok
  @callback delete_dag_schedule(binary()) :: :ok
  @callback count_active_schedules() :: integer()
end
