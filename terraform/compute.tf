module "compute" {
  source = "./modules/compute"

  project_name          = var.project_name
  environment           = var.environment
  app_subnet_ids        = module.networking.app_subnet_ids
  app_sg_id             = module.security_groups.app_sg_id
  instance_profile_name = module.iam.ec2_instance_profile_name
  target_group_arn      = module.alb.target_group_arn
}