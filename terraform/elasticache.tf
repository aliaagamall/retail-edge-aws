module "elasticache" {
  source = "./modules/elasticache"

  project_name  = var.project_name
  environment   = var.environment
  db_subnet_ids = module.networking.db_subnet_ids
  redis_sg_id   = module.security_groups.redis_sg_id

  secret_recovery_window_in_days = var.secret_recovery_window_in_days

  node_type                  = var.redis_node_type
  engine_version             = var.redis_engine_version
  num_cache_clusters         = var.redis_num_cache_clusters
  automatic_failover_enabled = var.redis_automatic_failover_enabled
  multi_az_enabled           = var.redis_multi_az_enabled
  auth_enabled               = var.redis_auth_enabled
  auth_token_length          = var.redis_auth_token_length
}
