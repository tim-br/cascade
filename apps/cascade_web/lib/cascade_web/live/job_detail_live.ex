defmodule CascadeWeb.JobDetailLive do
  use CascadeWeb, :live_view

  alias Cascade.Workflows
  alias Cascade.Runtime.StateManager
  alias Cascade.Events

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    job = Workflows.get_job_with_details!(id)

    if connected?(socket) do
      # Subscribe to real-time job and task events
      Phoenix.PubSub.subscribe(Cascade.PubSub, Events.job_topic(id))
      Phoenix.PubSub.subscribe(Cascade.PubSub, Events.job_tasks_topic(id))

      # Refresh every 2 seconds if job is still active
      if job.status in [:pending, :running] do
        :timer.send_interval(2000, self(), :refresh)
      end
    end

    socket =
      socket
      |> assign(:page_title, "Job Details")
      |> assign(:job, job)
      |> assign(:dag, job.dag)
      |> load_execution_details(id)

    {:ok, socket}
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, load_execution_details(socket, socket.assigns.job.id)}
  end

  @impl true
  def handle_info({:task_event, event}, socket) do
    # Real-time task status update
    socket =
      socket
      |> load_execution_details(socket.assigns.job.id)
      |> put_flash(:info, "Task #{event.task_id} status: #{event.status}")

    {:noreply, socket}
  end

  @impl true
  def handle_info({:job_event, _event}, socket) do
    {:noreply, load_execution_details(socket, socket.assigns.job.id)}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  defp load_execution_details(socket, job_id) do
    job = Workflows.get_job_with_details!(job_id)
    task_executions = Workflows.list_task_executions_for_job(job_id)

    # Try to get in-memory state for active jobs
    job_state = case StateManager.get_job_state(job_id) do
      {:ok, state} -> state
      {:error, _} -> nil
    end

    socket
    |> assign(:job, job)
    |> assign(:task_executions, task_executions)
    |> assign(:job_state, job_state)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200">
      <.navbar current_page="dashboard" />

      <div class="container mx-auto p-6">
        <div class="mb-4">
          <.link navigate={~p"/dags/#{@dag.id}"} class="btn btn-ghost btn-sm">
            ← Back to <%= @dag.name %>
          </.link>
        </div>

        <!-- Job Header -->
        <div class="bg-base-100 shadow-lg rounded-lg p-6 mb-6">
          <div class="flex justify-between items-start mb-4">
            <div>
              <h1 class="text-3xl font-bold mb-2">Job Details</h1>
              <p class="text-base-content/70 font-mono text-sm"><%= @job.id %></p>
            </div>
            <div>
              <.status_badge status={@job.status} large={true} />
            </div>
          </div>

          <div class="grid grid-cols-1 md:grid-cols-4 gap-4">
            <div>
              <div class="text-sm font-semibold text-base-content/60">DAG</div>
              <div class="text-lg"><%= @dag.name %></div>
            </div>
            <div>
              <div class="text-sm font-semibold text-base-content/60">Started</div>
              <div class="text-sm"><%= format_datetime(@job.started_at) %></div>
            </div>
            <div>
              <div class="text-sm font-semibold text-base-content/60">Duration</div>
              <div class="text-lg"><%= format_duration(@job) %></div>
            </div>
            <div>
              <div class="text-sm font-semibold text-base-content/60">Triggered By</div>
              <div class="text-lg"><%= @job.triggered_by %></div>
            </div>
          </div>

          <%= if @job.error do %>
            <div class="alert alert-error mt-4">
              <svg xmlns="http://www.w3.org/2000/svg" class="stroke-current shrink-0 h-6 w-6" fill="none" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z" /></svg>
              <span><%= @job.error %></span>
            </div>
          <% end %>
        </div>

        <!-- Real-time Status (for active jobs) -->
        <%= if @job_state do %>
          <div class="bg-base-100 shadow-lg rounded-lg p-6 mb-6">
            <h2 class="text-2xl font-bold mb-4">Real-time Status</h2>
            <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
              <div class="stat bg-base-200 rounded-lg">
                <div class="stat-title">Pending</div>
                <div class="stat-value text-warning"><%= MapSet.size(@job_state.pending_tasks) %></div>
              </div>
              <div class="stat bg-base-200 rounded-lg">
                <div class="stat-title">Running</div>
                <div class="stat-value text-info"><%= map_size(@job_state.running_tasks) %></div>
              </div>
              <div class="stat bg-base-200 rounded-lg">
                <div class="stat-title">Completed</div>
                <div class="stat-value text-success"><%= MapSet.size(@job_state.completed_tasks) %></div>
              </div>
              <div class="stat bg-base-200 rounded-lg">
                <div class="stat-title">Failed</div>
                <div class="stat-value text-error"><%= MapSet.size(@job_state.failed_tasks) %></div>
              </div>
            </div>
          </div>
        <% end %>

        <!-- Task Executions -->
        <div class="bg-base-100 shadow-lg rounded-lg overflow-hidden">
          <div class="p-6">
            <h2 class="text-2xl font-bold">Task Executions</h2>
          </div>

          <%= if Enum.empty?(@task_executions) do %>
            <div class="p-8 text-center text-base-content/60">
              No task executions found
            </div>
          <% else %>
            <div class="overflow-x-auto">
              <table class="table table-zebra w-full">
                <thead>
                  <tr>
                    <th>Task ID</th>
                    <th>Status</th>
                    <th>Type</th>
                    <th>Worker</th>
                    <th>Started</th>
                    <th>Duration</th>
                    <th>Retries</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for te <- @task_executions do %>
                    <tr class={row_class(te.status)}>
                      <td class="font-bold"><%= te.task_id %></td>
                      <td>
                        <.status_badge status={te.status} />
                      </td>
                      <td>
                        <span class={"badge badge-sm #{type_color(te.execution_type)}"}>
                          <%= te.execution_type %>
                        </span>
                      </td>
                      <td class="font-mono text-xs">
                        <%= te.worker_node || "-" %>
                      </td>
                      <td class="text-sm"><%= format_datetime(te.started_at) %></td>
                      <td><%= format_task_duration(te) %></td>
                      <td>
                        <%= if te.retry_count > 0 do %>
                          <span class="badge badge-warning badge-sm"><%= te.retry_count %></span>
                        <% else %>
                          -
                        <% end %>
                      </td>
                    </tr>
                    <%= if te.error do %>
                      <tr class="bg-error/10">
                        <td colspan="7" class="text-sm">
                          <strong>Error:</strong> <%= te.error %>
                        </td>
                      </tr>
                    <% end %>
                    <%= if te.result do %>
                      <tr class="bg-success/5">
                        <td colspan="7">
                          <details class="collapse collapse-arrow">
                            <summary class="collapse-title text-sm font-semibold">
                              View Result
                            </summary>
                            <div class="collapse-content">
                              <pre class="bg-base-200 p-4 rounded text-xs overflow-x-auto"><%= Jason.encode!(te.result, pretty: true) %></pre>
                            </div>
                          </details>
                        </td>
                      </tr>
                    <% end %>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Helper functions
  defp status_badge(%{status: status, large: true} = assigns) do
    color_class = case status do
      :pending -> "badge-warning"
      :queued -> "badge-warning"
      :running -> "badge-info"
      :success -> "badge-success"
      :failed -> "badge-error"
      :skipped -> "badge-ghost"
      :cancelled -> "badge-ghost"
      _ -> "badge-neutral"
    end

    assigns = assign(assigns, :color_class, color_class)

    ~H"""
    <span class={"badge badge-lg #{@color_class}"}>
      <%= @status %>
    </span>
    """
  end

  defp status_badge(assigns) do
    color_class = case assigns.status do
      :pending -> "badge-warning"
      :queued -> "badge-warning"
      :running -> "badge-info"
      :success -> "badge-success"
      :failed -> "badge-error"
      :skipped -> "badge-ghost"
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

  defp row_class(status) do
    case status do
      :running -> "bg-info/10"
      :success -> ""
      :failed -> "bg-error/5"
      _ -> ""
    end
  end

  defp format_datetime(nil), do: "-"
  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%H:%M:%S")
  end

  defp format_duration(job) do
    cond do
      is_nil(job.started_at) -> "-"
      is_nil(job.completed_at) -> "Running..."
      true ->
        diff = NaiveDateTime.diff(job.completed_at, job.started_at, :second)
        format_seconds(diff)
    end
  end

  defp format_task_duration(task) do
    cond do
      is_nil(task.started_at) -> "-"
      is_nil(task.completed_at) -> "Running..."
      true ->
        diff = NaiveDateTime.diff(task.completed_at, task.started_at, :second)
        format_seconds(diff)
    end
  end

  defp format_seconds(seconds) when seconds < 60, do: "#{seconds}s"
  defp format_seconds(seconds) do
    minutes = div(seconds, 60)
    remaining_seconds = rem(seconds, 60)
    "#{minutes}m #{remaining_seconds}s"
  end

  defp type_color("local"), do: "badge-primary"
  defp type_color("lambda"), do: "badge-secondary"
  defp type_color(_), do: "badge-ghost"
end
