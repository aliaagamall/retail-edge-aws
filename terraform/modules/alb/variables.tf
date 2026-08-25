variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "app_subnet_ids" {
  description = "Private application subnets - ALB now sits here, internal only"
  type        = list(string)
}

variable "alb_sg_id" {
  type = string
}

variable "certificate_arn" {
  description = "ACM certificate ARN. Leave empty to run HTTP-only (no domain yet)."
  type        = string
  default     = ""
}

variable "enable_deletion_protection" {
  type    = bool
  default = false
}

