
defmodule Cascade.Examples.ETLDAG do
  @moduledoc """
  Example ETL (Extract, Transform, Load) DAG.

  This DAG demonstrates a simple data pipeline with:
  - Extract data from source
  - Transform data
  - Load data to warehouse
  - Send notification upon completion
  """

  use Cascade.DSL

  dag "daily_etl_pipeline",
    description: "Daily ETL pipeline for data processing",
    schedule: "0 2 * * *",
    tasks: [
      extract: [
        type: :local,
        module: Cascade.Examples.Tasks.ExtractData,
        timeout: 10
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
