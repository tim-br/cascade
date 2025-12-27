defmodule CascadeWeb.WorkerListLive do
  use CascadeWeb, :live_view

  alias Cascade.Runtime.StateManager
  alias Cascade.Events

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Cascade.PubSub, Events.cluster_heartbeat_topic())
      :timer.send_interval(5000, self(), :refresh)
    end

    socket =
      socket
      |> assign(:page_title, "Workers")
      |> load_workers()

    {:ok, socket}
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, load_workers(socket)}
  end

  @impl true
  def handle_info({:worker_event, _event}, socket) do
    {:noreply, load_workers(socket)}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  defp load_workers(socket) do
    # For single-node deployment, get workers from supervisor
    worker_processes = Supervisor.which_children(Cascade.Runtime.WorkerSupervisor)
    worker_count = length(worker_processes)

    # Build simple worker stats for display
    worker_stats =
      Enum.map(1..worker_count, fn id ->
        %{
          node: node(),
          worker_id: id,
          status: :online
        }
      end)

    total_capacity = worker_count
    total_active = 0  # Would need to query running tasks
    online_workers = worker_count

    socket
    |> assign(:workers, worker_stats)
    |> assign(:total_capacity, total_capacity)
    |> assign(:total_active, total_active)
    |> assign(:online_workers, online_workers)
  end

  defp worker_status(last_seen) do
    diff = DateTime.diff(DateTime.utc_now(), last_seen, :second)

    cond do
      diff < 15 -> :online
      diff < 60 -> :warning
      true -> :offline
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200">
      <.navbar current_page="workers" />

      <div class="container mx-auto p-6">
        <h1 class="text-4xl font-bold mb-6">Worker Cluster</h1>

        <!-- Cluster Stats -->
        <div class="grid grid-cols-1 md:grid-cols-3 gap-4 mb-8">
          <div class="stat bg-base-100 shadow-lg rounded-lg">
            <div class="stat-figure text-success">
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" class="inline-block w-8 h-8 stroke-current">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 12h14M5 12a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v4a2 2 0 01-2 2M5 12a2 2 0 00-2 2v4a2 2 0 002 2h14a2 2 0 002-2v-4a2 2 0 00-2-2m-2-4h.01M17 16h.01"></path>
              </svg>
            </div>
            <div class="stat-title">Online Workers</div>
            <div class="stat-value text-success"><%= @online_workers %></div>
            <div class="stat-desc"><%= length(@workers) %> total</div>
          </div>

          <div class="stat bg-base-100 shadow-lg rounded-lg">
            <div class="stat-figure text-primary">
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" class="inline-block w-8 h-8 stroke-current">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z"></path>
              </svg>
            </div>
            <div class="stat-title">Total Capacity</div>
            <div class="stat-value text-primary"><%= @total_capacity %></div>
            <div class="stat-desc">Task slots</div>
          </div>

          <div class="stat bg-base-100 shadow-lg rounded-lg">
            <div class="stat-figure text-info">
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" class="inline-block w-8 h-8 stroke-current">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path>
              </svg>
            </div>
            <div class="stat-title">Active Tasks</div>
            <div class="stat-value text-info"><%= @total_active %></div>
            <div class="stat-desc">
              <%= if @total_capacity > 0 do %>
                <%= round(@total_active / @total_capacity * 100) %>% utilization
              <% else %>
                0% utilization
              <% end %>
            </div>
          </div>
        </div>

        <!-- Workers Table -->
        <div class="bg-base-100 shadow-lg rounded-lg overflow-hidden">
          <div class="p-6">
            <h2 class="text-2xl font-bold">Worker Nodes</h2>
          </div>

          <%= if Enum.empty?(@workers) do %>
            <div class="p-8 text-center text-base-content/60">
              No workers detected. Workers will appear here when they register with the cluster.
            </div>
          <% else %>
            <div class="overflow-x-auto">
              <table class="table table-zebra w-full">
                <thead>
                  <tr>
                    <th>Node</th>
                    <th>Status</th>
                    <th>Capacity</th>
                    <th>Active Tasks</th>
                    <th>Utilization</th>
                    <th>Last Seen</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for worker <- @workers do %>
                    <tr>
                      <td class="font-mono text-sm"><%= worker.node %></td>
                      <td>
                        <.worker_status_badge status={worker.status} />
                      </td>
                      <td><%= worker.capacity %></td>
                      <td><%= worker.active_tasks %></td>
                      <td>
                        <div class="flex items-center gap-2">
                          <progress
                            class={"progress w-20 #{utilization_color(worker)}"}
                            value={worker.active_tasks}
                            max={worker.capacity}
                          >
                          </progress>
                          <span class="text-sm">
                            <%= if worker.capacity > 0 do %>
                              <%= round(worker.active_tasks / worker.capacity * 100) %>%
                            <% else %>
                              0%
                            <% end %>
                          </span>
                        </div>
                      </td>
                      <td class="text-sm"><%= time_ago(worker.last_seen) %></td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% end %>
        </div>

        <!-- Cluster Information -->
        <div class="mt-6 bg-base-100 shadow-lg rounded-lg p-6">
          <h2 class="text-xl font-bold mb-4">Cluster Information</h2>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4 text-sm">
            <div>
              <div class="font-semibold text-base-content/60">Current Node</div>
              <div class="font-mono"><%= node() %></div>
            </div>
            <div>
              <div class="font-semibold text-base-content/60">Connected Nodes</div>
              <div>
                <%= if length(Node.list()) > 0 do %>
                  <%= Enum.join(Node.list(), ", ") %>
                <% else %>
                  No other nodes connected
                <% end %>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Helper functions
  defp worker_status_badge(assigns) do
    {color, text} = case assigns.status do
      :online -> {"badge-success", "Online"}
      :warning -> {"badge-warning", "Warning"}
      :offline -> {"badge-error", "Offline"}
      _ -> {"badge-ghost", "Unknown"}
    end

    assigns = assign(assigns, :color, color) |> assign(:text, text)

    ~H"""
    <span class={"badge #{@color}"}>
      <%= @text %>
    </span>
    """
  end

  defp utilization_color(worker) do
    utilization = if worker.capacity > 0 do
      worker.active_tasks / worker.capacity
    else
      0
    end

    cond do
      utilization < 0.5 -> "progress-success"
      utilization < 0.8 -> "progress-warning"
      true -> "progress-error"
    end
  end

  defp time_ago(nil), do: "never"
  defp time_ago(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 5 -> "just now"
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86400)}d ago"
    end
  end
end
