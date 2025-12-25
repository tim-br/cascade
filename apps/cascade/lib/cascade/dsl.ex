defmodule Cascade.DSL do
  @moduledoc """
  DSL for defining DAGs using clean keyword-list syntax.

  ## Usage Example

      defmodule MyApp.DailyETL do
        use Cascade.DSL

        dag "daily_etl_pipeline",
          description: "Daily ETL pipeline for data processing",
          schedule: "0 2 * * *",
          tasks: [
            extract: [
              type: :local,
              module: Cascade.Examples.Tasks.ExtractData,
              timeout: 300
            ],
            transform: [
              type: :local,
              module: Cascade.Examples.Tasks.TransformData,
              depends_on: [:extract],
              timeout: 300
            ],
            load: [
              type: :local,
              module: Cascade.Examples.Tasks.LoadData,
              depends_on: [:transform],
              timeout: 300
            ],
            notify: [
              type: :local,
              module: Cascade.Examples.Tasks.SendNotification,
              depends_on: [:load],
              timeout: 60
            ]
          ]
      end
  """

  defmacro __using__(_opts) do
    quote do
      import Cascade.DSL
      Module.register_attribute(__MODULE__, :dag_definition, accumulate: false)
      Module.register_attribute(__MODULE__, :dag_name, accumulate: false)
    end
  end

  @doc """
  Defines a DAG using keyword-list syntax.
  """
  defmacro dag(name, opts) do
    quote do
      opts = unquote(opts)

      name = unquote(name)
      description = Keyword.get(opts, :description)
      schedule = Keyword.get(opts, :schedule)
      tasks_keyword = Keyword.get(opts, :tasks, [])

      # Convert keyword list of tasks into the expected compiler format
      tasks =
        for {task_id, task_opts} <- tasks_keyword do
          task_config = %{
            id: task_id,
            type: Keyword.get(task_opts, :type),
            module: Keyword.get(task_opts, :module),
            timeout: Keyword.get(task_opts, :timeout),
            depends_on: Keyword.get(task_opts, :depends_on, []),
            function_name: Keyword.get(task_opts, :function_name),
            memory: Keyword.get(task_opts, :memory),
            output: Keyword.get(task_opts, :output),
            artifact_key: Keyword.get(task_opts, :artifact_key),
            retry: Keyword.get(task_opts, :retry),
            store_output_to_s3: Keyword.get(task_opts, :store_output_to_s3),
            output_s3_key: Keyword.get(task_opts, :output_s3_key)
          }

          {task_id, task_config}
        end

      @dag_name name
      @dag_definition Cascade.DSL.Compiler.compile(
                        name,
                        tasks,
                        __MODULE__,
                        description: description,
                        schedule: schedule
                      )

      def get_dag_definition, do: @dag_definition
      def dag_name, do: @dag_name
    end
  end
end
