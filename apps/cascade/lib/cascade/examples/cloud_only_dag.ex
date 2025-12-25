defmodule Cascade.Examples.CloudOnlyDAG do
  @moduledoc """
  Simple cloud-only DAG for testing Lambda and S3 integration.

  This DAG:
  - Runs entirely on AWS Lambda
  - Stores all results in S3
  - No local task execution
  """

  use Cascade.DSL

  dag "cloud_test_pipeline",
    description: "Simple cloud-only pipeline for testing Lambda + S3",
    schedule: nil,  # Manual trigger only
    tasks: [
      # Step 1: Process data on Lambda (stores to S3)
      process: [
        type: :lambda,
        function_name: "cascade-data-processor",
        timeout: 60,
        memory: 512,
        store_output_to_s3: true,
        output_s3_key: "cloud-test/{{job_id}}/process_result.json"
      ],

      # Step 2: Aggregate results on Lambda (depends on step 1, stores to S3)
      aggregate: [
        type: :lambda,
        function_name: "cascade-aggregator",
        timeout: 30,
        memory: 256,
        store_output_to_s3: true,
        output_s3_key: "cloud-test/{{job_id}}/final_result.json",
        depends_on: [:process]
      ]
    ]
end
