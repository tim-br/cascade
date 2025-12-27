defmodule CascadeWeb.DAGDetailLive do
  use CascadeWeb, :live_view

  alias Cascade.Workflows
  alias Cascade.Runtime.Scheduler
  alias Cascade.Events

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    dag = Workflows.get_dag!(id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Cascade.PubSub, Events.dag_topic(id))
    end

    socket =
      socket
      |> assign(:page_title, dag.name)
      |> assign(:dag, dag)
      |> assign(:context_json, default_context_json(dag.name))
      |> load_jobs()

    {:ok, socket}
  end

  @impl true
  def handle_event("trigger_job", %{"context" => context_json}, socket) do
    context =
      case Jason.decode(context_json) do
        {:ok, ctx} -> ctx
        {:error, _} -> %{}
      end

    case Scheduler.trigger_job(socket.assigns.dag.id, "manual", context) do
      {:ok, job} ->
        socket =
          socket
          |> put_flash(:info, "Job #{String.slice(job.id, 0..7)} triggered successfully!")
          |> load_jobs()

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to trigger job: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("update_context", %{"context" => value}, socket) do
    {:noreply, assign(socket, :context_json, value)}
  end

  @impl true
  def handle_info({:job_event, _event}, socket) do
    {:noreply, load_jobs(socket)}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  defp load_jobs(socket) do
    jobs =
      socket.assigns.dag.id
      |> Workflows.list_jobs_for_dag()
      |> Enum.take(20)

    assign(socket, :recent_jobs, jobs)
  end

  defp default_context_json(dag_name) do
    case dag_name do
      "cloud_test_pipeline" ->
        Jason.encode!(%{
          "input_data" => [10, 20, 30, 40, 50],
          "multiplier" => 3
        }, pretty: true)

      "literary_analysis_pipeline" ->
        Jason.encode!(%{
          "book1_id" => "1342",
          "book2_id" => "11",
          "analysis_depth" => "basic"
        }, pretty: true)

      _ ->
        "{}"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200">
      <.navbar current_page="dags" />

      <div class="container mx-auto p-6">
        <div class="mb-4">
          <.link navigate={~p"/dags"} class="btn btn-ghost btn-sm">
            ← Back to DAGs
          </.link>
        </div>

        <!-- DAG Header -->
        <div class="bg-base-100 shadow-lg rounded-lg p-6 mb-6">
          <div class="flex justify-between items-start mb-4">
            <div>
              <h1 class="text-4xl font-bold mb-2"><%= @dag.name %></h1>
              <p class="text-base-content/70"><%= @dag.description %></p>
            </div>
            <div class={["badge badge-lg", if(@dag.enabled, do: "badge-success", else: "badge-ghost")]}>
              <%= if @dag.enabled, do: "Enabled", else: "Disabled" %>
            </div>
          </div>

          <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
            <div>
              <div class="text-sm font-semibold text-base-content/60">Schedule</div>
              <div>
                <%= if @dag.schedule do %>
                  <code class="text-sm bg-base-200 px-2 py-1 rounded"><%= @dag.schedule %></code>
                <% else %>
                  <span class="text-base-content/60">Manual only</span>
                <% end %>
              </div>
            </div>
            <div>
              <div class="text-sm font-semibold text-base-content/60">Tasks</div>
              <div class="text-lg"><%= length(@dag.definition["nodes"]) %> tasks</div>
            </div>
            <div>
              <div class="text-sm font-semibold text-base-content/60">Version</div>
              <div class="text-lg">v<%= @dag.version %></div>
            </div>
          </div>
        </div>

        <!-- Trigger Form -->
        <div class="bg-base-100 shadow-lg rounded-lg p-6 mb-6">
          <h2 class="text-2xl font-bold mb-4">🚀 Trigger New Job</h2>
          <form phx-submit="trigger_job">
            <div class="form-control mb-4">
              <label class="label">
                <span class="label-text">Context (JSON)</span>
                <span class="label-text-alt">Optional job parameters</span>
              </label>
              <textarea
                name="context"
                class="textarea textarea-bordered h-24 font-mono text-sm"
                placeholder='{"key": "value"}'
                phx-change="update_context"
              ><%= @context_json %></textarea>
              <label class="label">
                <span class="label-text-alt">💡 Tip: Pre-filled with example values - click "Trigger Job" to test!</span>
              </label>
            </div>
            <button type="submit" class="btn btn-primary">
              Trigger Job
            </button>
          </form>
        </div>

        <!-- DAG Graph -->
        <div class="bg-base-100 shadow-lg rounded-lg p-6 mb-6">
          <h2 class="text-2xl font-bold mb-4">DAG Structure</h2>
          <div class="bg-base-200 rounded-lg p-6">
            <div class="flex flex-wrap gap-4">
              <%= for node <- @dag.definition["nodes"] do %>
                <div class="card bg-base-100 shadow-md w-48">
                  <div class="card-body p-4">
                    <h3 class="font-bold text-sm"><%= node["id"] %></h3>
                    <div class={["badge badge-sm", type_color(node["type"])]}>
                      <%= node["type"] %>
                    </div>
                    <% deps = get_dependencies(@dag.definition, node["id"]) %>
                    <%= if !Enum.empty?(deps) do %>
                      <div class="text-xs text-base-content/60 mt-2">
                        Depends on: <%= Enum.join(deps, ", ") %>
                      </div>
                    <% end %>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </div>

        <!-- Recent Jobs -->
        <div class="bg-base-100 shadow-lg rounded-lg overflow-hidden">
          <div class="p-6">
            <h2 class="text-2xl font-bold">Recent Jobs</h2>
          </div>
          <%= if Enum.empty?(@recent_jobs) do %>
            <div class="p-8 text-center text-base-content/60">
              No jobs have been run yet. Trigger one above!
            </div>
          <% else %>
            <div class="overflow-x-auto">
              <table class="table table-zebra w-full">
                <thead>
                  <tr>
                    <th>Job ID</th>
                    <th>Status</th>
                    <th>Started</th>
                    <th>Duration</th>
                    <th>Triggered By</th>
                    <th>Actions</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for job <- @recent_jobs do %>
                    <tr>
                      <td class="font-mono text-sm">
                        <%= String.slice(job.id, 0..7) %>...
                      </td>
                      <td>
                        <.status_badge status={job.status} />
                      </td>
                      <td><%= format_datetime(job.started_at) %></td>
                      <td><%= format_duration(job) %></td>
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

  defp type_color("local"), do: "badge-primary"
  defp type_color("lambda"), do: "badge-secondary"
  defp type_color(_), do: "badge-ghost"

  defp get_dependencies(definition, task_id) do
    definition["edges"]
    |> Enum.filter(&(&1["to"] == task_id))
    |> Enum.map(& &1["from"])
  end
end
