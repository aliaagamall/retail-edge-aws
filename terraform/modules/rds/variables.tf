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
  description = "Initial database name"
  type        = string
  default     = "retailedge"
}

variable "db_username" {
  type    = string
  default = "retailedge_admin"
}

variable "instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "allocated_storage" {
  type    = number
  default = 20
}

variable "backup_retention_period" {
  description = "Automated backup retention in days"
  type        = number
  default     = 0
}

variable "multi_az" {
  type    = bool
  default = true
}

variable "skip_final_snapshot" {
  description = "Set true only for throwaway/dev environments"
  type        = bool
  default     = false
}