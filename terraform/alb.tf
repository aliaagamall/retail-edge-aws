module "alb" {
  source = "./modules/alb"

  project_name               = var.project_name
  environment                = var.environment
  vpc_id                     = module.networking.vpc_id
  app_subnet_ids             = module.networking.app_subnet_ids
  alb_sg_id                  = module.security_groups.alb_sg_id
  certificate_arn            = var.certificate_arn
  enable_deletion_protection = var.alb_deletion_protection
}
