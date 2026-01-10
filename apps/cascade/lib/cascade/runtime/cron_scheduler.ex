defmodule Cascade.Runtime.CronScheduler do
  @moduledoc """
  Manages cron-based DAG scheduling.

  Responsibilities:
  - Initialize schedules from database on startup
  - Poll for due schedules every minute
  - Trigger jobs via Scheduler.trigger_job/3
  - React to DAG updates (schedule changes) via PubSub
  - Track execution state for restart resilience
  """

  use GenServer
  require Logger

  alias Cascade.Runtime.{Scheduler, CronParser}
  alias Cascade.Workflows
  alias Cascade.Events

  @poll_interval :timer.minutes(1)
  @startup_delay :timer.seconds(5)

  defmodule State do
    @moduledoc false
    defstruct [
      :timer_ref,
      :poll_interval,
      enabled: true,
      last_poll_at: nil
    ]
  end

  ## Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Manually trigger schedule check (for testing)"
  def check_schedules_now do
    GenServer.call(__MODULE__, :check_now)
  end

  @doc "Get scheduler status"
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  @doc "Force refresh of a specific DAG's schedule"
  def refresh_dag_schedule(dag_id) do
    GenServer.cast(__MODULE__, {:refresh_dag, dag_id})
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    enabled = Keyword.get(opts, :enabled, cron_enabled?())
    poll_interval = Keyword.get(opts, :poll_interval, @poll_interval)

    if enabled do
      # Subscribe to DAG update events
      Phoenix.PubSub.subscribe(Cascade.PubSub, Events.dag_updates_topic())

      Logger.info("[CRON_SCHEDULER] Starting (poll_interval=#{poll_interval}ms)")

      # Delay initial check to allow system to stabilize
      Process.send_after(self(), :initialize_schedules, @startup_delay)

      {:ok, %State{poll_interval: poll_interval, enabled: true}}
    else
      Logger.info("[CRON_SCHEDULER] Disabled")
      {:ok, %State{enabled: false}}
    end
  end

  @impl true
  def handle_info(:initialize_schedules, state) do
    Logger.info("[CRON_SCHEDULER] Initializing schedules from database...")

    # Sync schedules from DAGs to dag_schedules table
    sync_all_schedules()

    # Start polling
    timer_ref = schedule_next_poll(state.poll_interval)

    {:noreply, %{state | timer_ref: timer_ref}}
  end

  @impl true
  def handle_info(:poll, %State{enabled: false} = state) do
    {:noreply, state}
  end

  def handle_info(:poll, state) do
    now = DateTime.utc_now()

    # Find and trigger due schedules
    due_schedules = Workflows.list_due_schedules(now)

    if length(due_schedules) > 0 do
      Logger.info("[CRON_SCHEDULER] Polling: found #{length(due_schedules)} due schedules")
    end

    Enum.each(due_schedules, fn schedule ->
      trigger_scheduled_job(schedule, now)
    end)

    # Schedule next poll
    timer_ref = schedule_next_poll(state.poll_interval)

    {:noreply, %{state | timer_ref: timer_ref, last_poll_at: now}}
  end

  @impl true
  def handle_info({:dag_event, %{action: action, dag_name: dag_name}}, state)
      when action in [:created, :updated] do
    Logger.info("[CRON_SCHEDULER] DAG #{action}: #{dag_name}, refreshing schedule")

    case Workflows.get_dag_by_name(dag_name) do
      nil -> :ok
      dag -> sync_dag_schedule(dag)
    end

    {:noreply, state}
  end

  def handle_info({:dag_event, %{action: :deleted, dag_name: dag_name}}, state) do
    Logger.info("[CRON_SCHEDULER] DAG deleted: #{dag_name}")
    # Schedule will be deleted via ON DELETE CASCADE
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def handle_call(:check_now, _from, state) do
    send(self(), :poll)
    {:reply, :ok, state}
  end

  def handle_call(:get_status, _from, state) do
    status = %{
      enabled: state.enabled,
      poll_interval: state.poll_interval,
      last_poll_at: state.last_poll_at,
      active_schedules: Workflows.count_active_schedules()
    }

    {:reply, status, state}
  end

  @impl true
  def handle_cast({:refresh_dag, dag_id}, state) do
    case Workflows.get_dag!(dag_id) do
      nil -> :ok
      dag -> sync_dag_schedule(dag)
    end

    {:noreply, state}
  rescue
    Ecto.NoResultsError -> {:noreply, state}
  end

  ## Private Functions

  defp cron_enabled? do
    case System.get_env("CRON_SCHEDULER_ENABLED") do
      "false" -> false
      "0" -> false
      _ -> true
    end
  end

  defp schedule_next_poll(interval) do
    Process.send_after(self(), :poll, interval)
  end

  defp sync_all_schedules do
    Workflows.list_dags()
    |> Enum.each(&sync_dag_schedule/1)
  end

  defp sync_dag_schedule(dag) do
    cond do
      # No schedule defined
      is_nil(dag.schedule) or dag.schedule == "" ->
        Workflows.delete_dag_schedule(dag.id)

      # DAG is disabled
      not dag.enabled ->
        Workflows.deactivate_dag_schedule(dag.id)

      # Valid schedule
      true ->
        case CronParser.parse(dag.schedule) do
          {:ok, cron_expr} ->
            now = DateTime.utc_now()

            case CronParser.next_run(cron_expr, now) do
              {:ok, next_run} ->
                Workflows.upsert_dag_schedule(%{
                  dag_id: dag.id,
                  cron_expression: dag.schedule,
                  next_run_at: next_run,
                  is_active: true
                })

              {:error, _} ->
                Logger.warning("[CRON_SCHEDULER] Could not calculate next run for #{dag.name}")
                Workflows.deactivate_dag_schedule(dag.id)
            end

          {:error, reason} ->
            Logger.warning("[CRON_SCHEDULER] Invalid cron for DAG #{dag.name}: #{inspect(reason)}")
            Workflows.deactivate_dag_schedule(dag.id)
        end
    end
  end

  defp trigger_scheduled_job(schedule, now) do
    dag_id = schedule.dag_id

    # Verify DAG is still enabled
    case Workflows.get_dag!(dag_id) do
      nil ->
        Logger.warning("[CRON_SCHEDULER] DAG not found: #{dag_id}")
        Workflows.delete_dag_schedule(dag_id)

      dag ->
        if dag.enabled do
          Logger.info("[CRON_SCHEDULER] Triggering DAG: #{dag.name}")

          case Scheduler.trigger_job(dag_id, "cron_scheduler", %{
                 "scheduled_at" => DateTime.to_iso8601(schedule.next_run_at),
                 "cron_expression" => schedule.cron_expression
               }) do
            {:ok, job} ->
              # Calculate next run time
              {:ok, cron_expr} = CronParser.parse(schedule.cron_expression)
              {:ok, next_run} = CronParser.next_run(cron_expr, now)

              Workflows.update_dag_schedule(schedule, %{
                last_triggered_at: now,
                next_run_at: next_run,
                last_job_id: job.id,
                consecutive_failures: 0
              })

            {:error, reason} ->
              Logger.error("[CRON_SCHEDULER] Failed to trigger #{dag.name}: #{inspect(reason)}")

              # Update failure count and calculate next run anyway
              {:ok, cron_expr} = CronParser.parse(schedule.cron_expression)
              {:ok, next_run} = CronParser.next_run(cron_expr, now)

              Workflows.update_dag_schedule(schedule, %{
                next_run_at: next_run,
                consecutive_failures: schedule.consecutive_failures + 1
              })
          end
        else
          Logger.debug("[CRON_SCHEDULER] Skipping disabled DAG: #{dag.name}")
          Workflows.deactivate_dag_schedule(dag_id)
        end
    end
  rescue
    e ->
      Logger.error("[CRON_SCHEDULER] Error triggering schedule: #{inspect(e)}")
  end
end
