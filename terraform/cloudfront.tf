module "cloudfront" {
  source = "./modules/cloudfront"

  project_name = var.project_name
  environment  = var.environment

  s3_bucket_regional_domain_name = module.s3_web.bucket_regional_domain_name
  alb_arn                        = module.alb.alb_arn
  alb_dns_name                   = module.alb.alb_dns_name
  waf_web_acl_arn                = module.waf.web_acl_arn
  alb_https_enabled              = module.alb.https_enabled
}