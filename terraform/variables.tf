variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefix used in resource names and tags"
  type        = string
  default     = "retailedge"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "github_org" {
  description = "GitHub organization or username"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
}

# ---------- ALB ----------

variable "alb_deletion_protection" {
  type    = bool
  default = false
}

# ---------- WAF ----------

variable "waf_rate_limit" {
  description = "Maximum requests per 5-minute period per IP before blocking"
  type        = number
  default     = 2000
}

# ---------- RDS ----------

variable "rds_db_name" {
  description = "Initial RDS database name"
  type        = string
  default     = "retailedge"
}

variable "rds_db_username" {
  description = "RDS master username"
  type        = string
  default     = "retailedge_admin"
}

variable "rds_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "rds_allocated_storage" {
  description = "RDS allocated storage in GB"
  type        = number
  default     = 20
}

variable "rds_engine_version" {
  description = "MySQL engine version"
  type        = string
  default     = "8.0"
}

variable "rds_password_length" {
  description = "Length of the generated RDS password"
  type        = number
  default     = 20
}

variable "rds_backup_retention_period" {
  description = "Automated backup retention period in days"
  type        = number
  default     = 0
}

variable "rds_backup_window" {
  description = "Preferred daily RDS backup window"
  type        = string
  default     = "03:00-04:00"
}

variable "rds_maintenance_window" {
  description = "Preferred weekly RDS maintenance window"
  type        = string
  default     = "mon:04:30-mon:05:30"
}

variable "rds_multi_az" {
  description = "Enable RDS Multi-AZ deployment"
  type        = bool
  default     = true
}

variable "rds_skip_final_snapshot" {
  description = "Skip final snapshot when destroying RDS"
  type        = bool
  default     = true
}

variable "rds_deletion_protection" {
  description = "Protect RDS from accidental deletion"
  type        = bool
  default     = false
}

# ---------- ElastiCache ----------

variable "redis_node_type" {
  type    = string
  default = "cache.t3.micro"
}

# ---------- Compute ----------

variable "app_instance_type" {
  type    = string
  default = "t3.micro"
}

variable "asg_min_size" {
  type    = number
  default = 2
}

variable "asg_max_size" {
  type    = number
  default = 4
}

variable "asg_desired_capacity" {
  type    = number
  default = 2
}
