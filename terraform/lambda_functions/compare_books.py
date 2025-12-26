"""
Cascade Compare Books Lambda Function

Compares analysis results from multiple books.
"""

import json
import time
import os
from datetime import datetime

def lambda_handler(event, context):
    """
    Compare analysis results from multiple books.

    Expected event structure:
    {
        "job_id": "job-uuid",
        "task_id": "compare_results",
        "context": {
            "book1_word_freq": "literary-analysis/{job_id}/book1_word_freq.json",
            "book2_word_freq": "literary-analysis/{job_id}/book2_word_freq.json",
            "book1_sentiment": "literary-analysis/{job_id}/book1_sentiment.json",
            "book2_sentiment": "literary-analysis/{job_id}/book2_sentiment.json",
            "generate_visualizations": true
        },
        "config": {
            "generate_visualizations": true
        }
    }
    """

    print(f"Compare Books invoked with event: {json.dumps(event)}")

    job_id = event.get('job_id', 'unknown')
    task_id = event.get('task_id', 'unknown')
    event_context = event.get('context', {})
    config = event.get('config', {})
    # Payload is nested in config['config']['payload']
    task_config = config.get('config', {})
    payload = task_config.get('payload', {})

    # Get input S3 keys
    book1_word_freq = event_context.get('book1_word_freq') or payload.get('book1_word_freq', '')
    book2_word_freq = event_context.get('book2_word_freq') or payload.get('book2_word_freq', '')
    book1_sentiment = event_context.get('book1_sentiment') or payload.get('book1_sentiment', '')
    book2_sentiment = event_context.get('book2_sentiment') or payload.get('book2_sentiment', '')
    generate_viz = event_context.get('generate_visualizations', payload.get('generate_visualizations', False))

    print(f"Comparing books for job {job_id}, task {task_id}")
    print(f"Inputs: word_freq_1={book1_word_freq}, word_freq_2={book2_word_freq}")
    print(f"        sentiment_1={book1_sentiment}, sentiment_2={book2_sentiment}")
    print(f"Generate visualizations: {generate_viz}")

    try:
        # Simulate reading from S3 and comparing results
        # In a real implementation, this would read all analysis results from S3

        # Simulate processing time
        time.sleep(2)

        # Mock comparison results
        comparison = {
            "word_frequency_comparison": {
                "book1": {
                    "total_words": 89234,
                    "unique_words": 5432,
                    "lexical_diversity": 0.342
                },
                "book2": {
                    "total_words": 76543,
                    "unique_words": 4987,
                    "lexical_diversity": 0.389
                },
                "common_top_words": ["the", "and", "to", "of", "a"],
                "distinctive_words_book1": ["gentleman", "lady", "estate", "fortune"],
                "distinctive_words_book2": ["wonderland", "rabbit", "queen", "curious"]
            },
            "sentiment_comparison": {
                "book1": {
                    "overall_sentiment": "positive",
                    "sentiment_score": 0.189,
                    "positive_ratio": 0.43
                },
                "book2": {
                    "overall_sentiment": "positive",
                    "sentiment_score": 0.234,
                    "positive_ratio": 0.47
                },
                "sentiment_variance": {
                    "book1_variance": 0.045,
                    "book2_variance": 0.067
                },
                "comparison": "Book 2 is slightly more positive and has higher emotional variance"
            },
            "statistical_analysis": {
                "word_count_difference": 12691,
                "vocabulary_overlap": 0.67,
                "sentiment_correlation": 0.34,
                "complexity_comparison": "Book 1 has lower lexical diversity, suggesting simpler vocabulary"
            }
        }

        # Add visualization info if requested
        visualizations = []
        if generate_viz:
            visualizations = [
                {
                    "type": "word_cloud",
                    "book": "both",
                    "s3_key": f"literary-analysis/{job_id}/viz/word_clouds.png"
                },
                {
                    "type": "sentiment_timeline",
                    "book": "both",
                    "s3_key": f"literary-analysis/{job_id}/viz/sentiment_timeline.png"
                },
                {
                    "type": "vocabulary_venn",
                    "book": "both",
                    "s3_key": f"literary-analysis/{job_id}/viz/vocabulary_overlap.png"
                }
            ]

        result = {
            "job_id": job_id,
            "task_id": task_id,
            "status": "success",
            "inputs": {
                "book1_word_freq": book1_word_freq,
                "book2_word_freq": book2_word_freq,
                "book1_sentiment": book1_sentiment,
                "book2_sentiment": book2_sentiment
            },
            "comparison": comparison,
            "visualizations": visualizations,
            "summary": "Comparison completed successfully. Both books show positive sentiment, with Book 2 slightly more positive. Book 1 uses simpler vocabulary despite being longer.",
            "output_location": f"s3://{os.environ.get('BUCKET_NAME', 'cascade-artifacts')}/literary-analysis/{job_id}/comparison_report.json",
            "compared_at": datetime.utcnow().isoformat()
        }

        print(f"Book comparison complete")

        return {
            "statusCode": 200,
            "body": result
        }

    except Exception as e:
        error_msg = f"Failed to compare books: {str(e)}"
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
