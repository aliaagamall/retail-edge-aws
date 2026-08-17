variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short project prefix used in resource names/tags"
  type        = string
  default     = "retailedge"
}

variable "environment" {
  description = "Deployment environment (prod, staging, dev)"
  type        = string
  default     = "dev"
}

#for iam

variable "github_org" {
  type = string
}

variable "github_repo" {
  type = string
}
