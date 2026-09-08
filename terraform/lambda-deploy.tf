module "lambda_deploy" {
  source = "./modules/lambda-deploy"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region

  asg_name           = module.compute.asg_name
  ssm_parameter_name = module.ssm_parameters.current_image_parameter_name
  ssm_parameter_arn  = module.ssm_parameters.current_image_parameter_arn
  sns_topic_arn      = module.monitoring.sns_topic_arn

  # Sequential rolling deployment - one instance at a time.
  # Raise later if the fleet grows and slower rollouts become a problem.
  batch_size = 1
}
