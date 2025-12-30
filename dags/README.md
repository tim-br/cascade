# DAG Definitions Directory

This directory contains DAG (Directed Acyclic Graph) workflow definitions that are automatically loaded by Cascade.

## How It Works

Cascade's **DagLoader** automatically scans this directory for DAG files and loads them into the database. The loader:

- 🔄 Scans every 30 seconds (configurable via `DAGS_SCAN_INTERVAL`)
- 🔥 Hot-reloads changed DAGs without restart
- ✅ Validates DAGs before loading
- 🗑️ Disables DAGs when files are deleted
- ☁️ Supports loading from S3 buckets

## Supported File Formats

### JSON Files (`.json`)

Simple JSON format for static DAG definitions:

```json
{
  "nodes": [
    {
      "id": "task_1",
      "type": "local",
      "config": {
        "module": "MyApp.Tasks.Task1",
        "timeout": 300
      }
    }
  ],
  "edges": [
    {"from": "task_1", "to": "task_2"}
  ],
  "description": "My DAG description",
  "enabled": true
}
```

### Elixir Config Files (`.exs`)

Use Elixir for dynamic DAG generation:

```elixir
# You can use variables and logic
tasks = for i <- 1..10 do
  %{
    "id" => "task_#{i}",
    "type" => "local",
    "config" => %{"module" => "MyApp.Task"}
  }
end

%{
  "nodes" => tasks,
  "edges" => [],
  "description" => "Dynamically generated DAG"
}
```

## Configuration

Configure via environment variables:

```bash
# Local directory to scan (default: ./dags)
export DAGS_DIR="./dags"

# Scan interval in seconds (default: 30)
export DAGS_SCAN_INTERVAL=30

# Enable/disable auto-loading (default: true)
export DAGS_ENABLED=true

# Optional: S3 bucket for remote DAGs
export DAGS_S3_BUCKET="my-dags-bucket"
export DAGS_S3_PREFIX="dags/"
```

## DAG Structure

### Required Fields

- `nodes`: Array of task nodes
  - Each node must have: `id`, `type`, `config`
- `edges`: Array of dependencies (optional)
  - Each edge: `{"from": "task_1", "to": "task_2"}`

### Optional Fields

- `description`: DAG description (string)
- `enabled`: Enable/disable the DAG (boolean, default: true)

### Task Types

#### Local Tasks
Execute Elixir modules:
```json
{
  "id": "my_task",
  "type": "local",
  "config": {
    "module": "MyApp.Tasks.MyTask",
    "timeout": 300,
    "retry": 3
  }
}
```

#### Lambda Tasks
Execute AWS Lambda functions:
```json
{
  "id": "my_lambda",
  "type": "lambda",
  "config": {
    "function_name": "my-lambda-function",
    "timeout": 300,
    "payload": {
      "key": "value"
    }
  }
}
```

## Examples

See the example DAGs in this directory:

- `example_etl.json` - Simple ETL pipeline
- `lambda_pipeline.json` - Lambda-based workflow
- `advanced_example.exs` - Dynamic DAG generation with Elixir

## Validation

DAGs are validated before loading. The validator checks:

- ✅ Required fields present
- ✅ All nodes have unique IDs
- ✅ All edges reference existing nodes
- ✅ No circular dependencies (cycles)
- ✅ Valid node types and configurations

## Troubleshooting

### DAG Not Loading

Check the logs for validation errors:
```bash
# Look for DAG_LOADER messages
docker logs cascade-app | grep DAG_LOADER
```

### Force Reload

Trigger an immediate scan:
```elixir
# In IEx console
Cascade.DagLoader.scan_now()
```

### Check Status

View loader status:
```elixir
# In IEx console
Cascade.DagLoader.get_status()
```

## S3 Support

To load DAGs from S3:

1. Set environment variables:
   ```bash
   export DAGS_S3_BUCKET="my-bucket"
   export DAGS_S3_PREFIX="production/dags/"
   ```

2. Upload DAG files to S3:
   ```bash
   aws s3 cp my_dag.json s3://my-bucket/production/dags/
   ```

3. DAGs will be automatically loaded on next scan

## Task Implementation Patterns

Cascade supports multiple patterns for implementing tasks, similar to how Airflow handles Python tasks.

### Pattern 1: Built-in Tasks
Use tasks from Cascade's standard library:

```json
{
  "config": {
    "module": "Cascade.Examples.Tasks.ExtractData"
  }
}
```

**Pros:** Simple, works immediately, no dependencies
**Cons:** Limited to built-in tasks

### Pattern 2: Inline Tasks (Airflow-style)
Define task modules directly in `.exs` DAG files:

```elixir
# dags/weather_pipeline.exs

defmodule WeatherTasks.FetchAPI do
  def run(payload) do
    context = Map.get(payload, :context, %{})
    # Implement task logic using Elixir stdlib
    {:ok, %{"temperature" => 72, "city" => "Seattle"}}
  end
end

# Return DAG definition
%{
  "nodes" => [
    %{"id" => "fetch", "type" => "local",
      "config" => %{"module" => "WeatherTasks.FetchAPI", "timeout" => 60}}
  ],
  "edges" => [],
  "description" => "Weather pipeline with inline tasks"
}
```

**Pros:** Tasks live with DAG, great for simple logic, hot-reload supported
**Cons:** Limited to Elixir stdlib (no external dependencies)

### Pattern 3: Shared Task Library (Recommended)
Create reusable task modules across DAGs:

```elixir
# dags/_shared_tasks.exs (underscore prefix loads first)

defmodule SharedTasks.DataPipeline do
  defmodule FetchFromAPI do
    def run(payload) do
      # Reusable logic here
      {:ok, data}
    end
  end

  defmodule ValidateData do
    def run(payload) do
      # Reusable logic here
      {:ok, validated}
    end
  end
end

# Return nil (library file, not a DAG)
nil
```

Use in any DAG (JSON or .exs):

```json
{
  "nodes": [
    {"id": "fetch", "config": {"module": "SharedTasks.DataPipeline.FetchFromAPI"}},
    {"id": "validate", "config": {"module": "SharedTasks.DataPipeline.ValidateData"}}
  ]
}
```

**Pros:** DRY principle, centralized task logic, reusable across DAGs
**Cons:** Still limited to Elixir stdlib
**Tip:** Use `_` prefix (e.g., `_shared_tasks.exs`) to ensure library loads before DAGs

### Pattern 4: Custom Docker Image (For External Dependencies)

For tasks requiring external libraries (HTTPoison, Timex, database clients), build a custom Docker image:

```dockerfile
# Dockerfile.custom
FROM ghcr.io/tim-br/cascade:latest

# Add your task modules with dependencies
COPY lib/my_company_tasks /app/lib/my_company_tasks

# Install dependencies
WORKDIR /app
RUN mix deps.get && mix compile
```

Build and run:
```bash
docker build -f Dockerfile.custom -t cascade-custom .
docker run -p 4000:4000 -v ./dags:/app/dags cascade-custom
```

DAGs can now reference custom modules:
```json
{
  "config": {"module": "MyCompanyTasks.AdvancedProcessor"}
}
```

**Pros:** Full access to Hex ecosystem, production-ready, fast DAG loading
**Cons:** Requires Docker rebuild for task changes, less dynamic

### Pattern 5: Mix Project in dags/ ⚠️ Future

⚠️ **Not yet implemented** - planned for future release

```
dags/
  mix.exs              # Define task dependencies
  lib/
    my_tasks.ex        # Use HTTPoison, Timex, etc.
  my_pipeline.json
```

**Status:** Under consideration. Challenges include:
- Hot-reload becomes slow (compilation required)
- Dependency version conflicts with main app
- Code loading complexity

**Workaround:** Use Pattern 4 (custom Docker image) for now

## Comparison with Airflow

| Feature | Airflow | Cascade |
|---------|---------|---------|
| DAG Format | Python files | JSON or Elixir (.exs) |
| Task Imports | `from my_tasks import fetch` | Shared .exs files with `_` prefix |
| Inline Tasks | Define in DAG file | Define in .exs DAG file |
| Dependencies | Build custom Docker image | Build custom Docker image |
| Auto-install deps from dags/ | ❌ No | ❌ No (use Docker) |
| Hot-reload | Yes (scheduler restart) | Yes (automatic, ~30s) |
| DAG deletion | Keeps in DB, hides from UI | Keeps in DB, sets `enabled: false` |

Both philosophies align: keep DAG directory simple, use Docker for dependencies.

## Best Practices

1. **Use meaningful names**: File name becomes DAG name
2. **Version control**: Keep DAG files in git
3. **Test locally**: Validate DAGs before deploying
4. **Use `.exs` for complex logic**: Dynamic generation when needed
5. **Keep it simple**: Prefer JSON for static workflows
6. **Add descriptions**: Document what each DAG does
7. **Set appropriate timeouts**: Based on task complexity
8. **Share common tasks**: Use `_shared_tasks.exs` pattern
9. **Use `_` prefix for libraries**: Ensures load order

## Migration from Mix Tasks

If you were using `mix cascade.load_dag`, simply:

1. Move your DAG JSON files to this directory
2. Remove manual `mix cascade.load_dag` calls
3. DAGs will auto-load on application start
