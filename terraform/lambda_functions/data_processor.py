"""
Cascade Data Processor Lambda Function

Simulates processing a chunk of data.
In a real scenario, this would:
- Read input data from S3
- Process/transform the data
- Write results back to S3
"""

import json
import time
import os
from datetime import datetime

def lambda_handler(event, context):
    """
    Process data chunk.

    Expected event structure (from Cascade):
    {
        "job_id": "job-uuid",
        "task_id": "process_chunk_1",
        "context": {...},
        "config": {...},
        "timestamp": "ISO8601"
    }
    """

    print(f"Data Processor invoked with event: {json.dumps(event)}")

    job_id = event.get('job_id', 'unknown')
    task_id = event.get('task_id', 'unknown')
    context = event.get('context', {})
    config = event.get('config', {})

    # Extract input parameters from context
    input_data = context.get('input_data', [])
    multiplier = context.get('multiplier', 1)

    print(f"Processing data for job {job_id}, task {task_id}")
    print(f"Input data: {input_data}, Multiplier: {multiplier}")

    # Actually process the input data
    processing_time = config.get('processing_time', 2)
    time.sleep(processing_time)

    # Process each input value by multiplying
    processed_values = [x * multiplier for x in input_data]
    total = sum(processed_values)

    # Build real results based on input
    result = {
        "job_id": job_id,
        "task_id": task_id,
        "status": "success",
        "input_received": {
            "data": input_data,
            "multiplier": multiplier
        },
        "processed_values": processed_values,
        "total": total,
        "count": len(processed_values),
        "processing_time_seconds": processing_time,
        "output_location": f"s3://{os.environ.get('BUCKET_NAME', 'cascade-artifacts')}/results/{job_id}/{task_id}.json",
        "completed_at": datetime.utcnow().isoformat()
    }

    print(f"Processing complete: {json.dumps(result)}")

    return {
        "statusCode": 200,
        "body": result
    }
