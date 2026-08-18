module "iam" {
  source = "./modules/iam"

  project_name  = var.project_name
  environment   = var.environment
  aws_region    = var.aws_region
  github_org    = var.github_org
  github_repo   = var.github_repo
  github_branch = "main"

  secrets_arns = [
    module.rds.db_secret_arn
  ]
}