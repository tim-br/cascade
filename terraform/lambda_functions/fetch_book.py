"""
Cascade Fetch Book Lambda Function

Fetches books from Project Gutenberg for literary analysis.
"""

import json
import time
import os
import urllib.request
from datetime import datetime

def lambda_handler(event, context):
    """
    Fetch a book from Project Gutenberg.

    Expected event structure:
    {
        "job_id": "job-uuid",
        "task_id": "fetch_book_1",
        "context": {
            "book_id": "1342",  # Project Gutenberg book ID
            "source": "gutenberg"
        },
        "config": {
            "book_id": "1342"
        }
    }
    """

    print(f"Fetch Book invoked with event: {json.dumps(event)}")

    job_id = event.get('job_id', 'unknown')
    task_id = event.get('task_id', 'unknown')
    event_context = event.get('context', {})
    config = event.get('config', {})

    # Get book ID from context or config (context takes precedence)
    book_id = event_context.get('book_id') or config.get('book_id', '1342')
    source = event_context.get('source', 'gutenberg')

    print(f"Fetching book {book_id} from {source} for job {job_id}, task {task_id}")

    try:
        # Simulate fetching from Project Gutenberg
        # In a real implementation, this would use: https://www.gutenberg.org/files/{book_id}/{book_id}-0.txt
        url = f"https://www.gutenberg.org/files/{book_id}/{book_id}-0.txt"

        # For demo purposes, we'll create sample content rather than actually downloading
        # (to avoid network dependencies in Lambda)
        sample_texts = {
            "1342": "Pride and Prejudice by Jane Austen\n\nIt is a truth universally acknowledged...",
            "11": "Alice's Adventures in Wonderland by Lewis Carroll\n\nDown the rabbit hole...",
            "84": "Frankenstein by Mary Shelley\n\nYou will rejoice to hear that no disaster has accompanied...",
            "1661": "Sherlock Holmes by Arthur Conan Doyle\n\nTo Sherlock Holmes she is always the woman..."
        }

        book_content = sample_texts.get(book_id, f"Sample book content for book ID {book_id}")

        # Simulate some processing time
        time.sleep(1)

        # Get book metadata
        book_titles = {
            "1342": "Pride and Prejudice",
            "11": "Alice's Adventures in Wonderland",
            "84": "Frankenstein",
            "1661": "The Adventures of Sherlock Holmes"
        }

        result = {
            "job_id": job_id,
            "task_id": task_id,
            "status": "success",
            "book_id": book_id,
            "title": book_titles.get(book_id, f"Book {book_id}"),
            "source": source,
            "content_length": len(book_content),
            "content_preview": book_content[:200] + "...",
            "output_location": f"s3://{os.environ.get('BUCKET_NAME', 'cascade-artifacts')}/literary-analysis/{job_id}/book_{book_id}_raw.txt",
            "fetched_at": datetime.utcnow().isoformat()
        }

        print(f"Book fetch complete: {json.dumps(result)}")

        return {
            "statusCode": 200,
            "body": result
        }

    except Exception as e:
        error_msg = f"Failed to fetch book {book_id}: {str(e)}"
        print(f"ERROR: {error_msg}")

        return {
            "statusCode": 500,
            "body": {
                "job_id": job_id,
                "task_id": task_id,
                "status": "failed",
                "error": error_msg
            }
        }
