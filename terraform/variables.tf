variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-2"
}

variable "bucket_name" {
  description = "S3 bucket name for Cascade artifacts"
  type        = string
  default     = "cascade-artifacts-demo"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "cascade"
}
