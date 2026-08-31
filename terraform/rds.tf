module "rds" {
  source = "./modules/rds"

  project_name = var.project_name
  environment  = var.environment

  db_subnet_ids = module.networking.db_subnet_ids
  rds_sg_id     = module.security_groups.rds_sg_id

  db_name           = var.rds_db_name
  db_username       = var.rds_db_username
  instance_class    = var.rds_instance_class
  allocated_storage = var.rds_allocated_storage
  engine_version    = var.rds_engine_version
  password_length   = var.rds_password_length

  backup_retention_period = var.rds_backup_retention_period
  backup_window           = var.rds_backup_window
  maintenance_window      = var.rds_maintenance_window

  multi_az            = var.rds_multi_az
  skip_final_snapshot = var.rds_skip_final_snapshot
  deletion_protection = var.rds_deletion_protection
}
