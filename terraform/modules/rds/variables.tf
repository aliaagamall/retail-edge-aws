variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "db_subnet_ids" {
  type = list(string)
}

variable "rds_sg_id" {
  type = string
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "retailedge"
}

variable "db_username" {
  description = "Master database username"
  type        = string
  default     = "retailedge_admin"
}

variable "instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  description = "Allocated RDS storage in GB"
  type        = number
  default     = 20
}

variable "engine_version" {
  description = "MySQL engine version"
  type        = string
  default     = "8.0"
}

variable "password_length" {
  description = "Length of the generated database password"
  type        = number
  default     = 20
}

variable "backup_retention_period" {
  description = "Automated backup retention in days"
  type        = number
  default     = 0
}

variable "backup_window" {
  description = "Preferred daily backup window"
  type        = string
  default     = "03:00-04:00"
}

variable "maintenance_window" {
  description = "Preferred weekly maintenance window"
  type        = string
  default     = "mon:04:30-mon:05:30"
}

variable "multi_az" {
  description = "Enable Multi-AZ deployment"
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot when destroying the database"
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Protect the database from accidental deletion"
  type        = bool
  default     = false
}
