defmodule CascadeWeb.DAGListLive do
  use CascadeWeb, :live_view

  alias Cascade.Workflows
  alias Cascade.Events

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Cascade.PubSub, Events.dag_updates_topic())
    end

    socket =
      socket
      |> assign(:page_title, "DAGs")
      |> load_dags()

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_dag", %{"id" => id}, socket) do
    dag = Workflows.get_dag!(id)
    {:ok, _updated_dag} = Workflows.update_dag(dag, %{enabled: !dag.enabled})

    {:noreply, load_dags(socket)}
  end

  @impl true
  def handle_info({:dag_event, _event}, socket) do
    {:noreply, load_dags(socket)}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  defp load_dags(socket) do
    dags = Workflows.list_dags()

    # Get job counts for each DAG
    dags_with_stats =
      Enum.map(dags, fn dag ->
        jobs = Workflows.list_jobs_for_dag(dag.id)
        Map.put(dag, :job_count, length(jobs))
      end)

    assign(socket, :dags, dags_with_stats)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200">
      <div class="navbar bg-base-100 shadow-lg">
        <div class="flex-1">
          <a href="/" class="btn btn-ghost text-xl">🌊 Cascade</a>
        </div>
        <div class="flex-none">
          <ul class="menu menu-horizontal px-1">
            <li><.link navigate={~p"/"}>Dashboard</.link></li>
            <li><.link navigate={~p"/dags"} class="font-bold">DAGs</.link></li>
            <li><.link navigate={~p"/workers"}>Workers</.link></li>
          </ul>
        </div>
      </div>

      <div class="container mx-auto p-6">
        <div class="flex justify-between items-center mb-6">
          <h1 class="text-4xl font-bold">DAGs</h1>
        </div>

        <%= if Enum.empty?(@dags) do %>
          <div class="bg-base-100 shadow-lg rounded-lg p-12 text-center">
            <div class="text-6xl mb-4">📋</div>
            <h2 class="text-2xl font-bold mb-2">No DAGs Yet</h2>
            <p class="text-base-content/60 mb-4">
              Create your first DAG to get started with Cascade.
            </p>
            <p class="text-sm text-base-content/60">
              Use
              <code class="bg-base-200 px-2 py-1 rounded">
                Cascade.Examples.DAGLoader.load_etl_dag()
              </code>
              in IEx to load the example DAG.
            </p>
          </div>
        <% else %>
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            <%= for dag <- @dags do %>
              <div class="card bg-base-100 shadow-lg">
                <div class="card-body">
                  <div class="flex justify-between items-start mb-2">
                    <h2 class="card-title">{dag.name}</h2>
                    <div class="form-control">
                      <label class="label cursor-pointer gap-2">
                        <span class="label-text">Enabled</span>
                        <input
                          type="checkbox"
                          class="toggle toggle-success"
                          checked={dag.enabled}
                          phx-click="toggle_dag"
                          phx-value-id={dag.id}
                        />
                      </label>
                    </div>
                  </div>

                  <p class="text-sm text-base-content/70 mb-4">
                    {dag.description || "No description"}
                  </p>

                  <div class="divider my-2"></div>

                  <div class="grid grid-cols-2 gap-2 text-sm mb-4">
                    <div>
                      <div class="font-semibold">Tasks</div>
                      <div class="text-base-content/70">
                        {length(dag.definition["nodes"])}
                      </div>
                    </div>
                    <div>
                      <div class="font-semibold">Jobs Run</div>
                      <div class="text-base-content/70">
                        {Map.get(dag, :job_count, 0)}
                      </div>
                    </div>
                    <div class="col-span-2">
                      <div class="font-semibold">Schedule</div>
                      <div class="text-base-content/70">
                        <%= if dag.schedule do %>
                          <code class="text-xs bg-base-200 px-2 py-1 rounded">{dag.schedule}</code>
                        <% else %>
                          Manual only
                        <% end %>
                      </div>
                    </div>
                    <div class="col-span-2">
                      <div class="font-semibold">Version</div>
                      <div class="text-base-content/70">
                        v{dag.version} · Updated {relative_time(dag.updated_at)}
                      </div>
                    </div>
                  </div>

                  <div class="card-actions justify-end">
                    <.link
                      navigate={~p"/dags/#{dag.id}"}
                      class="btn btn-primary btn-sm"
                    >
                      View Details
                    </.link>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp relative_time(nil), do: "never"

  defp relative_time(datetime) do
    dt =
      case datetime do
        %DateTime{} -> datetime
        %NaiveDateTime{} -> DateTime.from_naive!(datetime, "Etc/UTC")
      end

    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      # future or now
      diff <= 0 -> "just now"
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      diff < 604_800 -> "#{div(diff, 86400)}d ago"
      true -> "#{div(diff, 604_800)}w ago"
    end
  end
end
