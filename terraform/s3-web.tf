module "s3_web" {
  source = "./modules/s3-web"

  project_name = var.project_name
  environment  = var.environment
  # cloudfront_distribution_arn will be set after create modules/cloudfront
}