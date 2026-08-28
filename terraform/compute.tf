module "compute" {
  source = "./modules/compute"

  project_name          = var.project_name
  environment           = var.environment
  app_subnet_ids        = module.networking.app_subnet_ids
  app_sg_id             = module.security_groups.app_sg_id
  instance_profile_name = module.iam.ec2_instance_profile_name
  target_group_arn      = module.alb.target_group_arn
  instance_type         = var.app_instance_type
  min_size              = var.asg_min_size
  max_size              = var.asg_max_size
  desired_capacity      = var.asg_desired_capacity

  enable_scheduled_scaling = var.enable_black_friday_scaling

  scale_up_day   = var.black_friday_scale_up_day
  scale_up_month = var.black_friday_scale_up_month
  scale_up_hour  = var.black_friday_scale_up_hour

  scale_down_day   = var.black_friday_scale_down_day
  scale_down_month = var.black_friday_scale_down_month
  scale_down_hour  = var.black_friday_scale_down_hour

  scheduled_min_size         = var.black_friday_min_size
  scheduled_max_size         = var.black_friday_max_size
  scheduled_desired_capacity = var.black_friday_desired_capacity
}