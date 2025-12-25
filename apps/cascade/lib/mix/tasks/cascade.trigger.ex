defmodule Mix.Tasks.Cascade.Trigger do
  @moduledoc """
  Triggers a Cascade job for a specified DAG.

  ## Usage

      # Trigger a job for a DAG by name
      mix cascade.trigger cloud_test_pipeline

      # Trigger with custom context (JSON)
      mix cascade.trigger daily_etl_pipeline --context '{"env": "prod"}'

  ## Examples

      # Cloud-only test pipeline
      mix cascade.trigger cloud_test_pipeline

      # ETL pipeline with context
      mix cascade.trigger daily_etl_pipeline --context '{"date": "2025-12-25"}'

      # Hybrid pipeline
      mix cascade.trigger hybrid_processing_pipeline
  """

  use Mix.Task
  require Logger

  @shortdoc "Triggers a Cascade job for a specified DAG"

  @impl Mix.Task
  def run(args) do
    # Start the application
    Mix.Task.run("app.start")

    {opts, args, _} = OptionParser.parse(args,
      strict: [context: :string, wait: :boolean],
      aliases: [c: :context, w: :wait]
    )

    case args do
      [dag_name] ->
        trigger_job(dag_name, opts)

      [] ->
        Mix.shell().error("Error: DAG name required")
        Mix.shell().info("Usage: mix cascade.trigger DAG_NAME [--context JSON]")
        list_available_dags()

      _ ->
        Mix.shell().error("Error: Too many arguments")
        Mix.shell().info("Usage: mix cascade.trigger DAG_NAME [--context JSON]")
    end
  end

  defp trigger_job(dag_name, opts) do
    context = parse_context(opts[:context])

    case Cascade.Workflows.get_dag_by_name(dag_name) do
      nil ->
        Mix.shell().error("Error: DAG '#{dag_name}' not found")
        list_available_dags()

      dag ->
        Mix.shell().info("Triggering job for DAG: #{dag.name}")
        Mix.shell().info("Description: #{dag.description}")

        if context != %{} do
          Mix.shell().info("Context: #{inspect(context)}")
        end

        case Cascade.Runtime.Scheduler.trigger_job(dag.id, "mix_task", context) do
          {:ok, job} ->
            Mix.shell().info("")
            Mix.shell().info("✓ Job triggered successfully!")
            Mix.shell().info("  Job ID: #{job.id}")
            Mix.shell().info("  Status: #{job.status}")
            Mix.shell().info("")
            Mix.shell().info("Monitor job execution:")
            Mix.shell().info("  • Web UI: http://localhost:4000/jobs/#{job.id}")
            Mix.shell().info("  • IEx: Cascade.Workflows.get_job_with_details!(\"#{job.id}\")")
            Mix.shell().info("")

            # Wait for job to complete via PubSub
            if opts[:wait] != false do
              wait_for_job_completion_via_pubsub(job.id)
            else
              # Just show initial status
              Process.sleep(500)
              print_job_status(job.id)
            end

          {:error, reason} ->
            Mix.shell().error("Error triggering job: #{inspect(reason)}")
        end
    end
  end

  defp parse_context(nil), do: %{}
  defp parse_context(context_str) do
    case Jason.decode(context_str) do
      {:ok, context} ->
        context

      {:error, reason} ->
        Mix.shell().error("Warning: Invalid JSON context: #{inspect(reason)}")
        Mix.shell().error("Using empty context instead")
        %{}
    end
  end

  defp list_available_dags do
    Mix.shell().info("")
    Mix.shell().info("Available DAGs:")

    case Cascade.Workflows.list_dags() do
      [] ->
        Mix.shell().info("  (none)")
        Mix.shell().info("")
        Mix.shell().info("Load example DAGs with: Cascade.Examples.DAGLoader.load_all()")

      dags ->
        Enum.each(dags, fn dag ->
          Mix.shell().info("  • #{dag.name} - #{dag.description}")
        end)
    end

    Mix.shell().info("")
  end

  defp wait_for_job_completion_via_pubsub(job_id, max_wait_ms \\ 300_000, first_call \\ true) do
    if first_call do
      Mix.shell().info("Waiting for job to complete...")
      # Subscribe to job events
      Phoenix.PubSub.subscribe(Cascade.PubSub, Cascade.Events.job_topic(job_id))
      Phoenix.PubSub.subscribe(Cascade.PubSub, Cascade.Events.job_tasks_topic(job_id))
    end

    # Wait for job completion event or timeout
    receive do
      {:job_event, %{status: status}} when status in [:success, :failed] ->
        Mix.shell().info("")
        print_job_status(job_id)
        Mix.shell().info("✓ Job completed with status: #{status}")

      {:task_event, event} ->
        # Show task progress
        icon = case event.status do
          :running -> "→"
          :success -> "✓"
          :failed -> "✗"
          _ -> "·"
        end
        Mix.shell().info("  #{icon} #{event.task_id}: #{event.status}")
        wait_for_job_completion_via_pubsub(job_id, max_wait_ms, false)
    after
      max_wait_ms ->
        Mix.shell().error("Timeout: Job did not complete within #{max_wait_ms / 1000}s")
        print_job_status(job_id)
    end
  end

  defp print_job_status(job_id) do
    job = Cascade.Workflows.get_job_with_details!(job_id)
    task_executions = Cascade.Workflows.list_task_executions_for_job(job_id)

    Mix.shell().info("Current status:")
    Mix.shell().info("  Job: #{job.status}")

    if length(task_executions) > 0 do
      Mix.shell().info("  Tasks:")
      Enum.each(task_executions, fn te ->
        status_icon = case te.status do
          :success -> "✓"
          :failed -> "✗"
          :running -> "→"
          :queued -> "○"
          _ -> "·"
        end

        Mix.shell().info("    #{status_icon} #{te.task_id}: #{te.status}")
      end)
    end

    Mix.shell().info("")
  end
end
