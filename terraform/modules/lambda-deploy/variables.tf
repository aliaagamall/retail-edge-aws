variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "asg_name" {
  description = "Auto Scaling Group name this Lambda deploys to"
  type        = string
}

variable "ssm_parameter_name" {
  description = "SSM Parameter Store path holding the currently deployed image tag"
  type        = string
}

variable "ssm_parameter_arn" {
  description = "ARN of the SSM parameter above, for scoping IAM permissions"
  type        = string
}

variable "sns_topic_arn" {
  description = "SNS topic ARN used to alert on mixed-fleet-state (failed rollback). Reuses the monitoring module's topic."
  type        = string
}

variable "batch_size" {
  description = "Number of instances to deploy to at once. Default 1 = fully sequential rolling deployment."
  type        = number
  default     = 1
}

variable "command_timeout_seconds" {
  description = "Max time to wait for deploy.sh to finish on a single instance via SSM"
  type        = number
  default     = 180
}

variable "lambda_timeout_seconds" {
  description = "Overall Lambda function timeout. Must comfortably exceed (instance_count / batch_size) * command_timeout_seconds."
  type        = number
  default     = 600
}
