# Cascade AWS Infrastructure (Terraform)

This Terraform configuration sets up the AWS infrastructure needed to test Cascade with Lambda functions and S3 storage.

## What Gets Created

- **S3 Bucket**: `cascade-artifacts-demo` (configurable) for storing task artifacts
  - Versioning enabled
  - 30-day lifecycle policy for cleanup
- **Lambda Functions**:
  - `cascade-data-processor`: Simulates data processing (1024MB, 5min timeout)
  - `cascade-aggregator`: Aggregates results from processors (512MB, 3min timeout)
- **IAM Role**: Lambda execution role with S3 and CloudWatch Logs permissions
- **CloudWatch Log Groups**: For Lambda function logs (7-day retention)

## Prerequisites

1. AWS CLI configured with credentials:
   ```bash
   aws configure
   ```

2. Terraform installed:
   ```bash
   brew install terraform  # macOS
   # or download from https://www.terraform.io/downloads
   ```

## Usage

### 1. Configure Variables (Optional)

Create a `terraform.tfvars` file to customize settings:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit with your values:
```hcl
aws_region  = "us-east-2"
bucket_name = "my-cascade-artifacts"  # Must be globally unique
```

### 2. Deploy Infrastructure

```bash
cd terraform

# Initialize Terraform
terraform init

# Preview changes
terraform plan

# Apply changes (creates resources)
terraform apply

# Note the output values - you'll need these for Cascade
```

### Configure Cascade

After `terraform apply`, run the commands shown in the output:

```bash
export AWS_REGION="us-east-2"
export CASCADE_S3_BUCKET="cascade-artifacts-demo"
```

Or use the bucket name from terraform output:

```bash
export CASCADE_S3_BUCKET=$(terraform output -raw s3_bucket_name)
```

### 3. Test the Setup

Test the cloud-only pipeline with data flow:

```bash
# Via Mix task (recommended)
cd ../apps/cascade
mix cascade.trigger cloud_test_pipeline \
  --context '{"input_data": [10, 20, 30, 40, 50], "multiplier": 3}'

# Or via IEx
iex -S mix
```

```elixir
# Load the cloud-only DAG
Cascade.Examples.DAGLoader.load_cloud_only_dag()

# Trigger with context (data gets passed between tasks)
dag = Cascade.Workflows.get_dag_by_name("cloud_test_pipeline")
{:ok, job} = Cascade.Runtime.Scheduler.trigger_job(
  dag.id,
  "manual",
  %{"input_data" => [10, 20, 30, 40, 50], "multiplier" => 3}
)

# Watch execution in real-time
Cascade.Workflows.list_task_executions_for_job(job.id)
```

**What happens:**
1. `process` Lambda receives input `[10, 20, 30, 40, 50]` and multiplies by 3
2. Result `[30, 60, 90, 120, 150]` stored to S3
3. `aggregate` Lambda downloads from S3 and calculates: total=450, avg=90

**Verify results:**
```bash
# View CloudWatch logs
aws logs tail /aws/lambda/cascade-data-processor --since 5m
aws logs tail /aws/lambda/cascade-aggregator --since 5m

# Download S3 artifacts
JOB_ID="your-job-id-here"
aws s3 cp s3://cascade-artifacts-demo/cloud-test/$JOB_ID/process_result.json -
aws s3 cp s3://cascade-artifacts-demo/cloud-test/$JOB_ID/final_result.json -
```

### Destroy Infrastructure

When you're done testing:

```bash
terraform destroy
```

This will delete all AWS resources created by Terraform.

## Customization

### Change Region

Edit `variables.tf` or pass via command line:

```bash
terraform apply -var="aws_region=us-west-2"
```

### Change Bucket Name

```bash
terraform apply -var="bucket_name=my-custom-bucket-name"
```

## Cost Estimation

This infrastructure is very low cost:

- **S3**: ~$0.023/GB/month + minimal request costs
- **Lambda**: First 1M requests/month are free, then $0.20 per 1M requests
- **CloudWatch Logs**: Minimal cost for log storage

Expected monthly cost for light testing: **< $1**

## Troubleshooting

### Bucket name already exists

S3 bucket names must be globally unique. Change the bucket name:

```bash
terraform apply -var="bucket_name=cascade-artifacts-YOUR_NAME"
```

### AWS credentials not found

Ensure AWS CLI is configured:

```bash
aws configure
aws sts get-caller-identity  # Verify credentials work
```

### Lambda invocation errors

Check CloudWatch Logs:

```bash
aws logs tail /aws/lambda/cascade-data-processor --follow
```

## Files

- `versions.tf`: Terraform and provider version requirements
- `variables.tf`: Input variables for customization
- `main.tf`: Main resource definitions (S3, Lambda, IAM)
- `outputs.tf`: Output values after apply
- `lambda_functions/`: Python code for Lambda functions
  - `data_processor.py`: Data processing Lambda
  - `aggregator.py`: Aggregation Lambda
