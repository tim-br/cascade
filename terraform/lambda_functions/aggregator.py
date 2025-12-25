"""
Cascade Aggregator Lambda Function

Aggregates results from multiple data processing tasks.
In a real scenario, this would:
- Read results from multiple S3 locations
- Aggregate/combine the data
- Generate summary statistics
- Write aggregated results to S3
"""

import json
import time
import os
from datetime import datetime
import boto3

s3_client = boto3.client('s3')

def lambda_handler(event, context):
    """
    Aggregate results from multiple processors.

    Expected event structure (from Cascade):
    {
        "job_id": "job-uuid",
        "task_id": "aggregate_results",
        "context": {...},
        "config": {...},
        "timestamp": "ISO8601"
    }
    """

    print(f"Aggregator invoked with event: {json.dumps(event)}")

    job_id = event.get('job_id', 'unknown')
    task_id = event.get('task_id', 'unknown')
    context_data = event.get('context', {})

    # Get upstream results from context
    upstream_results = context_data.get('upstream_results', {})
    print(f"Upstream results metadata: {json.dumps(upstream_results)}")

    # Download and aggregate upstream data
    aggregated_values = []
    upstream_count = 0

    for upstream_task_id, upstream_info in upstream_results.items():
        print(f"Processing upstream task: {upstream_task_id}")

        # Get S3 location from upstream result
        s3_key = upstream_info.get('result_s3_key')

        if s3_key:
            # Download the actual data from S3
            bucket = os.environ.get('BUCKET_NAME', 'cascade-artifacts-demo')
            print(f"Downloading s3://{bucket}/{s3_key}")

            try:
                response = s3_client.get_object(Bucket=bucket, Key=s3_key)
                upstream_data = json.loads(response['Body'].read().decode('utf-8'))
                print(f"Downloaded upstream data: {json.dumps(upstream_data)}")

                # Extract processed values from upstream
                if 'processed_values' in upstream_data:
                    aggregated_values.extend(upstream_data['processed_values'])
                    upstream_count += 1

            except Exception as e:
                print(f"Error downloading from S3: {str(e)}")

    print(f"Aggregating {len(aggregated_values)} values from {upstream_count} upstream tasks")
    time.sleep(1)

    # Calculate real aggregated results
    grand_total = sum(aggregated_values) if aggregated_values else 0
    avg_value = grand_total / len(aggregated_values) if aggregated_values else 0
    min_value = min(aggregated_values) if aggregated_values else 0
    max_value = max(aggregated_values) if aggregated_values else 0

    result = {
        "job_id": job_id,
        "task_id": task_id,
        "status": "success",
        "aggregation": {
            "upstream_tasks_processed": upstream_count,
            "total_values": len(aggregated_values),
            "grand_total": grand_total,
            "average": avg_value,
            "min": min_value,
            "max": max_value
        },
        "all_values": aggregated_values,
        "output_location": f"s3://{os.environ.get('BUCKET_NAME', 'cascade-artifacts')}/results/{job_id}/aggregated.json",
        "completed_at": datetime.utcnow().isoformat()
    }

    print(f"Aggregation complete: {json.dumps(result)}")

    return {
        "statusCode": 200,
        "body": result
    }
