variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "db_subnet_ids" {
  description = "Private database subnet IDs used by Redis"
  type        = list(string)
}

variable "redis_sg_id" {
  type = string
}

variable "node_type" {
  description = "ElastiCache Redis node type"
  type        = string
  default     = "cache.t3.micro"
}

variable "engine_version" {
  description = "Redis engine version"
  type        = string
  default     = "7.1"
}

variable "num_cache_clusters" {
  description = "Number of cache nodes in the replication group"
  type        = number
  default     = 2
}

variable "automatic_failover_enabled" {
  description = "Enable automatic failover between primary and replica"
  type        = bool
  default     = true
}

variable "multi_az_enabled" {
  description = "Enable Multi-AZ for Redis"
  type        = bool
  default     = true
}

variable "auth_enabled" {
  description = "Enable Redis AUTH token"
  type        = bool
  default     = true
}

variable "auth_token_length" {
  description = "Length of the generated Redis AUTH token"
  type        = number
  default     = 32
}

variable "secret_recovery_window_in_days" {
  description = "Number of days before the Redis secret is permanently deleted"
  type        = number
  default     = 0
}
