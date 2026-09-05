variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "asg_name" {
  description = "Auto Scaling Group name"
  type        = string
}

variable "alb_arn" {
  description = "ALB ARN"
  type        = string
}

variable "target_group_arn" {
  description = "Target group ARN"
  type        = string
}

variable "db_instance_id" {
  description = "RDS instance ID"
  type        = string
}

variable "redis_replication_group_id" {
  description = "Redis replication group ID"
  type        = string
}

variable "distribution_id" {
  description = "CloudFront distribution ID"
  type        = string
}

variable "web_acl_id" {
  description = "WAF Web ACL ID"
  type        = string
}

variable "alert_email" {
  description = "Email for alarm notifications"
  type        = string
}

variable "cpu_threshold" {
  description = "CPU usage threshold"
  type        = number
  default     = 75
}

variable "alb_5xx_threshold" {
  description = "ALB 5xx error threshold"
  type        = number
  default     = 5
}

variable "alb_latency_p95_threshold" {
  description = "ALB p95 latency threshold in seconds"
  type        = number
  default     = 0.8
}

variable "rds_free_storage_threshold_bytes" {
  description = "Minimum RDS free storage in bytes"
  type        = number
  default     = 2147483648
}

variable "redis_evictions_threshold" {
  description = "Redis eviction threshold"
  type        = number
  default     = 100
}

variable "waf_blocked_requests_threshold" {
  description = "WAF blocked requests threshold"
  type        = number
  default     = 1000
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}
