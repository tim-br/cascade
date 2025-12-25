# =============================================
# AFFORDABLE POSTGRESQL RDS FOR CASCADE APP
# Smallest cost-effective instance (db.t4g.micro)
# =============================================

# Variables (add these to your variables.tf or pass via tfvars)
variable "db_username" {
  description = "Master username for the PostgreSQL database"
  type        = string
  default     = "cascade_admin"
}

variable "db_name" {
  description = "Name of the database to create"
  type        = string
  default     = "cascade_prod"
}

# Random password fallback (if you don't provide one via tfvars)
resource "random_password" "db_password" {
  length  = 20
  special = false
  override_special = "_%@"
}

# Subnet group for RDS (use private subnets for security)
resource "aws_db_subnet_group" "cascade" {
  name       = "cascade-db-subnet-group"
  subnet_ids = data.aws_subnets.all.ids  # Replace with your private subnet data source or list

  tags = {
    Name = "Cascade DB Subnet Group"
  }
}

# Security group for RDS - allow access only from ECS tasks
resource "aws_security_group" "rds" {
  name        = "cascade-rds-sg"
  description = "Allow PostgreSQL access from ECS tasks"
  vpc_id      = data.aws_vpc.default.id 

  ingress {
    description = "PostgreSQL from anywhere (TEMPORARY - tighten later!)"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # WARNING: Open to internet — only for initial testing
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Cascade RDS Security Group"
  }
}

# Smallest affordable RDS instance: db.t4g.micro (ARM Graviton)
# ~$15–20/month depending on region (as of 2025)
resource "aws_db_instance" "cascade" {
  identifier             = "cascade-db"
  engine                 = "postgres"
  engine_version         = "16"  # Latest stable as of 2025
  instance_class         = "db.t4g.micro"     # Cheapest burstable Graviton instance
  allocated_storage      = 20                 # Minimum GP2 storage (20 GB)
  storage_type           = "gp2"
  db_name                = var.db_name
  username               = var.db_username
  password               = var.db_password != "" ? var.db_password : random_password.db_password.result
  parameter_group_name   = "default.postgres16"

  db_subnet_group_name   = aws_db_subnet_group.cascade.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  publicly_accessible    = false
  skip_final_snapshot    = true               # Set to false in real prod
  final_snapshot_identifier = "cascade-final-snapshot"  # Only used if skip_final_snapshot = false

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  multi_az               = false  # Single AZ = cheaper
  storage_encrypted      = true

  tags = {
    Name = "Cascade PostgreSQL"
  }
}

# Output the connection string for easy use
output "database_url" {
  description = "PostgreSQL connection string for your app"
  value       = "ecto:// ${var.db_username}:${var.db_password != "" ? var.db_password : random_password.db_password.result}@${aws_db_instance.cascade.endpoint}/${var.db_name}"
  sensitive   = true
}

output "rds_endpoint" {
  description = "RDS endpoint (host:port)"
  value       = aws_db_instance.cascade.endpoint
}
