defmodule Cascade.AWS.Config do
  @moduledoc """
  AWS configuration helper.

  ExAws automatically uses the AWS credential chain:
  1. Environment variables (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
  2. AWS credentials file (~/.aws/credentials) - from `aws configure`
  3. AWS config file (~/.aws/config)
  4. EC2/ECS instance metadata

  This module provides helpers for Cascade-specific AWS configuration.
  """

  @doc """
  Returns the AWS region.
  """
  def region do
    System.get_env("AWS_REGION") ||
      System.get_env("AWS_DEFAULT_REGION") ||
      Application.get_env(:cascade, :aws_region) ||
      "us-east-1"
  end

  @doc """
  Returns the S3 bucket name for artifacts.
  """
  def s3_bucket do
    System.get_env("CASCADE_S3_BUCKET") ||
      Application.get_env(:cascade, :s3_bucket) ||
      "cascade-artifacts"
  end
end
