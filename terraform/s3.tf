module "s3" {
  source = "./modules/s3"

  project_name = var.project_name
  environment  = var.environment
  app_role_arn = module.iam.ec2_role_arn
}