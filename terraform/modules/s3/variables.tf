variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "bucket_purpose" {
  description = "Suffix describing what this bucket is for (e.g. 'assets', 'uploads')"
  type        = string
  default     = "assets"
}

variable "app_role_arn" {
  description = "ARN of the EC2 application IAM role, allowed to access this bucket"
  type        = string
}