# Network outputs
output "vpc_id" {
  value = module.networking.vpc_id
}

output "public_subnet_ids" {
  value = module.networking.public_subnet_ids
}

output "app_subnet_ids" {
  value = module.networking.app_subnet_ids
}

output "db_subnet_ids" {
  value = module.networking.db_subnet_ids
}

# Security groups outputs
output "alb_sg_id" {
  value = module.security_groups.alb_sg_id
}

output "app_sg_id" {
  value = module.security_groups.app_sg_id
}

output "rds_sg_id" {
  value = module.security_groups.rds_sg_id
}

output "redis_sg_id" {
  value = module.security_groups.redis_sg_id
}

output "endpoints_sg_id" {
  value = module.security_groups.endpoints_sg_id
}

# vpc endpints outputs
output "interface_endpoint_ids" {
  value = module.vpc_endpoints.interface_endpoint_ids
}

output "s3_endpoint_id" {
  value = module.vpc_endpoints.s3_endpoint_id
}

# iam outputs
output "ec2_instance_profile_name" {
  value = module.iam.ec2_instance_profile_name
}

output "github_deploy_role_arn" {
  value = module.iam.github_deploy_role_arn
}

# elb outputs

output "alb_arn" {
  value = module.alb.alb_arn
}

output "alb_dns_name" {
  value = module.alb.alb_dns_name
}

output "target_group_arn" {
  value = module.alb.target_group_arn
}

output "https_enabled" {
  value = module.alb.https_enabled
}

# rds outputs

output "db_instance_id" {
  value = module.rds.db_instance_id
}

output "db_endpoint" {
  value = module.rds.db_endpoint
}

output "db_secret_arn" {
  value = module.rds.db_secret_arn
}

output "db_secret_name" {
  value = module.rds.db_secret_name
}
# ElastiCache outputs

output "redis_primary_endpoint" {
  value = module.elasticache.redis_primary_endpoint
}

output "redis_port" {
  value = module.elasticache.redis_port
}

output "redis_replication_group_id" {
  value = module.elasticache.redis_replication_group_id
}

output "redis_security_group_id" {
  value = module.security_groups.redis_sg_id
}

output "redis_secret_arn" {
  value = module.elasticache.redis_secret_arn
}

# ecr outputs

output "ecr_repository_url" {
  value = module.ecr.repository_url
}

# s3 outputs

output "s3_bucket_name" {
  value = module.s3.bucket_name
}

# waf outputs

output "waf_web_acl_arn" {
  value = module.waf.web_acl_arn
}

# compute outputs
output "asg_name" {
  value = module.compute.asg_name
}
output "launch_template_id" {
  value = module.compute.launch_template_id
}

# s3-web outputs
output "web_bucket_name" {
  value = module.s3_web.bucket_name
}

output "web_bucket_regional_domain_name" {
  value = module.s3_web.bucket_regional_domain_name
}

# cloudfront outputs
output "distribution_id" {
  value = module.cloudfront.distribution_id
}

output "distribution_domain_name" {
  value = module.cloudfront.distribution_domain_name
}

# ssm-parameter output

output "current_image_parameter_name" {
  value = module.ssm_parameters.current_image_parameter_name
}