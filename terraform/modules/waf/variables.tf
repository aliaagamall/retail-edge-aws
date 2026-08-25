variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}


variable "rate_limit" {
  description = "Max requests per 5-minute period per IP before blocking"
  type        = number
  default     = 2000
}