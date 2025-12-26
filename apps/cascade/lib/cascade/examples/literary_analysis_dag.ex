defmodule Cascade.Examples.LiteraryAnalysisDAG do
  @moduledoc """
  Complex literary analysis pipeline for processing multiple books.

  This DAG demonstrates:
  - Parallel data ingestion (fetching books from Project Gutenberg)
  - Parallel text processing (extracting chapters)
  - Multiple independent analysis tasks (word frequency, sentiment)
  - Fan-in aggregation pattern (comparing results)
  - Periodic failures for testing error handling
  - Input parameters for book selection

  Architecture:
  ```
  fetch_book_1 ──> extract_chapters_1 ──┬──> word_frequency_1 ───┐
                                        │                        │
                                        └──> sentiment_analysis_1 ┤
                                                                  ├──> compare_results
  fetch_book_2 ──> extract_chapters_2 ──┬──> word_frequency_2 ───┤
                                        │                        │
                                        └──> sentiment_analysis_2 ┘
  ```

  Input Parameters:
  - book1_id: Project Gutenberg book ID (default: 1342 - Pride and Prejudice)
  - book2_id: Project Gutenberg book ID (default: 11 - Alice in Wonderland)
  - analysis_depth: "basic" or "detailed"
  """

  use Cascade.DSL

  dag "literary_analysis_pipeline",
    description: "Complex literary analysis pipeline with parallel processing and intentional failures",
    schedule: nil,  # Manual trigger only for testing
    tasks: [
      # Stage 1: Fetch books from Project Gutenberg (parallel)
      fetch_book_1: [
        type: :lambda,
        function_name: "cascade-fetch-book",
        timeout: 120,
        memory: 512,
        store_output_to_s3: true,
        output_s3_key: "literary-analysis/{{job_id}}/book1_raw.txt",
        payload: %{
          book_id: "{{book1_id}}",
          source: "gutenberg"
        }
      ],

      fetch_book_2: [
        type: :lambda,
        function_name: "cascade-fetch-book",
        timeout: 120,
        memory: 512,
        store_output_to_s3: true,
        output_s3_key: "literary-analysis/{{job_id}}/book2_raw.txt",
        payload: %{
          book_id: "{{book2_id}}",
          source: "gutenberg"
        }
      ],

      # Stage 2: Extract chapters from books (parallel, depends on fetches)
      extract_chapters_1: [
        type: :lambda,
        function_name: "cascade-extract-chapters",
        timeout: 90,
        memory: 1024,
        store_output_to_s3: true,
        output_s3_key: "literary-analysis/{{job_id}}/book1_chapters.json",
        depends_on: [:fetch_book_1],
        payload: %{
          input_s3_key: "literary-analysis/{{job_id}}/book1_raw.txt"
        }
      ],

      extract_chapters_2: [
        type: :lambda,
        function_name: "cascade-extract-chapters",
        timeout: 90,
        memory: 1024,
        store_output_to_s3: true,
        output_s3_key: "literary-analysis/{{job_id}}/book2_chapters.json",
        depends_on: [:fetch_book_2],
        payload: %{
          input_s3_key: "literary-analysis/{{job_id}}/book2_raw.txt"
        }
      ],

      # Stage 3a: Word frequency analysis (parallel, depends on chapter extraction)
      word_frequency_1: [
        type: :lambda,
        function_name: "cascade-word-frequency",
        timeout: 180,
        memory: 1536,
        store_output_to_s3: true,
        output_s3_key: "literary-analysis/{{job_id}}/book1_word_freq.json",
        depends_on: [:extract_chapters_1],
        payload: %{
          input_s3_key: "literary-analysis/{{job_id}}/book1_chapters.json",
          top_n: 500,
          analysis_depth: "{{analysis_depth}}"
        }
      ],

      word_frequency_2: [
        type: :lambda,
        function_name: "cascade-word-frequency",
        timeout: 180,
        memory: 1536,
        store_output_to_s3: true,
        output_s3_key: "literary-analysis/{{job_id}}/book2_word_freq.json",
        depends_on: [:extract_chapters_2],
        payload: %{
          input_s3_key: "literary-analysis/{{job_id}}/book2_chapters.json",
          top_n: 500,
          analysis_depth: "{{analysis_depth}}"
        }
      ],

      # Stage 3b: Sentiment analysis (parallel, depends on chapter extraction)
      # THIS TASK FAILS PERIODICALLY (30% failure rate) for testing
      sentiment_analysis_1: [
        type: :lambda,
        function_name: "cascade-sentiment-analysis",
        timeout: 240,
        memory: 2048,
        store_output_to_s3: true,
        output_s3_key: "literary-analysis/{{job_id}}/book1_sentiment.json",
        depends_on: [:extract_chapters_1],
        payload: %{
          input_s3_key: "literary-analysis/{{job_id}}/book1_chapters.json",
          failure_rate: 0.3,  # 30% chance to fail
          model: "sentiment-v2"
        }
      ],

      sentiment_analysis_2: [
        type: :lambda,
        function_name: "cascade-sentiment-analysis",
        timeout: 240,
        memory: 2048,
        store_output_to_s3: true,
        output_s3_key: "literary-analysis/{{job_id}}/book2_sentiment.json",
        depends_on: [:extract_chapters_2],
        payload: %{
          input_s3_key: "literary-analysis/{{job_id}}/book2_chapters.json",
          failure_rate: 0.15,  # 15% chance to fail
          model: "sentiment-v2"
        }
      ],

      # Stage 4: Compare and aggregate results (fan-in, depends on all analyses)
      compare_results: [
        type: :lambda,
        function_name: "cascade-compare-books",
        timeout: 120,
        memory: 1024,
        store_output_to_s3: true,
        output_s3_key: "literary-analysis/{{job_id}}/comparison_report.json",
        depends_on: [:word_frequency_1, :word_frequency_2, :sentiment_analysis_1, :sentiment_analysis_2],
        payload: %{
          book1_word_freq: "literary-analysis/{{job_id}}/book1_word_freq.json",
          book2_word_freq: "literary-analysis/{{job_id}}/book2_word_freq.json",
          book1_sentiment: "literary-analysis/{{job_id}}/book1_sentiment.json",
          book2_sentiment: "literary-analysis/{{job_id}}/book2_sentiment.json",
          generate_visualizations: true
        }
      ]
    ]
end
