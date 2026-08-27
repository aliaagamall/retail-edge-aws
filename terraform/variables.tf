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

variable "rds_skip_final_snapshot" {
  type    = bool
  default = true
}

variable "rds_backup_retention_period" {
  type    = number
  default = 0
}

variable "rds_instance_class" {
  type    = string
  default = "db.t3.micro"
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
