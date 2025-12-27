defmodule Cascade.Runtime.TaskExecutors.LocalExecutor do
  @moduledoc """
  Executes tasks locally by invoking Elixir modules.

  Task modules should implement a `run/1` function that takes a context map
  and returns `{:ok, result}` or `{:error, reason}`.
  """

  require Logger

  @doc """
  Executes a local task by calling the configured module's run/1 function.

  The task_config should contain:
  - "module": The Elixir module to execute (as a string)
  - Additional config is passed to the module's run/1 function

  The payload contains:
  - job_id, task_id, task_config
  """
  def execute(task_config, payload) do
    Logger.info("Executing task with payload: #{inspect(payload)}")

    # Module might be at top level or in config
    module_name = task_config["module"] || get_in(task_config, ["config", "module"])

    if module_name do
      try do
        # Convert module name to atom (safe since we control DAG definitions)
        # Use String.to_atom instead of to_existing_atom to handle modules that aren't loaded yet
        module = String.to_atom("Elixir.#{module_name}")

        # Ensure the module is loaded
        case Code.ensure_loaded(module) do
          {:module, ^module} ->
            # Build context for the task
            context = %{
              job_id: payload[:job_id],
              task_id: payload[:task_id],
              config: task_config["config"] || task_config
            }

            # Execute the module's run/1 function
            apply_task_function(module, context)

          {:error, reason} ->
            {:error, "Failed to load module #{module_name}: #{inspect(reason)}"}
        end
      rescue
        error ->
          {:error, "Task execution failed: #{inspect(error)}"}
      end
    else
      {:error, "No module specified for local task"}
    end
  end

  defp apply_task_function(module, context) do
    if function_exported?(module, :run, 1) do
      Logger.info("Executing #{module}.run/1")

      case apply(module, :run, [context]) do
        {:ok, result} ->
          {:ok, result}

        {:error, reason} ->
          {:error, reason}

        result ->
          # If module doesn't return tuple, wrap it
          {:ok, result}
      end
    else
      {:error, "Module #{module} does not export run/1"}
    end
  end
end
