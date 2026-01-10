defmodule Cascade.DagLoader do
  @moduledoc """
  Automatically loads and manages DAG definitions from multiple sources.

  Improvements over Airflow:
  - Multiple sources: local directory + S3 bucket (simultaneously)
  - Hot-reloading: only updates changed DAGs (checksum tracking)
  - Validation: validates DAGs before loading
  - Graceful error handling: bad DAGs don't crash the loader
  - Configurable scan interval per source

  Configuration (via environment variables):
  - DAGS_DIR: Local directory to scan for DAG files (default: ./dags)
  - DAGS_S3_BUCKET: S3 bucket to scan for DAG files (optional)
  - DAGS_S3_PREFIX: S3 prefix/path within bucket (default: dags/)
  - DAGS_SCAN_INTERVAL: Scan interval in seconds (default: 30)
  - DAGS_ENABLED: Enable/disable auto-loading (default: true)

  Supported file formats:
  - .json: JSON DAG definition
  - .exs: Elixir config file returning a DAG definition map
  """

  use GenServer
  require Logger

  alias Cascade.Workflows
  alias Cascade.Events
  alias Cascade.DagLoader.{LocalSource, S3Source, Validator}

  @default_scan_interval 30_000  # 30 seconds
  @default_dags_dir "dags"

  defmodule State do
    @moduledoc false
    defstruct [
      :scan_interval,
      :local_source,
      :s3_source,
      :loaded_dags,  # %{dag_name => checksum}
      :timer_ref,
      enabled: true
    ]
  end

  ## Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Trigger immediate DAG scan"
  def scan_now do
    GenServer.call(__MODULE__, :scan_now)
  end

  @doc "Get loader status and statistics"
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    enabled = System.get_env("DAGS_ENABLED", "true") == "true"

    if enabled do
      scan_interval = get_scan_interval()
      local_source = configure_local_source()
      s3_source = configure_s3_source()

      state = %State{
        scan_interval: scan_interval,
        local_source: local_source,
        s3_source: s3_source,
        loaded_dags: %{},
        enabled: true
      }

      Logger.info("🔄 [DAG_LOADER] Starting DAG loader (scan_interval=#{scan_interval}ms)")
      Logger.info("   Local source: #{inspect(local_source)}")
      Logger.info("   S3 source: #{inspect(s3_source)}")

      # Perform initial scan
      {:ok, state, {:continue, :initial_scan}}
    else
      Logger.info("🔄 [DAG_LOADER] DAG auto-loading disabled (DAGS_ENABLED=false)")
      {:ok, %State{enabled: false}}
    end
  end

  @impl true
  def handle_continue(:initial_scan, state) do
    # Perform initial scan immediately
    new_state = perform_scan(state)

    # Schedule next scan
    timer_ref = Process.send_after(self(), :scan, state.scan_interval)

    {:noreply, %{new_state | timer_ref: timer_ref}}
  end

  @impl true
  def handle_call(:scan_now, _from, %State{enabled: false} = state) do
    {:reply, {:error, :disabled}, state}
  end

  def handle_call(:scan_now, _from, state) do
    new_state = perform_scan(state)
    {:reply, :ok, new_state}
  end

  def handle_call(:get_status, _from, %State{enabled: false} = state) do
    {:reply, %{enabled: false}, state}
  end

  def handle_call(:get_status, _from, state) do
    status = %{
      enabled: true,
      scan_interval: state.scan_interval,
      loaded_dags: Map.keys(state.loaded_dags),
      dag_count: map_size(state.loaded_dags),
      local_source: state.local_source,
      s3_source: state.s3_source
    }

    {:reply, status, state}
  end

  @impl true
  def handle_info(:scan, %State{enabled: false} = state) do
    {:noreply, state}
  end

  def handle_info(:scan, state) do
    # Cancel existing timer if any
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)

    # Perform scan
    new_state = perform_scan(state)

    # Schedule next scan
    timer_ref = Process.send_after(self(), :scan, state.scan_interval)

    {:noreply, %{new_state | timer_ref: timer_ref}}
  end

  ## Private Functions

  defp get_scan_interval do
    case System.get_env("DAGS_SCAN_INTERVAL") do
      nil -> @default_scan_interval
      val ->
        case Integer.parse(val) do
          {seconds, ""} -> seconds * 1000
          _ ->
            Logger.warning("Invalid DAGS_SCAN_INTERVAL: #{val}, using default")
            @default_scan_interval
        end
    end
  end

  defp configure_local_source do
    dags_dir = System.get_env("DAGS_DIR", @default_dags_dir)

    if File.exists?(dags_dir) and File.dir?(dags_dir) do
      %{type: :local, path: dags_dir}
    else
      Logger.warning("DAGS_DIR not found or not a directory: #{dags_dir}")
      nil
    end
  end

  defp configure_s3_source do
    bucket = System.get_env("DAGS_S3_BUCKET")
    prefix = System.get_env("DAGS_S3_PREFIX", "dags/")

    if bucket do
      %{type: :s3, bucket: bucket, prefix: prefix}
    else
      nil
    end
  end

  defp perform_scan(state) do
    Logger.debug("🔍 [DAG_LOADER] Scanning for DAG updates...")

    # Load DAGs from all sources
    all_dags = []

    all_dags =
      if state.local_source do
        all_dags ++ LocalSource.load_dags(state.local_source)
      else
        all_dags
      end

    all_dags =
      if state.s3_source do
        all_dags ++ S3Source.load_dags(state.s3_source)
      else
        all_dags
      end

    # Process each DAG
    new_loaded_dags =
      Enum.reduce(all_dags, state.loaded_dags, fn {name, content, source_info}, acc ->
        process_dag(name, content, source_info, acc)
      end)

    # Check for deleted DAGs
    deleted_dags = Map.keys(state.loaded_dags) -- Map.keys(new_loaded_dags)

    Enum.each(deleted_dags, fn dag_name ->
      Logger.info("🗑️  [DAG_LOADER] DAG deleted: #{dag_name}")
      # Optionally disable the DAG instead of deleting
      case Workflows.get_dag_by_name(dag_name) do
        nil ->
          :ok

        dag ->
          case Workflows.update_dag(dag, %{enabled: false}) do
            {:ok, _updated_dag} ->
              Logger.info("   Disabled DAG: #{dag_name}")
              broadcast_dag_event(:deleted, dag_name)

            {:error, _reason} ->
              :ok
          end
      end
    end)

    %{state | loaded_dags: new_loaded_dags}
  end

  defp process_dag(name, content, source_info, loaded_dags) do
    # Calculate checksum
    checksum = :crypto.hash(:md5, content) |> Base.encode16()

    # Check if DAG has changed
    case Map.get(loaded_dags, name) do
      ^checksum ->
        # No change, skip
        loaded_dags

      _ ->
        # New or changed DAG, load it
        load_dag(name, content, source_info, checksum, loaded_dags)
    end
  end

  defp load_dag(name, content, source_info, checksum, loaded_dags) do
    Logger.info("📥 [DAG_LOADER] Loading DAG: #{name} from #{source_info[:source]}")

    with {:ok, dag_definition} <- parse_dag_content(content, source_info),
         :ok <- Validator.validate_dag(dag_definition),
         {:ok, _dag} <- upsert_dag(name, dag_definition, source_info) do
      Logger.info("✅ [DAG_LOADER] Successfully loaded DAG: #{name}")
      Map.put(loaded_dags, name, checksum)
    else
      {:error, reason} ->
        Logger.error("❌ [DAG_LOADER] Failed to load DAG #{name}: #{inspect(reason)}")
        # Don't update checksum so we'll retry next scan
        loaded_dags
    end
  end

  defp parse_dag_content(content, %{extension: ".json"}) do
    case Jason.decode(content) do
      {:ok, dag_def} -> {:ok, dag_def}
      {:error, error} -> {:error, "JSON parse error: #{inspect(error)}"}
    end
  end

  defp parse_dag_content(content, %{extension: ".exs"}) do
    try do
      {result, _binding} = Code.eval_string(content)
      {:ok, result}
    rescue
      error -> {:error, "Elixir eval error: #{inspect(error)}"}
    end
  end

  defp parse_dag_content(_content, %{extension: ext}) do
    {:error, "Unsupported file extension: #{ext}"}
  end

  defp upsert_dag(name, definition, source_info) do
    attrs = %{
      name: name,
      description: Map.get(definition, "description", "Loaded from #{source_info[:source]}"),
      definition: definition,
      enabled: Map.get(definition, "enabled", true),
      schedule: Map.get(definition, "schedule")
    }

    result =
      case Workflows.get_dag_by_name(name) do
        nil ->
          # Create new DAG
          case Workflows.create_dag(attrs) do
            {:ok, _dag} = success ->
              broadcast_dag_event(:created, name)
              success

            error ->
              error
          end

        existing_dag ->
          # Update existing DAG
          case Workflows.update_dag(existing_dag, attrs) do
            {:ok, _dag} = success ->
              broadcast_dag_event(:updated, name)
              success

            error ->
              error
          end
      end

    result
  end

  defp broadcast_dag_event(action, dag_name) do
    Phoenix.PubSub.broadcast(
      Cascade.PubSub,
      Events.dag_updates_topic(),
      {:dag_event, %{action: action, dag_name: dag_name}}
    )
  end
end
