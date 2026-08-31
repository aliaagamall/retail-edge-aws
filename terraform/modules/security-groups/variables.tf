variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "vpc_cidr" {
  type = string
}
variable "certificate_arn" {
  description = "ACM certificate ARN. Leave empty to run HTTP-only (no domain yet)."
  type        = string
  default     = ""
}