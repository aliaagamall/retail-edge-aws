variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "app_subnet_ids" {
  description = "Private application subnet IDs where interface ENIs are placed"
  type        = list(string)
}

variable "app_route_table_id" {
  description = "Route table used by the app subnets (for the S3 gateway endpoint)"
  type        = string
}

variable "endpoints_sg_id" {
  description = "Security Group ID allowing 443 from the App SG only"
  type        = string
}