variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "github_org" {
  description = "GitHub organization or username that owns the app repo"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (application repo)"
  type        = string
}

variable "github_branch" {
  description = "Branch allowed to assume the deployment role via OIDC"
  type        = string
  default     = "main"
}

variable "secrets_arns" {
  description = "ARNs of the Secrets Manager secrets the EC2 role may read"
  type        = list(string)
}

variable "deploy_lambda_arn" {
  description = "ARN of the deployment Lambda that GitHub Actions is allowed to invoke"
  type        = string
}

variable "web_bucket_arn" {
  description = "ARN of the S3 web bucket GitHub Actions syncs the React build to"
  type        = string
}

variable "cloudfront_distribution_arn" {
  description = "ARN of the CloudFront distribution GitHub Actions invalidates after a frontend deploy"
  type        = string
}