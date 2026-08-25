module "waf" {
  source = "./modules/waf"

  project_name = var.project_name
  environment  = var.environment
}