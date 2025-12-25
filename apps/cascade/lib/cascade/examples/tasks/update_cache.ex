defmodule Cascade.Examples.Tasks.UpdateCache do
  @moduledoc """
  Updates application cache.
  """

  require Logger

  def run(context) do
    Logger.info("UpdateCache: Updating cache for job #{context.job_id}")
    Process.sleep(800)
    {:ok, %{cache_keys_updated: 200, cache_hit_rate_improvement: "15%", timestamp: DateTime.utc_now()}}
  end
end
