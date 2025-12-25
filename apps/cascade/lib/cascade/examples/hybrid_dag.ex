defmodule Cascade.Examples.HybridDAG do
  @moduledoc """
  Hybrid DAG demonstrating both local and Lambda execution with S3 artifacts.

  This DAG shows:
  - Local data preparation
  - Lambda-based data processing (with S3 output)
  - Local aggregation of Lambda results
  - Mixed local/remote task dependencies
  """

  use Cascade.DSL

  dag "hybrid_processing_pipeline",
    description: "Hybrid pipeline mixing local and Lambda tasks",
    schedule: "0 4 * * *",  # Run daily at 4 AM
    tasks: [
      # Stage 1: Local data preparation
      prepare_data: [
        type: :local,
        module: Cascade.Examples.Tasks.PrepareData,
        timeout: 60
      ],

      # Stage 2: Parallel Lambda processing
      # These tasks would run on AWS Lambda with results stored in S3
      process_chunk_1: [
        type: :lambda,
        function_name: "cascade-data-processor",  # Your Lambda function name
        timeout: 300,
        memory: 1024,
        store_output_to_s3: true,
        output_s3_key: "results/{{job_id}}/chunk_1.json",
        depends_on: [:prepare_data]
      ],

      process_chunk_2: [
        type: :lambda,
        function_name: "cascade-data-processor",
        timeout: 300,
        memory: 1024,
        store_output_to_s3: true,
        output_s3_key: "results/{{job_id}}/chunk_2.json",
        depends_on: [:prepare_data]
      ],

      process_chunk_3: [
        type: :lambda,
        function_name: "cascade-data-processor",
        timeout: 300,
        memory: 1024,
        store_output_to_s3: true,
        output_s3_key: "results/{{job_id}}/chunk_3.json",
        depends_on: [:prepare_data]
      ],

      # Stage 3: Lambda aggregation (also stores to S3)
      aggregate_results: [
        type: :lambda,
        function_name: "cascade-aggregator",
        timeout: 180,
        memory: 512,
        store_output_to_s3: true,
        output_s3_key: "results/{{job_id}}/aggregated.json",
        depends_on: [:process_chunk_1, :process_chunk_2, :process_chunk_3]
      ],

      # Stage 4: Local validation and storage
      validate_and_store: [
        type: :local,
        module: Cascade.Examples.Tasks.ValidateAndStore,
        timeout: 120,
        depends_on: [:aggregate_results]
      ],

      # Stage 5: Local notification
      send_summary: [
        type: :local,
        module: Cascade.Examples.Tasks.SendSummary,
        timeout: 30,
        depends_on: [:validate_and_store]
      ]
    ]
end
