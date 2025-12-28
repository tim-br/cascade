"""
Cascade Extract Chapters Lambda Function

Extracts chapters from book text for further analysis.
"""

import json
import time
import os
import re
from datetime import datetime

def lambda_handler(event, context):
    """
    Extract chapters from a book.

    Expected event structure:
    {
        "job_id": "job-uuid",
        "task_id": "extract_chapters_1",
        "context": {
            "input_s3_key": "literary-analysis/{job_id}/book1_raw.txt"
        },
        "config": {
            "input_s3_key": "..."
        }
    }
    """

    print(f"Extract Chapters invoked with event: {json.dumps(event)}")

    job_id = event.get('job_id', 'unknown')
    task_id = event.get('task_id', 'unknown')
    event_context = event.get('context', {})
    config = event.get('config', {})
    # Payload is nested in config['config']['payload']
    task_config = config.get('config', {})
    payload = task_config.get('payload', {})

    input_s3_key = event_context.get('input_s3_key') or payload.get('input_s3_key', '')

    print(f"Extracting chapters from {input_s3_key} for job {job_id}, task {task_id}")

    try:
        # Simulate reading from S3 and extracting chapters
        # In a real implementation, this would read from S3

        # Simulate processing time
        time.sleep(2)

        # Mock chapter extraction
        chapters = [
            {
                "chapter_num": 1,
                "title": "Chapter I",
                "word_count": 1523,
                "paragraph_count": 12
            },
            {
                "chapter_num": 2,
                "title": "Chapter II",
                "word_count": 1842,
                "paragraph_count": 15
            },
            {
                "chapter_num": 3,
                "title": "Chapter III",
                "word_count": 1654,
                "paragraph_count": 13
            },
            {
                "chapter_num": 4,
                "title": "Chapter IV",
                "word_count": 2103,
                "paragraph_count": 18
            },
            {
                "chapter_num": 5,
                "title": "Chapter V",
                "word_count": 1789,
                "paragraph_count": 14
            }
        ]

        total_words = sum(ch['word_count'] for ch in chapters)

        result = {
            "job_id": job_id,
            "task_id": task_id,
            "status": "success",
            "input_s3_key": input_s3_key,
            "total_chapters": len(chapters),
            "total_words": total_words,
            "chapters": chapters,
            "output_location": f"s3://{os.environ.get('BUCKET_NAME', 'cascade-artifacts')}/{input_s3_key.replace('raw.txt', 'chapters.json')}",
            "extracted_at": datetime.utcnow().isoformat()
        }

        print(f"Chapter extraction complete: extracted {len(chapters)} chapters, {total_words} words")

        return {
            "statusCode": 200,
            "body": result
        }

    except Exception as e:
        error_msg = f"Failed to extract chapters: {str(e)}"
        print(f"ERROR: {error_msg}")

        # Re-raise the exception so Lambda properly marks it as failed
        # Don't return statusCode: 500 as that doesn't signal failure to Lambda
        raise
