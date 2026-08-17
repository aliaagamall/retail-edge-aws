module "vpc_endpoints" {
  source = "./modules/vpc-endpoints"

  project_name       = var.project_name
  environment        = var.environment
  aws_region         = var.aws_region
  vpc_id             = module.networking.vpc_id
  app_subnet_ids     = module.networking.app_subnet_ids
  app_route_table_id = module.networking.app_route_table_id
  endpoints_sg_id    = module.security_groups.endpoints_sg_id
}