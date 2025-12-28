"""
Cascade Sentiment Analysis Lambda Function

Analyzes sentiment in literary texts.

This function includes INTENTIONAL PERIODIC FAILURES for testing Cascade's error handling.
"""

import json
import time
import os
import random
from datetime import datetime


def lambda_handler(event, context):
    """
    Analyze sentiment in a book.

    Expected event structure:
    {
        "job_id": "job-uuid",
        "task_id": "sentiment_analysis_1",
        "context": {
            "input_s3_key": "literary-analysis/{job_id}/book1_chapters.json",
            "failure_rate": 0.3,  # 30% chance to fail
            "model": "sentiment-v2"
        },
        "config": {
            "failure_rate": 0.3,
            "model": "sentiment-v2"
        }
    }
    """

    # print(f"Sentiment Analysis invoked with event: {json.dumps(event)}")

    job_id = event.get('job_id', 'unknown')
    task_id = event.get('task_id', 'unknown')
    event_context = event.get('context', {})
    config = event.get('config', {})
    # Payload is nested in config['config']['payload']
    task_config = config.get('config', {})
    payload = task_config.get('payload', {})

    input_s3_key = event_context.get(
        'input_s3_key') or payload.get('input_s3_key', '')
    failure_rate = float(event_context.get(
        'failure_rate', payload.get('failure_rate', 0.0)))
    model = event_context.get('model', payload.get('model', 'sentiment-v1'))

    # print(
    #     f"Analyzing sentiment from {input_s3_key} for job {job_id}, task {task_id}")
    # print(f"Parameters: model={model}, failure_rate={failure_rate}")

    # INTENTIONAL FAILURE SIMULATION
    # This simulates real-world failures like API timeouts, model errors, etc.
    if random.random() < failure_rate:
        error_types = [
            "Model timeout: Sentiment analysis model did not respond within 30s",
            "Insufficient memory: OOM error during batch processing",
            "API rate limit exceeded: Too many requests to sentiment API",
            "Invalid input: Chapter text contains unsupported characters",
            "Model unavailable: Sentiment model service temporarily unavailable"
        ]
        error_msg = random.choice(error_types)

        print(f"SIMULATED FAILURE: {error_msg} for job {job_id} and {task_id}")
        print(f"This failure was intentional (failure_rate={failure_rate})")

        # Raise exception to properly signal Lambda failure
        # When Lambda catches an unhandled exception, it sets X-Amz-Function-Error header
        # which Cascade detects as a task failure
        raise Exception(f"SIMULATED_FAILURE: {error_msg}")

    try:
        # Simulate reading from S3 and analyzing sentiment
        # In a real implementation, this would read chapter data from S3

        # Simulate longer processing time for sentiment analysis
        time.sleep(3)

        # Mock sentiment analysis results
        chapter_sentiments = [
            {"chapter": 1, "positive": 0.45, "negative": 0.25,
                "neutral": 0.30, "overall": "positive"},
            {"chapter": 2, "positive": 0.35, "negative": 0.40,
                "neutral": 0.25, "overall": "negative"},
            {"chapter": 3, "positive": 0.50, "negative": 0.20,
                "neutral": 0.30, "overall": "positive"},
            {"chapter": 4, "positive": 0.30, "negative": 0.50,
                "neutral": 0.20, "overall": "negative"},
            {"chapter": 5, "positive": 0.55, "negative": 0.15,
                "neutral": 0.30, "overall": "positive"}
        ]

        # Aggregate sentiment
        avg_positive = sum(ch['positive']
                           for ch in chapter_sentiments) / len(chapter_sentiments)
        avg_negative = sum(ch['negative']
                           for ch in chapter_sentiments) / len(chapter_sentiments)
        avg_neutral = sum(ch['neutral']
                          for ch in chapter_sentiments) / len(chapter_sentiments)

        overall_sentiment = "positive" if avg_positive > avg_negative else "negative"

        result = {
            "job_id": job_id,
            "task_id": task_id,
            "status": "success",
            "input_s3_key": input_s3_key,
            "model": model,
            "total_chapters_analyzed": len(chapter_sentiments),
            "chapter_sentiments": chapter_sentiments,
            "aggregate_sentiment": {
                "positive": round(avg_positive, 3),
                "negative": round(avg_negative, 3),
                "neutral": round(avg_neutral, 3),
                "overall": overall_sentiment
            },
            "sentiment_score": round(avg_positive - avg_negative, 3),
            "output_location": f"s3://{os.environ.get('BUCKET_NAME', 'cascade-artifacts')}/{input_s3_key.replace('chapters.json', 'sentiment.json')}",
            "analyzed_at": datetime.utcnow().isoformat(),
            "note": f"Executed successfully (failure_rate was {failure_rate})"
        }

        # print(
        #     f"Sentiment analysis complete: overall={overall_sentiment}, score={result['sentiment_score']}")

        return {
            "statusCode": 200,
            "body": result
        }

    except Exception as e:
        error_msg = f"Failed to analyze sentiment: {str(e)}"
        print(f"ERROR: {error_msg}")

        # Re-raise the exception so Lambda properly marks it as failed
        # Don't return statusCode: 500 as that doesn't signal failure to Lambda
        raise
