defmodule Cascade.Examples.Tasks.TransformProducts do
  @moduledoc """
  Transforms product data.
  """

  require Logger

  def run(context) do
    Logger.info("TransformProducts: Transforming product data for job #{context.job_id}")
    Process.sleep(2000)
    {:ok, %{products_transformed: 2500, categories_normalized: 80, timestamp: DateTime.utc_now()}}
  end
end
