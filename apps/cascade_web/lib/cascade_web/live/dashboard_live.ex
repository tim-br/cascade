defmodule CascadeWeb.DashboardLive do
  use CascadeWeb, :live_view

  alias Cascade.Workflows
  alias Cascade.Events

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to global events
      Phoenix.PubSub.subscribe(Cascade.PubSub, Events.dag_updates_topic())
      Phoenix.PubSub.subscribe(Cascade.PubSub, Events.cluster_heartbeat_topic())

      # Refresh metrics every 5 seconds
      :timer.send_interval(5000, self(), :refresh_metrics)
    end

    socket =
      socket
      |> assign(:page_title, "Dashboard")
      |> load_dashboard_data()

    {:ok, socket}
  end

  @impl true
  def handle_info(:refresh_metrics, socket) do
    {:noreply, load_dashboard_data(socket)}
  end

  @impl true
  def handle_info({:job_event, _event}, socket) do
    {:noreply, load_dashboard_data(socket)}
  end

  @impl true
  def handle_info({:worker_event, _event}, socket) do
    worker_count = length(Supervisor.which_children(Cascade.Runtime.WorkerSupervisor))
    {:noreply, assign(socket, :worker_count, worker_count)}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  defp load_dashboard_data(socket) do
    all_jobs = Workflows.list_jobs()
    active_jobs = Workflows.list_active_jobs()
    all_dags = Workflows.list_dags()
    enabled_dags = Workflows.list_enabled_dags()

    # For single-node deployment, get worker count from supervisor
    worker_count = length(Supervisor.which_children(Cascade.Runtime.WorkerSupervisor))

    # Calculate statistics
    total_jobs = length(all_jobs)
    active_jobs_count = length(active_jobs)

    recent_jobs =
      all_jobs
      |> Enum.reject(&is_nil(&1.inserted_at))
      |> Enum.sort_by(& &1.inserted_at, {:desc, NaiveDateTime})
      |> Enum.take(10)

    job_stats = calculate_job_stats(all_jobs)

    socket
    |> assign(:total_dags, length(all_dags))
    |> assign(:enabled_dags, length(enabled_dags))
    |> assign(:total_jobs, total_jobs)
    |> assign(:active_jobs_count, active_jobs_count)
    |> assign(:active_jobs, active_jobs)
    |> assign(:recent_jobs, recent_jobs)
    |> assign(:worker_count, worker_count)
    |> assign(:job_stats, job_stats)
  end

  defp calculate_job_stats(jobs) do
    jobs
    |> Enum.group_by(& &1.status)
    |> Enum.map(fn {status, jobs_list} -> {status, length(jobs_list)} end)
    |> Map.new()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200">
      <.navbar current_page="dashboard" />

      <div class="container mx-auto p-6">
        <h1 class="text-4xl font-bold mb-6">Dashboard</h1>

        <!-- Stats Cards -->
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
          <.link navigate={~p"/dags"} class="stat bg-base-100 shadow-lg rounded-lg hover:shadow-xl transition-shadow cursor-pointer">
            <div class="stat-figure text-primary">
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" class="inline-block w-8 h-8 stroke-current">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z"></path>
              </svg>
            </div>
            <div class="stat-title">Total DAGs</div>
            <div class="stat-value text-primary"><%= @total_dags %></div>
            <div class="stat-desc"><%= @enabled_dags %> enabled</div>
          </.link>

          <div class={["stat bg-base-100 shadow-lg rounded-lg relative", if(@active_jobs_count > 0, do: "hover:shadow-xl transition-shadow cursor-pointer")]}>
            <%= if @active_jobs_count > 0 do %>
              <a href="#active-jobs" class="absolute inset-0"></a>
            <% end %>
            <div class="stat-figure text-secondary">
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" class="inline-block w-8 h-8 stroke-current">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6V4m0 2a2 2 0 100 4m0-4a2 2 0 110 4m-6 8a2 2 0 100-4m0 4a2 2 0 110-4m0 4v2m0-6V4m6 6v10m6-2a2 2 0 100-4m0 4a2 2 0 110-4m0 4v2m0-6V4"></path>
              </svg>
            </div>
            <div class="stat-title">Active Jobs</div>
            <div class="stat-value text-secondary"><%= @active_jobs_count %></div>
            <div class="stat-desc"><%= @total_jobs %> total jobs</div>
          </div>

          <div class="stat bg-base-100 shadow-lg rounded-lg">
            <div class="stat-figure text-accent">
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" class="inline-block w-8 h-8 stroke-current">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path>
              </svg>
            </div>
            <div class="stat-title">Success Rate</div>
            <div class="stat-value text-accent"><%= success_rate(@job_stats) %>%</div>
            <div class="stat-desc"><%= Map.get(@job_stats, :success, 0) %> successful</div>
          </div>

          <div class="stat bg-base-100 shadow-lg rounded-lg">
            <div class="stat-figure text-info">
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" class="inline-block w-8 h-8 stroke-current">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 12h14M5 12a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v4a2 2 0 01-2 2M5 12a2 2 0 00-2 2v4a2 2 0 002 2h14a2 2 0 002-2v-4a2 2 0 00-2-2m-2-4h.01M17 16h.01"></path>
              </svg>
            </div>
            <div class="stat-title">Workers</div>
            <div class="stat-value text-info"><%= @worker_count %></div>
            <div class="stat-desc">Online and ready</div>
          </div>
        </div>

        <!-- Active Jobs -->
        <div class="mb-8">
          <h2 class="text-2xl font-bold mb-4">Active Jobs</h2>
          <div class="bg-base-100 shadow-lg rounded-lg overflow-hidden">
            <%= if Enum.empty?(@active_jobs) do %>
              <div class="p-8 text-center text-base-content/60">
                No active jobs at the moment
              </div>
            <% else %>
              <div class="overflow-x-auto">
                <table class="table table-zebra w-full">
                  <thead>
                    <tr>
                      <th>Job ID</th>
                      <th>DAG</th>
                      <th>Status</th>
                      <th>Started</th>
                      <th>Triggered By</th>
                      <th>Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for job <- @active_jobs do %>
                      <tr>
                        <td class="font-mono text-sm">
                          <%= String.slice(job.id, 0..7) %>...
                        </td>
                        <td><%= get_dag_name(job) %></td>
                        <td>
                          <.status_badge status={job.status} />
                        </td>
                        <td><%= format_datetime(job.started_at) %></td>
                        <td><%= job.triggered_by %></td>
                        <td>
                          <.link navigate={~p"/jobs/#{job.id}"} class="btn btn-sm btn-primary">
                            View
                          </.link>
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            <% end %>
          </div>
        </div>

        <!-- Recent Jobs -->
        <div>
          <h2 class="text-2xl font-bold mb-4">Recent Jobs</h2>
          <div class="bg-base-100 shadow-lg rounded-lg overflow-hidden">
            <%= if Enum.empty?(@recent_jobs) do %>
              <div class="p-8 text-center text-base-content/60">
                No jobs yet. <.link navigate={~p"/dags"} class="link link-primary">Create your first DAG</.link>
              </div>
            <% else %>
              <div class="overflow-x-auto">
                <table class="table table-zebra w-full">
                  <thead>
                    <tr>
                      <th>Job ID</th>
                      <th>DAG</th>
                      <th>Status</th>
                      <th>Started</th>
                      <th>Duration</th>
                      <th>Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for job <- @recent_jobs do %>
                      <tr>
                        <td class="font-mono text-sm">
                          <%= String.slice(job.id, 0..7) %>...
                        </td>
                        <td><%= get_dag_name(job) %></td>
                        <td>
                          <.status_badge status={job.status} />
                        </td>
                        <td><%= format_datetime(job.started_at) %></td>
                        <td><%= format_duration(job) %></td>
                        <td>
                          <.link navigate={~p"/jobs/#{job.id}"} class="btn btn-sm btn-primary">
                            View
                          </.link>
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Helper functions
  defp status_badge(assigns) do
    color_class = case assigns.status do
      :pending -> "badge-warning"
      :running -> "badge-info"
      :success -> "badge-success"
      :failed -> "badge-error"
      :cancelled -> "badge-ghost"
      _ -> "badge-neutral"
    end

    assigns = assign(assigns, :color_class, color_class)

    ~H"""
    <span class={"badge #{@color_class}"}>
      <%= @status %>
    </span>
    """
  end

  defp get_dag_name(job) do
    case Workflows.get_dag!(job.dag_id) do
      nil -> "Unknown"
      dag -> dag.name
    end
  rescue
    _ -> "Unknown"
  end

  defp format_datetime(nil), do: "-"
  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")
  end

  defp format_duration(job) do
    cond do
      is_nil(job.started_at) -> "-"
      is_nil(job.completed_at) -> "Running..."
      true ->
        diff = NaiveDateTime.diff(job.completed_at, job.started_at, :second)
        "#{diff}s"
    end
  end

  defp success_rate(stats) do
    total = Enum.reduce(stats, 0, fn {_status, count}, acc -> acc + count end)

    if total == 0 do
      0
    else
      success = Map.get(stats, :success, 0)
      round(success / total * 100)
    end
  end
end
