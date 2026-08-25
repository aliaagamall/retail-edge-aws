module "rds" {
  source = "./modules/rds"

  project_name             = var.project_name
  environment              = var.environment
  db_subnet_ids            = module.networking.db_subnet_ids
  rds_sg_id                = module.security_groups.rds_sg_id
  skip_final_snapshot      = var.rds_skip_final_snapshot       
  backup_retention_period  = var.rds_backup_retention_period   
  instance_class           = var.rds_instance_class           
}