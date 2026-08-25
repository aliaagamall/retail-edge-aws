variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "cloudfront_distribution_arn" {
  description = "ARN of the CloudFront distribution allowed to read this bucket (i w'll set it after CloudFront is created)"
  type        = string
  default     = ""
}