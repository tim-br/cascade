#!/usr/bin/env elixir

# Quick test script for Cascade
# Run with: mix run test_cascade.exs

IO.puts("\n🚀 Testing Cascade - Phase 1\n")
IO.puts("=" <> String.duplicate("=", 50))

# Load the ETL DAG
IO.puts("\n1. Loading ETL DAG...")
{:ok, dag} = Cascade.Examples.DAGLoader.load_etl_dag()
IO.puts("   ✓ DAG loaded: #{dag.name}")
IO.puts("   ✓ DAG ID: #{dag.id}")
IO.puts("   ✓ Tasks: #{length(dag.definition["nodes"])}")

# Trigger a job
IO.puts("\n2. Triggering job...")
{:ok, job} = Cascade.Runtime.Scheduler.trigger_job(dag.id, "test_script", %{test: true})
IO.puts("   ✓ Job triggered: #{job.id}")
IO.puts("   ✓ Status: #{job.status}")

# Wait for completion (tasks take ~4 seconds total)
IO.puts("\n3. Waiting for job to complete...")
Process.sleep(5000)

# Check final status
job_final = Cascade.Workflows.get_job_with_details!(job.id)
task_executions = Cascade.Workflows.list_task_executions_for_job(job.id)

IO.puts("\n4. Job Results:")
IO.puts("   Status: #{job_final.status}")
IO.puts("   Started: #{job_final.started_at}")
IO.puts("   Completed: #{job_final.completed_at}")

IO.puts("\n5. Task Executions:")
Enum.each(task_executions, fn te ->
  status_icon = if te.status == :success, do: "✓", else: "✗"
  IO.puts("   #{status_icon} #{te.task_id}: #{te.status}")
end)

# Summary
success_count = Enum.count(task_executions, &(&1.status == :success))
total_count = length(task_executions)

IO.puts("\n" <> String.duplicate("=", 50))
if success_count == total_count and job_final.status == :success do
  IO.puts("✅ SUCCESS! All #{total_count} tasks completed successfully!")
else
  IO.puts("❌ FAILED! #{success_count}/#{total_count} tasks succeeded")
end
IO.puts(String.duplicate("=", 50) <> "\n")
