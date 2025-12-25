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

# CloudWatch Log Groups for Lambda functions
resource "aws_cloudwatch_log_group" "data_processor" {
  name              = "/aws/lambda/${aws_lambda_function.data_processor.function_name}"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "aggregator" {
  name              = "/aws/lambda/${aws_lambda_function.aggregator.function_name}"
  retention_in_days = 7
}
