locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# Random password
resource "random_password" "db" {
  length  = var.password_length
  special = false
}

# DB Subnet Group
resource "aws_db_subnet_group" "this" {
  name       = "${local.name_prefix}-db-subnet-group"
  subnet_ids = var.db_subnet_ids

  tags = {
    Name = "${local.name_prefix}-db-subnet-group"
  }
}

# RDS MySQL Instance
resource "aws_db_instance" "this" {
  identifier     = "${local.name_prefix}-mysql"
  engine         = "mysql"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage = var.allocated_storage
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result
  port     = 3306

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.rds_sg_id]
  publicly_accessible    = false

  multi_az = var.multi_az

  backup_retention_period = var.backup_retention_period
  backup_window           = var.backup_window
  maintenance_window      = var.maintenance_window

  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${local.name_prefix}-mysql-final-snapshot"

  deletion_protection = var.deletion_protection

  tags = {
    Name = "${local.name_prefix}-mysql"
  }
}

# Secrets Manager
resource "aws_secretsmanager_secret" "db" {
  name                    = "${local.name_prefix}/db"
  description             = "RDS MySQL credentials for the RetailEdge application"
  recovery_window_in_days = var.secret_recovery_window_in_days
  tags = {
    Name = "${local.name_prefix}-db-secret"
  }
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id

  secret_string = jsonencode({
    DB_HOST     = aws_db_instance.this.address
    DB_USER     = var.db_username
    DB_PWD      = random_password.db.result
    DB_DATABASE = var.db_name
    DB_PORT     = 3306
  })
}
