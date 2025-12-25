defmodule Cascade.DSL do
  @moduledoc """
  DSL for defining DAGs in Elixir.

  ## Example

      defmodule MyApp.ExampleDAG do
        use Cascade.DSL

        dag "data_pipeline" do
          description "Daily ETL pipeline"
          schedule "0 2 * * *"

          task :extract do
            type :local
            module MyApp.Tasks.Extract
            timeout 300
          end

          task :transform do
            type :local
            module MyApp.Tasks.Transform
            depends_on [:extract]
          end
        end
      end
  """

  defmacro __using__(_opts) do
    quote do
      import Cascade.DSL
      Module.register_attribute(__MODULE__, :dag_definition, accumulate: false)
      Module.register_attribute(__MODULE__, :dag_name, accumulate: false)
      Module.register_attribute(__MODULE__, :tasks, accumulate: true)
    end
  end

  @doc """
  Defines a DAG with the given name and block of tasks.
  """
  defmacro dag(name, do: block) do
    quote do
      @dag_name unquote(name)
      unquote(block)
      @dag_definition Cascade.DSL.Compiler.compile(@dag_name, @tasks, __MODULE__)

      def get_dag_definition, do: @dag_definition
      def dag_name, do: @dag_name
    end
  end

  @doc """
  Sets the description for the DAG.
  """
  defmacro description(text) do
    quote do
      Module.put_attribute(__MODULE__, :dag_description, unquote(text))
    end
  end

  @doc """
  Sets the schedule (cron expression) for the DAG.
  """
  defmacro schedule(cron_expression) do
    quote do
      Module.put_attribute(__MODULE__, :dag_schedule, unquote(cron_expression))
    end
  end

  @doc """
  Defines a task within a DAG.
  """
  defmacro task(task_id, do: block) do
    quote do
      task_id = unquote(task_id)
      task_config = %{id: task_id}

      # Execute the task configuration block
      task_config = unquote(block_to_config(block))

      # Add task to module attribute
      @tasks {task_id, task_config}
    end
  end

  # Convert task configuration block to a map
  defp block_to_config(block) do
    quote do
      task_config = %{id: task_id}

      task_config =
        unquote(block)
        |> case do
          {:__block__, _, expressions} -> expressions
          single_expr -> [single_expr]
        end
        |> Enum.reduce(task_config, fn expr, acc ->
          case expr do
            {:type, _, [type_val]} ->
              Map.put(acc, :type, type_val)

            {:module, _, [module_val]} ->
              Map.put(acc, :module, module_val)

            {:timeout, _, [timeout_val]} ->
              Map.put(acc, :timeout, timeout_val)

            {:depends_on, _, [deps]} ->
              Map.put(acc, :depends_on, deps)

            {:function_name, _, [fn_name]} ->
              Map.put(acc, :function_name, fn_name)

            {:memory, _, [mem]} ->
              Map.put(acc, :memory, mem)

            {:output, _, [output_type]} ->
              Map.put(acc, :output, output_type)

            {:artifact_key, _, [key]} ->
              Map.put(acc, :artifact_key, key)

            {:retry, _, [[opts]]} ->
              Map.put(acc, :retry, opts)

            _ ->
              acc
          end
        end)

      task_config
    end
  end

  @doc """
  Specifies the type of task (:local or :lambda).
  """
  defmacro type(value), do: value

  @doc """
  Specifies the Elixir module to execute for local tasks.
  """
  defmacro module(value), do: value

  @doc """
  Specifies the timeout in seconds.
  """
  defmacro timeout(value), do: value

  @doc """
  Specifies task dependencies.
  """
  defmacro depends_on(deps), do: deps

  @doc """
  Specifies the Lambda function name for remote execution.
  """
  defmacro function_name(name), do: name

  @doc """
  Specifies memory allocation for Lambda functions.
  """
  defmacro memory(mb), do: mb

  @doc """
  Specifies output storage type.
  """
  defmacro output(type), do: type

  @doc """
  Specifies the artifact key template for S3 storage.
  """
  defmacro artifact_key(key), do: key

  @doc """
  Specifies retry configuration.
  """
  defmacro retry(opts), do: opts
end
