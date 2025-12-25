defmodule Cascade.Runtime.WorkerSupervisor do
  @moduledoc """
  Supervisor for TaskRunner worker processes.

  Starts and manages a pool of TaskRunner GenServers that execute tasks.
  """

  use DynamicSupervisor
  require Logger

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Starts a pool of worker processes.
  """
  def start_workers(count \\ nil) do
    # Default: 2x number of schedulers (CPU cores)
    count = count || System.schedulers_online() * 2

    Logger.info("Starting #{count} worker processes")

    for i <- 1..count do
      spec = {Cascade.Runtime.TaskRunner, worker_id: i}
      DynamicSupervisor.start_child(__MODULE__, spec)
    end
  end

  @doc """
  Stops all workers.
  """
  def stop_workers do
    __MODULE__
    |> DynamicSupervisor.which_children()
    |> Enum.each(fn {_, pid, _, _} ->
      DynamicSupervisor.terminate_child(__MODULE__, pid)
    end)
  end
end
