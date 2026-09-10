module "iam" {
  source = "./modules/iam"

  project_name  = var.project_name
  environment   = var.environment
  aws_region    = var.aws_region
  github_org    = var.github_org
  github_repo   = var.github_repo
  github_branch = "feat/retailedge-aws-integration"

  secrets_arns = [
    module.rds.db_secret_arn,
    module.elasticache.redis_secret_arn
  ]

  deploy_lambda_arn           = module.lambda_deploy.lambda_function_arn
  web_bucket_arn              = module.s3_web.bucket_arn
  cloudfront_distribution_arn = module.cloudfront.distribution_arn
}