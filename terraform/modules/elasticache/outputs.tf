output "redis_primary_endpoint" {
  value = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "redis_port" {
  value = aws_elasticache_replication_group.this.port
}

output "redis_replication_group_id" {
  value = aws_elasticache_replication_group.this.id
}

output "redis_security_group_id" {
  value = var.redis_sg_id
}

output "redis_secret_arn" {
  value = var.auth_enabled ? aws_secretsmanager_secret.redis[0].arn : ""
}

output "redis_secret_name" {
  value = var.auth_enabled ? aws_secretsmanager_secret.redis[0].name : ""
}