defmodule Cascade.Examples.ComplexDAG do
  @moduledoc """
  Complex data processing pipeline with parallel execution.

  This DAG demonstrates:
  - Multiple parallel ingestion sources (API, Database, Files)
  - Independent validation steps
  - Parallel transformations with fan-in/fan-out patterns
  - Quality checks and aggregation
  - Multiple destination loads
  - Final notifications
  """

  use Cascade.DSL

  dag "data_processing_pipeline",
    description: "Complex data pipeline with parallel processing and aggregation",
    schedule: "0 3 * * *",  # Run daily at 3 AM
    tasks: [
      # Stage 1: Data ingestion from multiple sources (parallel)
      fetch_api_data: [
        type: :local,
        module: Cascade.Examples.Tasks.FetchAPIData,
        timeout: 300
      ],
      fetch_database_data: [
        type: :local,
        module: Cascade.Examples.Tasks.FetchDatabaseData,
        timeout: 300
      ],
      fetch_file_data: [
        type: :local,
        module: Cascade.Examples.Tasks.FetchFileData,
        timeout: 300
      ],

      # Stage 2: Data validation (depends on ingestion)
      validate_api: [
        type: :local,
        module: Cascade.Examples.Tasks.ValidateAPIData,
        timeout: 120,
        depends_on: [:fetch_api_data]
      ],
      validate_database: [
        type: :local,
        module: Cascade.Examples.Tasks.ValidateDatabaseData,
        timeout: 120,
        depends_on: [:fetch_database_data]
      ],
      validate_files: [
        type: :local,
        module: Cascade.Examples.Tasks.ValidateFileData,
        timeout: 120,
        depends_on: [:fetch_file_data]
      ],

      # Stage 3: Parallel transformations (fan-in from validation, fan-out to multiple transforms)
      transform_customer_data: [
        type: :local,
        module: Cascade.Examples.Tasks.TransformCustomers,
        timeout: 600,
        depends_on: [:validate_api, :validate_database]
      ],
      transform_transaction_data: [
        type: :local,
        module: Cascade.Examples.Tasks.TransformTransactions,
        timeout: 600,
        depends_on: [:validate_api, :validate_database]
      ],
      transform_product_data: [
        type: :local,
        module: Cascade.Examples.Tasks.TransformProducts,
        timeout: 400,
        depends_on: [:validate_files]
      ],

      # Stage 4: Data quality checks (fan-in all transformations)
      quality_check: [
        type: :local,
        module: Cascade.Examples.Tasks.QualityCheck,
        timeout: 180,
        depends_on: [:transform_customer_data, :transform_transaction_data, :transform_product_data]
      ],

      # Stage 5: Aggregation and analytics (sequential)
      compute_metrics: [
        type: :local,
        module: Cascade.Examples.Tasks.ComputeMetrics,
        timeout: 300,
        depends_on: [:quality_check]
      ],
      generate_reports: [
        type: :local,
        module: Cascade.Examples.Tasks.GenerateReports,
        timeout: 240,
        depends_on: [:compute_metrics]
      ],

      # Stage 6: Load to destinations (parallel, different dependencies)
      load_warehouse: [
        type: :local,
        module: Cascade.Examples.Tasks.LoadWarehouse,
        timeout: 400,
        depends_on: [:quality_check]
      ],
      update_cache: [
        type: :local,
        module: Cascade.Examples.Tasks.UpdateCache,
        timeout: 120,
        depends_on: [:compute_metrics]
      ],

      # Stage 7: Final notifications (fan-in everything)
      send_completion_email: [
        type: :local,
        module: Cascade.Examples.Tasks.SendEmail,
        timeout: 60,
        depends_on: [:generate_reports, :load_warehouse, :update_cache]
      ],
      update_dashboard: [
        type: :local,
        module: Cascade.Examples.Tasks.UpdateDashboard,
        timeout: 90,
        depends_on: [:generate_reports, :load_warehouse]
      ]
    ]
end
