# Cascade

**A modern, distributed workflow orchestration engine built in Elixir**

🔗 **[Live Demo](https://cascade.nauths.io)** | 📖 [Documentation](#installation) | 🐛 [Issues](https://github.com/tim-br/cascade/issues)

Cascade is an Airflow-inspired workflow orchestrator that fixes key design limitations:

> **Note**: Cascade is an Elixir umbrella application with two main components:
> - `apps/cascade` - Core workflow engine
> - `apps/cascade_web` - Phoenix LiveView UI
> - `terraform/` - AWS infrastructure (Lambda, S3, RDS, ALB)
- **Non-blocking workers**: Workers coordinate asynchronously and don't block on external task execution
- **True parallelism**: Async/await for parallel execution within workers
- **Decoupled capacity**: Orchestration capacity is independent from execution capacity
- **Cloud-native**: First-class support for AWS Lambda and S3
- **Real-time updates**: Built on Phoenix PubSub for live job monitoring

## Features

- ✅ **Auto-Loading DAGs** - Automatic hot-reloading from local directory or S3 bucket
- ✅ **Elixir DSL** - Define workflows as code with clean, functional syntax
- ✅ **Worker Pool Execution** - Concurrent task execution with configurable worker pool
- ✅ **Hybrid Workflows** - Mix local Elixir tasks with serverless Lambda functions
- ✅ **Data Flow** - Automatic data passing between dependent tasks via S3
- ✅ **Real-time Monitoring** - Phoenix LiveView UI with live job status updates
- ✅ **Artifact Storage** - S3 integration for large task outputs
- ✅ **DAG Validation** - Comprehensive validation with cycle detection
- 📋 **Distributed Execution** - Multi-node clustering with load balancing (Phase 2)
- 📋 **Fault Tolerance** - Automatic task reassignment on worker failure (Phase 2)

## Architecture

```
┌─────────────┐
│   Trigger   │ (Web UI, Mix Task, API)
└──────┬──────┘
       │
       v
┌─────────────┐     ┌──────────────┐
│  Scheduler  │────>│ StateManager │ (ETS + Postgres)
└──────┬──────┘     └──────────────┘
       │
       v
┌─────────────┐     ┌──────────────┐
│  Executor   │────>│ TaskRunners  │ (Worker Pool)
└─────────────┘     └──────┬───────┘
                           │
              ┌────────────┴────────────┐
              │                         │
              v                         v
    ┌──────────────┐          ┌──────────────┐
    │ Local Tasks  │          │ Lambda Tasks │
    │  (Elixir)    │          │   (AWS)      │
    └──────────────┘          └──────┬───────┘
                                     │
                                     v
                              ┌──────────────┐
                              │  S3 Storage  │
                              └──────────────┘
```

### Data Flow

1. **Job Context**: Initial parameters passed when triggering a job
2. **Task Execution**: Each task receives job context + upstream task results
3. **Result Storage**: Task outputs stored in Postgres (small) or S3 (large)
4. **Data Passing**: Downstream tasks automatically receive upstream results

## Installation

### Prerequisites

- Elixir 1.14+
- Erlang/OTP 25+
- PostgreSQL 14+
- AWS Account (for Lambda/S3 features)

### Setup

1. **Clone and install dependencies**
   ```bash
   git clone git@github.com:tim-br/cascade.git
   cd cascade
   mix deps.get
   ```

2. **Configure database**
   ```bash
   # Edit config/dev.exs with your Postgres credentials
   mix ecto.create
   mix ecto.migrate
   ```

3. **Configure AWS (optional)**
   ```bash
   aws configure  # Sets up ~/.aws/credentials
   export AWS_REGION="us-east-2"
   export CASCADE_S3_BUCKET="your-bucket-name"
   ```

4. **Start the application**
   ```bash
   iex -S mix
   ```

## Creating Workflows

### Basic DAG Definition

```elixir
defmodule MyApp.DailyETL do
  use Cascade.DSL

  dag "daily_etl_pipeline",
    description: "Daily ETL pipeline for data processing",
    schedule: "0 2 * * *",  # Cron format
    tasks: [
      # Task 1: Extract data
      extract: [
        type: :local,
        module: MyApp.Tasks.Extract,
        timeout: 300
      ],

      # Task 2: Transform (depends on extract)
      transform: [
        type: :local,
        module: MyApp.Tasks.Transform,
        depends_on: [:extract],
        timeout: 300
      ],

      # Task 3: Load (depends on transform)
      load: [
        type: :local,
        module: MyApp.Tasks.Load,
        depends_on: [:transform],
        timeout: 300
      ]
    ]
end
```

### Hybrid Local + Lambda DAG

```elixir
defmodule MyApp.DataPipeline do
  use Cascade.DSL

  dag "cloud_processing_pipeline",
    description: "Hybrid pipeline with Lambda processing",
    schedule: nil,  # Manual trigger only
    tasks: [
      # Local preprocessing
      preprocess: [
        type: :local,
        module: MyApp.Tasks.Preprocess,
        timeout: 60
      ],

      # Heavy processing on Lambda
      process: [
        type: :lambda,
        function_name: "data-processor",
        timeout: 300,
        memory: 1024,
        store_output_to_s3: true,
        output_s3_key: "results/{{job_id}}/processed.json",
        depends_on: [:preprocess]
      ],

      # Aggregate results locally
      aggregate: [
        type: :local,
        module: MyApp.Tasks.Aggregate,
        depends_on: [:process],
        timeout: 60
      ]
    ]
end
```

## Passing Data Between Tasks

### Overview

Cascade automatically passes data between dependent tasks:
1. **Job Context**: Initial parameters (e.g., date range, configuration)
2. **Upstream Results**: Outputs from completed dependency tasks

### Task Implementation

#### Local Task (Elixir)

```elixir
defmodule MyApp.Tasks.Process do
  @behaviour Cascade.Task

  def execute(task_config, payload) do
    # Extract job context (initial parameters)
    context = Map.get(payload, :context, %{})
    input_data = context["input_data"]
    multiplier = context["multiplier"]

    # Get results from upstream tasks
    upstream_results = context["upstream_results"] || %{}

    if upstream_task_result = upstream_results["preprocess"] do
      # Use data from preprocess task
      preprocessed_values = upstream_task_result["values"]
      # Process the data...
    end

    # Process and return results
    processed = Enum.map(input_data, fn x -> x * multiplier end)

    {:ok, %{
      "processed_values" => processed,
      "total" => Enum.sum(processed),
      "count" => length(processed)
    }}
  end
end
```

#### Lambda Task (Python)

```python
def lambda_handler(event, context):
    # Extract job context
    job_context = event.get('context', {})
    input_data = job_context.get('input_data', [])
    multiplier = job_context.get('multiplier', 1)

    # Get upstream results
    upstream_results = job_context.get('upstream_results', {})

    # Download upstream data from S3
    if 'process' in upstream_results:
        s3_key = upstream_results['process']['result_s3_key']
        # Download and process upstream data from S3
        upstream_data = download_from_s3(s3_key)
        values = upstream_data['processed_values']

    # Process and return
    result = {
        "aggregated_total": sum(values),
        "average": sum(values) / len(values),
        "min": min(values),
        "max": max(values)
    }

    return {
        "statusCode": 200,
        "body": result
    }
```

### Context Structure

When a task executes, it receives this payload:

```elixir
%{
  job_id: "uuid",
  task_id: "aggregate",
  task_config: %{...},
  context: %{
    # Initial job parameters
    "input_data" => [10, 20, 30],
    "multiplier" => 2,

    # Results from upstream tasks
    "upstream_results" => %{
      "process" => %{
        # For small results: inline data
        "processed_values" => [20, 40, 60],
        "total" => 120,

        # For large results: S3 references
        "result_location" => "s3://bucket/path/to/result.json",
        "result_s3_key" => "path/to/result.json",
        "result_size_bytes" => 1024
      }
    }
  }
}
```

### Triggering Jobs with Context

#### Via Mix Task

```bash
mix cascade.trigger daily_etl_pipeline \
  --context '{"date": "2025-12-25", "env": "production"}'
```

#### Via IEx

```elixir
Cascade.Runtime.Scheduler.trigger_job(
  dag_id,
  "user@example.com",
  %{"date" => "2025-12-25", "batch_size" => 1000}
)
```

#### Via Web UI

In the job trigger form, paste JSON context:
```json
{
  "input_data": [10, 20, 30, 40, 50],
  "multiplier": 3,
  "processing_mode": "fast"
}
```

### S3 Artifact Storage

For large task outputs, enable S3 storage:

```elixir
process: [
  type: :lambda,
  function_name: "large-data-processor",
  store_output_to_s3: true,
  output_s3_key: "results/{{job_id}}/{{task_id}}.json"
]
```

Downstream tasks receive S3 references and can download:
```python
# In downstream Lambda
upstream_s3_key = upstream_results['process']['result_s3_key']
s3_client.get_object(Bucket=bucket, Key=upstream_s3_key)
```

## Task Types

### Local Tasks (`:local`)

Execute Elixir modules in the worker pool.

**Configuration:**
```elixir
extract: [
  type: :local,
  module: MyApp.Tasks.Extract,
  timeout: 300,  # seconds
  retry: 3
]
```

**Implementation:**
```elixir
defmodule MyApp.Tasks.Extract do
  @behaviour Cascade.Task

  def execute(task_config, payload) do
    # Your task logic here
    {:ok, %{"records" => 1000}}
  end
end
```

### Lambda Tasks (`:lambda`)

Execute on AWS Lambda for:
- Heavy computation
- Language-specific processing (Python, Node.js, etc.)
- Scaling beyond cluster capacity

**Configuration:**
```elixir
process: [
  type: :lambda,
  function_name: "my-lambda-function",
  timeout: 300,          # seconds
  memory: 1024,          # MB
  invocation_type: :sync, # or :async
  store_output_to_s3: true,
  output_s3_key: "results/{{job_id}}/output.json"
]
```

## Loading DAGs

Cascade features **automatic DAG loading** that improves on Airflow's approach. DAGs are automatically loaded from a directory on startup and hot-reloaded when files change.

### Auto-Loading (Recommended) 🆕

Simply place DAG definition files in the `./dags` directory (or custom location):

**JSON Format:**
```json
// dags/my_pipeline.json
{
  "nodes": [
    {"id": "extract", "type": "local", "config": {...}},
    {"id": "transform", "type": "local", "config": {...}, "depends_on": ["extract"]}
  ],
  "edges": [{"from": "extract", "to": "transform"}],
  "description": "My ETL Pipeline",
  "enabled": true
}
```

**Elixir Format (for dynamic DAGs):**
```elixir
# dags/dynamic_pipeline.exs
tasks = for i <- 1..10 do
  %{"id" => "task_#{i}", "type" => "local", "config" => %{...}}
end

%{
  "nodes" => tasks,
  "edges" => [...],
  "description" => "Dynamically generated with 10 parallel tasks"
}
```

**Features:**
- ✅ **Hot-reloading**: Changes detected automatically every 30s (configurable)
- ✅ **Multiple sources**: Local directory + S3 bucket (both simultaneously)
- ✅ **Change detection**: Only reloads modified DAGs (checksum-based)
- ✅ **Validation**: Comprehensive validation before loading (cycles, types, etc.)
- ✅ **Graceful errors**: Bad DAGs logged, don't crash the loader
- ✅ **Deletion handling**: DAGs automatically disabled when files removed

**Configuration:**
```bash
# Local directory (default: ./dags)
export DAGS_DIR="./dags"

# Scan interval in seconds (default: 30)
export DAGS_SCAN_INTERVAL=30

# Enable/disable (default: true)
export DAGS_ENABLED=true

# Optional: Load from S3
export DAGS_S3_BUCKET="my-dags-bucket"
export DAGS_S3_PREFIX="production/dags/"
```

**See:** [dags/README.md](dags/README.md) and [docs/DAG_LOADING.md](docs/DAG_LOADING.md) for complete documentation.

### Programmatic Loading (Legacy)

You can still load DAGs programmatically if needed:

```elixir
# From Elixir modules
Cascade.Examples.DAGLoader.load_all()

# Or create directly
Cascade.Workflows.create_dag(%{
  name: "my_dag",
  description: "My DAG",
  definition: %{"nodes" => [...], "edges" => [...]},
  enabled: true
})
```

## Triggering Jobs

### Mix Task (CLI)

```bash
# Trigger and wait for completion
mix cascade.trigger cloud_test_pipeline \
  --context '{"input_data": [1,2,3], "multiplier": 5}'

# Trigger and exit immediately
mix cascade.trigger my_pipeline --no-wait
```

### IEx Console

```elixir
# Get DAG
dag = Cascade.Workflows.get_dag_by_name("daily_etl_pipeline")

# Trigger job
{:ok, job} = Cascade.Runtime.Scheduler.trigger_job(
  dag.id,
  "system",
  %{"date" => "2025-12-25"}
)

# Check status
Cascade.Workflows.get_job_with_details!(job.id)
```

### Web UI

Navigate to `http://localhost:4000` or visit the [live demo](https://cascade.nauths.io)

## Monitoring

### Database Queries

```elixir
# List all jobs for a DAG
Cascade.Workflows.list_jobs_for_dag(dag_id)

# Get job details
job = Cascade.Workflows.get_job_with_details!(job_id)

# Get task executions
Cascade.Workflows.list_task_executions_for_job(job_id)
```

### CloudWatch Logs (Lambda)

```bash
# Tail Lambda logs
aws logs tail /aws/lambda/my-function --follow

# Search for specific job
aws logs tail /aws/lambda/my-function --since 1h \
  | grep "job_id_here"
```

### S3 Artifacts

```bash
# List job artifacts
aws s3 ls s3://my-bucket/results/JOB_ID/

# Download result
aws s3 cp s3://my-bucket/results/JOB_ID/task.json -
```

## Configuration

### Environment Variables

```bash
# Database
export DATABASE_URL="ecto://user:pass@localhost/cascade_dev"

# AWS
export AWS_REGION="us-east-2"
export CASCADE_S3_BUCKET="my-cascade-bucket"

# Workers
export CASCADE_WORKERS=16  # Number of worker processes
export CASCADE_NODE_ROLE="both"  # coordinator | worker | both
```

### Application Config

`config/runtime.exs`:
```elixir
config :cascade,
  aws_region: System.get_env("AWS_REGION") || "us-east-1",
  s3_bucket: System.get_env("CASCADE_S3_BUCKET") || "cascade-artifacts",
  default_task_timeout: 300_000  # 5 minutes in ms
```

## Examples

### Example 1: Data Processing Pipeline

```elixir
defmodule MyApp.DataPipeline do
  use Cascade.DSL

  dag "data_processing",
    description: "Process and aggregate data",
    tasks: [
      # Multiply input values
      process: [
        type: :lambda,
        function_name: "data-processor",
        timeout: 60,
        store_output_to_s3: true,
        output_s3_key: "results/{{job_id}}/processed.json"
      ],

      # Aggregate processed values
      aggregate: [
        type: :lambda,
        function_name: "aggregator",
        timeout: 30,
        store_output_to_s3: true,
        output_s3_key: "results/{{job_id}}/final.json",
        depends_on: [:process]
      ]
    ]
end
```

**Trigger with context:**
```bash
mix cascade.trigger data_processing \
  --context '{"input_data": [10, 20, 30], "multiplier": 3}'
```

**Expected flow:**
1. `process` receives `[10, 20, 30]`, multiplies by 3 → `[30, 60, 90]`
2. Result stored to S3
3. `aggregate` downloads from S3, calculates total: 180

### Example 2: ETL Pipeline

See `apps/cascade/lib/cascade/examples/etl_dag.ex` for a complete ETL example with:
- Multiple parallel extraction tasks
- Transformation with data validation
- Loading to data warehouse
- Notification on completion

## Development

### Running Tests

```bash
mix test
```

### Database Migrations

```bash
# Create new migration
mix ecto.gen.migration add_new_field

# Run migrations
mix ecto.migrate

# Rollback
mix ecto.rollback
```

### Production Deployment

Cascade includes complete Terraform configuration for AWS deployment. See [terraform/README.md](terraform/README.md) for detailed setup instructions.

### Quick Start

```bash
cd terraform

# Configure variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your domain, database password, etc.

# Deploy infrastructure
terraform init
terraform apply
```

This creates:
- **ECS Fargate** - Containerized Cascade application
- **Application Load Balancer** - HTTPS with ACM certificate
- **RDS PostgreSQL** - Workflow metadata storage
- **S3 bucket** - Task artifact storage
- **Lambda functions** - Example serverless task executors (data-processor, aggregator)
- **IAM roles** - Secure permissions for ECS and Lambda
- **CloudWatch logs** - Centralized logging

### Post-Deployment

After Terraform completes:

1. **Run database migrations**:
   ```bash
   aws ecs run-task \
     --cluster cascade-cluster \
     --task-definition cascade-app:N \
     --launch-type FARGATE \
     --region us-east-2 \
     --network-configuration "..." \
     --overrides '{"containerOverrides":[{"name":"cascade-app","command":["bin/init","eval","Cascade.Release.migrate()"]}]}'
   ```

2. **Load example DAGs**:
   ```bash
   aws ecs run-task \
     --cluster cascade-cluster \
     --task-definition cascade-app:N \
     --launch-type FARGATE \
     --region us-east-2 \
     --network-configuration "..." \
     --overrides '{"containerOverrides":[{"name":"cascade-app","command":["bin/init","eval","Cascade.Release.load_dags()"]}]}'
   ```

3. **Access the UI**:
   - Navigate to `https://your-domain.com`
   - View the dashboard, browse DAGs, and trigger jobs

See the [Terraform README](terraform/README.md) for complete deployment instructions.

## Architecture Details

### State Management

- **ETS Tables**: In-memory state for active jobs (fast)
- **Postgres**: Persistent storage for job history (durable)
- **PubSub**: Real-time event broadcasting

### Worker Pool

- Default: 2× CPU cores
- Configurable via `CASCADE_WORKERS`
- Atomic task claiming prevents duplicate execution
- Automatic reassignment on worker failure

### Dependency Resolution

- DAG validation at compile time
- Topological sort for ready tasks
- Parallel execution of independent tasks
- Automatic upstream result passing

## Roadmap

### Phase 1: Core Engine ✅ COMPLETE
- DAG DSL and validation
- Local task execution
- State management
- Database persistence

### Phase 2: Distribution 📋 PLANNED
- Erlang clustering
- Worker heartbeat and registration
- Distributed worker coordination
- Cross-node load balancing
- Fault tolerance and worker reassignment

### Phase 3: Cloud Integration ✅ COMPLETE
- AWS Lambda execution
- S3 artifact storage
- Data flow between tasks
- Mix task for job triggering

### Phase 4: LiveView UI ✅ COMPLETE
- Real-time job monitoring
- DAG list and detail views
- Manual job triggers with context
- Job execution tracking
- Task-level execution details

### Phase 5: Advanced Features 🚧 IN PROGRESS
- ✅ **Auto-loading DAGs** - Directory-based with hot-reloading (JSON + Elixir)
- ✅ **S3 DAG source** - Load DAGs from S3 bucket
- 📋 Cron-based scheduling
- 📋 Retry with exponential backoff
- 📋 Task timeout enforcement
- 📋 Error callbacks
- 📋 Job cancellation
- 📋 Authentication/authorization
- 📋 Telemetry/metrics
- 📋 DAG versioning

## Contributing

Contributions welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Write tests for new functionality
4. Submit a pull request

## License

Copyright 2025 Cascade Contributors

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

## Support

- Issues: [GitHub Issues](https://github.com/your-org/cascade/issues)
- Documentation: This README + inline code documentation
- Examples: `apps/cascade/lib/cascade/examples/`

---

Built with ❤️ using Elixir, Phoenix, and AWS
