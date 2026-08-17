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