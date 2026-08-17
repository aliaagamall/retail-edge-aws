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