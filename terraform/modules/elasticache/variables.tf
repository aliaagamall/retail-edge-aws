variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "db_subnet_ids" {
  description = "Using the same private database subnets as RDS"
  type        = list(string)
}

variable "redis_sg_id" {
  type = string
}

variable "node_type" {
  type    = string
  default = "cache.t3.micro"
}

variable "auth_enabled" {
  description = "Enable Redis AUTH token"
  type        = bool
  default     = true
}