module "ssm_parameters" {
  source = "./modules/ssm-parameters"

  project_name = var.project_name
  environment  = var.environment
}