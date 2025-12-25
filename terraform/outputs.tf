output "s3_bucket_name" {
  description = "Name of the S3 bucket for artifacts"
  value       = aws_s3_bucket.cascade_artifacts.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.cascade_artifacts.arn
}

output "data_processor_function_name" {
  description = "Name of the data processor Lambda function"
  value       = aws_lambda_function.data_processor.function_name
}

output "data_processor_function_arn" {
  description = "ARN of the data processor Lambda function"
  value       = aws_lambda_function.data_processor.arn
}

output "aggregator_function_name" {
  description = "Name of the aggregator Lambda function"
  value       = aws_lambda_function.aggregator.function_name
}

output "aggregator_function_arn" {
  description = "ARN of the aggregator Lambda function"
  value       = aws_lambda_function.aggregator.arn
}

output "export_commands" {
  description = "Commands to export environment variables for Cascade"
  value       = <<-EOT
    # Run these commands to configure Cascade:
    export AWS_REGION="${var.aws_region}"
    export CASCADE_S3_BUCKET="${aws_s3_bucket.cascade_artifacts.id}"

    # Verify AWS credentials are configured:
    aws sts get-caller-identity
  EOT
}
