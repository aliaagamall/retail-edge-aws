module "elasticache" {
  source = "./modules/elasticache"

  project_name  = var.project_name
  environment   = var.environment
  db_subnet_ids = module.networking.db_subnet_ids
  redis_sg_id   = module.security_groups.redis_sg_id
  node_type     = var.redis_node_type   
}