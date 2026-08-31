variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "s3_bucket_regional_domain_name" {
  type = string
}

variable "alb_arn" {
  type = string
}

variable "alb_dns_name" {
  type = string
}

variable "waf_web_acl_arn" {
  type = string
}

variable "api_path_pattern" {
  type    = string
  default = "/api/*"
}

variable "price_class" {
  type    = string
  default = "PriceClass_100" # because it's the cheapset one
}

variable "alb_https_enabled" {
  description = "Whether HTTPS is enabled on the ALB"
  type        = bool
  default     = false
}