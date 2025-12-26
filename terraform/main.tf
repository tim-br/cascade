# S3 Bucket for Cascade artifacts
resource "aws_s3_bucket" "cascade_artifacts" {
  bucket = var.bucket_name

  tags = {
    Name = "Cascade Artifacts"
  }
}

resource "aws_s3_bucket_versioning" "cascade_artifacts" {
  bucket = aws_s3_bucket.cascade_artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "cascade_artifacts" {
  bucket = aws_s3_bucket.cascade_artifacts.id

  rule {
    id     = "delete-old-artifacts"
    status = "Enabled"

    filter {
      prefix = "" # Apply to all objects
    }

    expiration {
      days = 30
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

# IAM Role for Lambda functions
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for Lambda to access S3 and CloudWatch Logs
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.project_name}-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.cascade_artifacts.arn,
          "${aws_s3_bucket.cascade_artifacts.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Data Processor Lambda Function
data "archive_file" "data_processor" {
  type        = "zip"
  source_file = "${path.module}/lambda_functions/data_processor.py"
  output_path = "${path.module}/lambda_functions/data_processor.zip"
}

resource "aws_lambda_function" "data_processor" {
  filename         = data.archive_file.data_processor.output_path
  function_name    = "cascade-data-processor"
  role             = aws_iam_role.lambda_role.arn
  handler          = "data_processor.lambda_handler"
  source_code_hash = data.archive_file.data_processor.output_base64sha256
  runtime          = "python3.11"
  timeout          = 300
  memory_size      = 1024

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.cascade_artifacts.id
    }
  }
}

# Aggregator Lambda Function
data "archive_file" "aggregator" {
  type        = "zip"
  source_file = "${path.module}/lambda_functions/aggregator.py"
  output_path = "${path.module}/lambda_functions/aggregator.zip"
}

resource "aws_lambda_function" "aggregator" {
  filename         = data.archive_file.aggregator.output_path
  function_name    = "cascade-aggregator"
  role             = aws_iam_role.lambda_role.arn
  handler          = "aggregator.lambda_handler"
  source_code_hash = data.archive_file.aggregator.output_base64sha256
  runtime          = "python3.11"
  timeout          = 180
  memory_size      = 512

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.cascade_artifacts.id
    }
  }
}

# Literary Analysis Lambda Functions
data "archive_file" "fetch_book" {
  type        = "zip"
  source_file = "${path.module}/lambda_functions/fetch_book.py"
  output_path = "${path.module}/lambda_functions/fetch_book.zip"
}

resource "aws_lambda_function" "fetch_book" {
  filename         = data.archive_file.fetch_book.output_path
  function_name    = "cascade-fetch-book"
  role             = aws_iam_role.lambda_role.arn
  handler          = "fetch_book.lambda_handler"
  source_code_hash = data.archive_file.fetch_book.output_base64sha256
  runtime          = "python3.11"
  timeout          = 120
  memory_size      = 512

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.cascade_artifacts.id
    }
  }
}

data "archive_file" "extract_chapters" {
  type        = "zip"
  source_file = "${path.module}/lambda_functions/extract_chapters.py"
  output_path = "${path.module}/lambda_functions/extract_chapters.zip"
}

resource "aws_lambda_function" "extract_chapters" {
  filename         = data.archive_file.extract_chapters.output_path
  function_name    = "cascade-extract-chapters"
  role             = aws_iam_role.lambda_role.arn
  handler          = "extract_chapters.lambda_handler"
  source_code_hash = data.archive_file.extract_chapters.output_base64sha256
  runtime          = "python3.11"
  timeout          = 90
  memory_size      = 1024

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.cascade_artifacts.id
    }
  }
}

data "archive_file" "word_frequency" {
  type        = "zip"
  source_file = "${path.module}/lambda_functions/word_frequency.py"
  output_path = "${path.module}/lambda_functions/word_frequency.zip"
}

resource "aws_lambda_function" "word_frequency" {
  filename         = data.archive_file.word_frequency.output_path
  function_name    = "cascade-word-frequency"
  role             = aws_iam_role.lambda_role.arn
  handler          = "word_frequency.lambda_handler"
  source_code_hash = data.archive_file.word_frequency.output_base64sha256
  runtime          = "python3.11"
  timeout          = 180
  memory_size      = 1536

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.cascade_artifacts.id
    }
  }
}

data "archive_file" "sentiment_analysis" {
  type        = "zip"
  source_file = "${path.module}/lambda_functions/sentiment_analysis.py"
  output_path = "${path.module}/lambda_functions/sentiment_analysis.zip"
}

resource "aws_lambda_function" "sentiment_analysis" {
  filename         = data.archive_file.sentiment_analysis.output_path
  function_name    = "cascade-sentiment-analysis"
  role             = aws_iam_role.lambda_role.arn
  handler          = "sentiment_analysis.lambda_handler"
  source_code_hash = data.archive_file.sentiment_analysis.output_base64sha256
  runtime          = "python3.11"
  timeout          = 240
  memory_size      = 2048

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.cascade_artifacts.id
    }
  }
}

data "archive_file" "compare_books" {
  type        = "zip"
  source_file = "${path.module}/lambda_functions/compare_books.py"
  output_path = "${path.module}/lambda_functions/compare_books.zip"
}

resource "aws_lambda_function" "compare_books" {
  filename         = data.archive_file.compare_books.output_path
  function_name    = "cascade-compare-books"
  role             = aws_iam_role.lambda_role.arn
  handler          = "compare_books.lambda_handler"
  source_code_hash = data.archive_file.compare_books.output_base64sha256
  runtime          = "python3.11"
  timeout          = 120
  memory_size      = 1024

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.cascade_artifacts.id
    }
  }
}

# CloudWatch Log Groups for Lambda functions
resource "aws_cloudwatch_log_group" "data_processor" {
  name              = "/aws/lambda/${aws_lambda_function.data_processor.function_name}"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "aggregator" {
  name              = "/aws/lambda/${aws_lambda_function.aggregator.function_name}"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "fetch_book" {
  name              = "/aws/lambda/${aws_lambda_function.fetch_book.function_name}"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "extract_chapters" {
  name              = "/aws/lambda/${aws_lambda_function.extract_chapters.function_name}"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "word_frequency" {
  name              = "/aws/lambda/${aws_lambda_function.word_frequency.function_name}"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "sentiment_analysis" {
  name              = "/aws/lambda/${aws_lambda_function.sentiment_analysis.function_name}"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "compare_books" {
  name              = "/aws/lambda/${aws_lambda_function.compare_books.function_name}"
  retention_in_days = 7
}
