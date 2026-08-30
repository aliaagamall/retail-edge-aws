variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "app_subnet_ids" {
  type = list(string)
}

variable "app_sg_id" {
  type = string
}

variable "instance_profile_name" {
  type = string
}

variable "target_group_arn" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "min_size" {
  type    = number
  default = 2
}

variable "max_size" {
  type    = number
  default = 4
}

variable "desired_capacity" {
  type    = number
  default = 2
}

variable "enable_scheduled_scaling" {
  description = "Enable recurring scheduled scaling"
  type        = bool
  default     = false
}

variable "scale_up_day" {
  description = "Day of month to scale up"
  type        = number
  default     = 25
}

variable "scale_up_month" {
  description = "Month to scale up"
  type        = number
  default     = 11
}

variable "scale_up_hour" {
  description = "Hour (UTC) to scale up"
  type        = number
  default     = 0
}

variable "scale_down_day" {
  description = "Day of month to scale down"
  type        = number
  default     = 29
}

variable "scale_down_month" {
  description = "Month to scale down"
  type        = number
  default     = 11
}

variable "scale_down_hour" {
  description = "Hour (UTC) to scale down"
  type        = number
  default     = 6
}

variable "scheduled_min_size" {
  type    = number
  default = 10
}

variable "scheduled_max_size" {
  type    = number
  default = 17
}

variable "scheduled_desired_capacity" {
  type    = number
  default = 15
}

variable "ecr_repository_url" {
  description = "ECR repository URL to pull the application image from"
  type        = string
}

variable "ssm_parameter_name" {
  description = "SSM Parameter Store path holding the current deployed image tag"
  type        = string
}