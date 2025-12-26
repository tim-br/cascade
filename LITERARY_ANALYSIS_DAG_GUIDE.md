# Literary Analysis DAG - Demo Guide

## Overview

This is a complex cloud-only DAG that demonstrates Cascade's capabilities with a realistic text processing pipeline. It analyzes two books from Project Gutenberg using 9 Lambda functions with parallel processing and intentional failures for testing error handling.

## DAG Architecture

```
fetch_book_1 ──> extract_chapters_1 ──┬──> word_frequency_1 ───┐
                                      │                        │
                                      └──> sentiment_analysis_1*┤
                                                                ├──> compare_results
fetch_book_2 ──> extract_chapters_2 ──┬──> word_frequency_2 ───┤
                                      │                        │
                                      └──> sentiment_analysis_2*┘

* = Includes periodic failures (sentiment_analysis_1: 30%, sentiment_analysis_2: 15%)
```

## Tasks (9 Lambda Functions)

### Stage 1: Data Ingestion (Parallel)
1. **fetch_book_1** - Fetches first book from Project Gutenberg
2. **fetch_book_2** - Fetches second book from Project Gutenberg

### Stage 2: Text Processing (Parallel)
3. **extract_chapters_1** - Splits book 1 into chapters
4. **extract_chapters_2** - Splits book 2 into chapters

### Stage 3: Analysis (Parallel, Fan-out)
5. **word_frequency_1** - Analyzes word frequency in book 1
6. **word_frequency_2** - Analyzes word frequency in book 2
7. **sentiment_analysis_1** - Analyzes sentiment in book 1 (⚠️ 30% failure rate)
8. **sentiment_analysis_2** - Analyzes sentiment in book 2 (⚠️ 15% failure rate)

### Stage 4: Aggregation (Fan-in)
9. **compare_results** - Compares and aggregates results from both books

## Input Parameters

The DAG accepts the following context parameters:

- **book1_id**: Project Gutenberg book ID (default: "1342" - Pride and Prejudice)
- **book2_id**: Project Gutenberg book ID (default: "11" - Alice in Wonderland)
- **analysis_depth**: "basic" or "detailed" (default: "basic")

### Available Book IDs:
- `1342` - Pride and Prejudice by Jane Austen
- `11` - Alice's Adventures in Wonderland by Lewis Carroll
- `84` - Frankenstein by Mary Shelley
- `1661` - The Adventures of Sherlock Holmes by Arthur Conan Doyle

## How to Use

### 1. Load the DAG (if not already loaded)

```bash
mix run load_literary_dag.exs
```

Or from IEx:

```elixir
alias Cascade.Examples.DAGLoader
DAGLoader.load_literary_analysis_dag()
```

### 2. Trigger a Job

From IEx:

```elixir
# Using defaults (Pride and Prejudice vs Alice in Wonderland)
{:ok, dag} = Cascade.Workflows.get_dag_by_name("literary_analysis_pipeline")
Cascade.Runtime.Scheduler.trigger_job(dag.id, "demo_user", %{})

# With custom books
Cascade.Runtime.Scheduler.trigger_job(dag.id, "demo_user", %{
  "book1_id" => "84",    # Frankenstein
  "book2_id" => "1661",  # Sherlock Holmes
  "analysis_depth" => "detailed"
})
```

### 3. Monitor Job Execution

```elixir
# Get job state
{:ok, job_state} = Cascade.Runtime.StateManager.get_job_state(job_id)

# View all jobs for the DAG
Cascade.Workflows.list_jobs_for_dag(dag.id)
```

## Failure Handling (Airflow-Style)

Cascade currently handles failures **like Airflow's default behavior**:

### Current Behavior:
- ✅ When a task fails, the **entire job is marked as failed**
- ✅ Downstream tasks are **NOT executed** after a failure
- ✅ Failed tasks are recorded with error details
- ✅ Job failure events are published for monitoring

### What Happens When sentiment_analysis_1 Fails:
1. `sentiment_analysis_1` fails with a random error (30% chance)
2. The entire job is immediately marked as `:failed`
3. `compare_results` does **NOT run** (missing dependency)
4. Job state is removed from active processing
5. Job record in Postgres shows `status: :failed`

This matches Airflow's behavior when:
- No retries are configured
- No trigger rules are set (default is `all_success`)

### Observing Failures

The `sentiment_analysis.py` Lambda includes these simulated failures:
- Model timeout errors
- Out of memory errors
- API rate limit errors
- Invalid input errors
- Service unavailable errors

Each failure includes detailed error information in the response.

## Lambda Functions

All Lambda functions are located in `terraform/lambda_functions/`:

- `fetch_book.py` - Book fetching logic
- `extract_chapters.py` - Chapter extraction
- `word_frequency.py` - Word frequency analysis
- `sentiment_analysis.py` - Sentiment analysis (with failures)
- `compare_books.py` - Results comparison

## Deploying Lambda Functions

To deploy these functions to AWS:

1. Zip each Lambda function:
```bash
cd terraform/lambda_functions
zip fetch_book.zip fetch_book.py
zip extract_chapters.zip extract_chapters.py
zip word_frequency.zip word_frequency.py
zip sentiment_analysis.zip sentiment_analysis.py
zip compare_books.zip compare_books.py
```

2. Update terraform configuration to include these functions

3. Deploy with terraform:
```bash
cd terraform
terraform apply
```

## Expected Results

### Successful Run:
- All 9 tasks complete
- Results stored in S3 at `literary-analysis/{job_id}/`
- Final comparison report generated
- Job status: `:success`

### Failed Run (when sentiment_analysis fails):
- First ~4-5 tasks complete successfully
- One sentiment_analysis task fails
- Remaining tasks are NOT executed
- Job status: `:failed`
- Error details captured in job record

## Testing Recommendations

1. **Run multiple times** to observe different failure scenarios
2. **Try different book combinations** using input parameters
3. **Monitor the web UI** to see task progression and failures
4. **Check S3 outputs** to see intermediate results before failure
5. **Review error logs** to see different failure types

## Future Enhancements

Potential additions to match more Airflow features:

- ✨ **Retries**: Automatic retry of failed tasks
- ✨ **Trigger Rules**: Different dependency behaviors (`all_done`, `one_failed`, etc.)
- ✨ **Task timeouts**: Explicit timeout handling
- ✨ **SLA monitoring**: Track task/job duration
- ✨ **Branching**: Conditional task execution based on results

## Comparison with Airflow

| Feature | Airflow | Cascade (Current) |
|---------|---------|-------------------|
| DAG Definition | Python code | Elixir DSL |
| Task Execution | Celery/K8s | Lambda + Local |
| State Storage | Postgres | ETS + Postgres |
| Failure Handling | Configurable | Fail entire job |
| Retries | ✅ Built-in | ❌ Not yet |
| Trigger Rules | ✅ Multiple options | ❌ Only all_success |
| Parallel Execution | ✅ Yes | ✅ Yes |
| Web UI | ✅ Full featured | ✅ Basic (Phoenix LiveView) |
| Cloud Integration | Plugins | ✅ Native (Lambda, S3) |

---

**Created**: 2024-12-26
**DAG Name**: `literary_analysis_pipeline`
**Total Tasks**: 9
**Type**: Cloud-only (100% Lambda)
