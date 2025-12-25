# =============================================
# FULL ECS FARGATE DEPLOYMENT FOR CASCADE APP
# =============================================



# Variables
variable "domain_name" {
  description = "Your domain (e.g., cascade.example.com)"
  type        = string
}

variable "hosted_zone_id" {
  description = "Route53 hosted zone ID"
  type        = string
}

variable "secret_key_base" {
  description = "Phoenix SECRET_KEY_BASE"
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "DB password (from tfvars or random)"
  type        = string
  sensitive   = true
  default     = ""
}

# VPC data (keep this — it's useful)
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "all" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_region" "current" {}

# ECS Cluster
resource "aws_ecs_cluster" "cascade" {
  name = "cascade-cluster"
}

# Execution Role (public image pull + logs)
resource "aws_iam_role" "ecs_exec_role" {
  name = "cascade-ecs-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_exec_policy" {
  role       = aws_iam_role.ecs_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Task Role (for Lambda and S3 access)
resource "aws_iam_role" "ecs_task_role" {
  name = "cascade-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

# Lambda invoke policy
resource "aws_iam_role_policy" "ecs_task_lambda_policy" {
  name = "cascade-ecs-lambda-invoke"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction",
          "lambda:InvokeAsync"
        ]
        Resource = [
          aws_lambda_function.data_processor.arn,
          aws_lambda_function.aggregator.arn
        ]
      }
    ]
  })
}

# S3 access policy
resource "aws_iam_role_policy" "ecs_task_s3_policy" {
  name = "cascade-ecs-s3-access"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.cascade_artifacts.arn,
          "${aws_s3_bucket.cascade_artifacts.arn}/*"
        ]
      }
    ]
  })
}

# Log group
resource "aws_cloudwatch_log_group" "cascade_app" {
  name              = "/ecs/cascade-app"
  retention_in_days = 14
}

# Task Definition
resource "aws_ecs_task_definition" "cascade_app" {
  family                   = "cascade-app"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecs_exec_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "cascade-app"
      image     = "ghcr.io/tim-br/cascade:latest"
      essential = true
      portMappings = [
        { containerPort = 4000, protocol = "tcp" }
      ]
      environment = [
        { name = "PHX_HOST",          value = var.domain_name },
        { name = "PORT",              value = "4000" },
        { name = "PHX_SERVER",        value = "true" },
        { name = "DATABASE_URL",      value = "ecto://cascade_admin:${var.db_password}@${aws_db_instance.cascade.endpoint}/cascade_prod" },
        { name = "SECRET_KEY_BASE",   value = var.secret_key_base },
        { name = "AWS_REGION",        value = data.aws_region.current.name },
        { name = "CASCADE_S3_BUCKET", value = aws_s3_bucket.cascade_artifacts.id }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.cascade_app.name
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "cascade"
        }
      }
    }
  ])
}

# Optional: Add ALB, service, security groups, Route53 later

# Security group for ECS tasks (allow traffic from ALB only)
resource "aws_security_group" "ecs_tasks" {
  name        = "cascade-ecs-tasks-sg"
  description = "Allow inbound from ALB and outbound internet"
  vpc_id      = data.aws_vpc.default.id

  # Ingress from ALB is added in alb.tf as aws_security_group_rule

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# The missing piece: ECS Service
resource "aws_ecs_service" "cascade" {
  name            = "cascade-service"
  cluster         = aws_ecs_cluster.cascade.id
  task_definition = aws_ecs_task_definition.cascade_app.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.all.ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = true  # Required for outbound internet (DB, S3, etc.) in default VPC
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.cascade.arn
    container_name   = "cascade-app"
    container_port   = 4000
  }

  depends_on = [aws_lb_listener.https]
}
