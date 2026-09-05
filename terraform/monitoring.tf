module "monitoring" {
  source = "./modules/monitoring"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region

  asg_name                   = module.compute.asg_name
  alb_arn                    = module.alb.alb_arn
  target_group_arn           = module.alb.target_group_arn
  db_instance_id             = module.rds.db_instance_id
  redis_replication_group_id = module.elasticache.redis_replication_group_id
  distribution_id            = module.cloudfront.distribution_id
  web_acl_id                 = module.waf.web_acl_id

  alert_email = var.alert_email

  # Alert thresholds
  cpu_threshold     = 75
  alb_5xx_threshold = 5
}