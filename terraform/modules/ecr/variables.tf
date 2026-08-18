variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "repository_name" {
  description = "ECR repository name (matches the app image name)"
  type        = string
  default     = "app"
}

variable "image_tag_mutability" {
  description = "MUTABLE or IMMUTABLE"
  type        = string
  default     = "IMMUTABLE"
}