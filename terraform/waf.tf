module "waf" {
  source = "./modules/waf"

  project_name = var.project_name
  environment  = var.environment
  rate_limit   = var.waf_rate_limit
}
