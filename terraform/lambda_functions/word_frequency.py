"""
Cascade Word Frequency Lambda Function

Analyzes word frequency in literary texts.
"""

import json
import time
import os
from datetime import datetime
from collections import Counter

def lambda_handler(event, context):
    """
    Analyze word frequency in a book.

    Expected event structure:
    {
        "job_id": "job-uuid",
        "task_id": "word_frequency_1",
        "context": {
            "input_s3_key": "literary-analysis/{job_id}/book1_chapters.json",
            "top_n": 500,
            "analysis_depth": "basic"
        },
        "config": {
            "top_n": 500,
            "analysis_depth": "basic"
        }
    }
    """

    print(f"Word Frequency invoked with event: {json.dumps(event)}")

    job_id = event.get('job_id', 'unknown')
    task_id = event.get('task_id', 'unknown')
    event_context = event.get('context', {})
    config = event.get('config', {})
    # Payload is nested in config['config']['payload']
    task_config = config.get('config', {})
    payload = task_config.get('payload', {})

    input_s3_key = event_context.get('input_s3_key') or payload.get('input_s3_key', '')
    top_n = int(event_context.get('top_n', payload.get('top_n', 500)))
    analysis_depth = event_context.get('analysis_depth', payload.get('analysis_depth', 'basic'))

    print(f"Analyzing word frequency from {input_s3_key} for job {job_id}, task {task_id}")
    print(f"Parameters: top_n={top_n}, analysis_depth={analysis_depth}")

    try:
        # Simulate reading from S3 and analyzing word frequency
        # In a real implementation, this would read chapter data from S3

        # Simulate processing time based on depth
        processing_time = 3 if analysis_depth == "detailed" else 2
        time.sleep(processing_time)

        # Mock word frequency data
        word_frequencies = {
            "the": 5234,
            "and": 3821,
            "to": 3142,
            "of": 2987,
            "a": 2654,
            "in": 2103,
            "that": 1876,
            "was": 1654,
            "he": 1523,
            "his": 1402,
            "with": 1289,
            "as": 1187,
            "for": 1098,
            "on": 987,
            "at": 876,
            "be": 765,
            "by": 654,
            "not": 598,
            "from": 543,
            "her": 512
        }

        total_words = sum(word_frequencies.values())
        unique_words = len(word_frequencies)

        # Additional analysis for detailed mode
        additional_metrics = {}
        if analysis_depth == "detailed":
            additional_metrics = {
                "avg_word_length": 4.7,
                "lexical_diversity": 0.342,
                "most_common_word_length": 3,
                "proper_nouns_count": 234
            }

        result = {
            "job_id": job_id,
            "task_id": task_id,
            "status": "success",
            "input_s3_key": input_s3_key,
            "total_words": total_words,
            "unique_words": unique_words,
            "top_words": word_frequencies,
            "analysis_depth": analysis_depth,
            "processing_time_seconds": processing_time,
            **additional_metrics,
            "output_location": f"s3://{os.environ.get('BUCKET_NAME', 'cascade-artifacts')}/{input_s3_key.replace('chapters.json', 'word_freq.json')}",
            "analyzed_at": datetime.utcnow().isoformat()
        }

        print(f"Word frequency analysis complete: {unique_words} unique words, {total_words} total")

        return {
            "statusCode": 200,
            "body": result
        }

    except Exception as e:
        error_msg = f"Failed to analyze word frequency: {str(e)}"
        print(f"ERROR: {error_msg}")

        # Re-raise the exception so Lambda properly marks it as failed
        # Don't return statusCode: 500 as that doesn't signal failure to Lambda
        raise
