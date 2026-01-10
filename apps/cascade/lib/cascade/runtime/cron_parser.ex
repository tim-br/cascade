defmodule Cascade.Runtime.CronParser do
  @moduledoc """
  Cron expression parsing and next-run calculation utilities.

  Wraps the `crontab` library with Cascade-specific handling.
  """

  @doc """
  Parses a cron expression string.

  Returns {:ok, %Crontab.CronExpression{}} or {:error, reason}.

  Supports:
  - Standard 5-field format: "minute hour day month weekday"
  - Common aliases: @hourly, @daily, @weekly, @monthly, @yearly
  """
  @spec parse(String.t()) :: {:ok, Crontab.CronExpression.t()} | {:error, term()}
  def parse(expression) when is_binary(expression) do
    expression
    |> String.trim()
    |> expand_aliases()
    |> Crontab.CronExpression.Parser.parse()
  end

  @doc """
  Calculates the next run time after a given datetime.

  Returns {:ok, DateTime.t()} or {:error, :no_next_run}.
  """
  @spec next_run(Crontab.CronExpression.t(), DateTime.t()) ::
          {:ok, DateTime.t()} | {:error, :no_next_run}
  def next_run(%Crontab.CronExpression{} = cron, %DateTime{} = after_time) do
    naive = DateTime.to_naive(after_time)

    case Crontab.Scheduler.get_next_run_date(cron, naive) do
      {:ok, next_naive} ->
        {:ok, DateTime.from_naive!(next_naive, "Etc/UTC")}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Checks if a schedule is due to run at the given time.

  A schedule is "due" if next_run_at <= current_time.
  """
  @spec is_due?(DateTime.t(), DateTime.t()) :: boolean()
  def is_due?(next_run_at, current_time) do
    DateTime.compare(next_run_at, current_time) in [:lt, :eq]
  end

  @doc """
  Validates a cron expression without parsing.
  """
  @spec valid?(String.t()) :: boolean()
  def valid?(expression) do
    case parse(expression) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  # Expand common cron aliases
  defp expand_aliases("@yearly"), do: "0 0 1 1 *"
  defp expand_aliases("@annually"), do: "0 0 1 1 *"
  defp expand_aliases("@monthly"), do: "0 0 1 * *"
  defp expand_aliases("@weekly"), do: "0 0 * * 0"
  defp expand_aliases("@daily"), do: "0 0 * * *"
  defp expand_aliases("@midnight"), do: "0 0 * * *"
  defp expand_aliases("@hourly"), do: "0 * * * *"
  defp expand_aliases(expr), do: expr
end
