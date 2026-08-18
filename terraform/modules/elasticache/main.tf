locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# Random auth token (Redis requires 16-128 chars, no special chars issues) 
resource "random_password" "redis_auth" {
  count   = var.auth_enabled ? 1 : 0
  length  = 32
  special = false
}

# Subnet Group 
resource "aws_elasticache_subnet_group" "this" {
  name       = "${local.name_prefix}-redis-subnet-group"
  subnet_ids = var.db_subnet_ids

  tags = {
    Name = "${local.name_prefix}-redis-subnet-group"
  }
}

# Redis Replication Group (Multi-AZ + Failover + Replica) 
resource "aws_elasticache_replication_group" "this" {
  replication_group_id = "${local.name_prefix}-redis"
  description          = "RetailEdge Redis cache"

  engine         = "redis"
  engine_version = "7.1"
  node_type      = var.node_type
  port           = 6379

  # Cluster Mode: Disabled -> single shard, num_node_groups omitted
  num_cache_clusters = 2 # 1 primary + 1 replica

  automatic_failover_enabled = true
  multi_az_enabled           = true

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [var.redis_sg_id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = var.auth_enabled ? random_password.redis_auth[0].result : null

  auto_minor_version_upgrade = true

  tags = {
    Name = "${local.name_prefix}-redis"
  }
}

# Secrets Manager (only if auth enabled) 
resource "aws_secretsmanager_secret" "redis" {
  count       = var.auth_enabled ? 1 : 0
  name        = "${var.project_name}/redis"
  description = "Redis auth token and connection info for the RetailEdge application"

  tags = {
    Name = "${local.name_prefix}-redis-secret"
  }
}

resource "aws_secretsmanager_secret_version" "redis" {
  count     = var.auth_enabled ? 1 : 0
  secret_id = aws_secretsmanager_secret.redis[0].id

  secret_string = jsonencode({
    REDIS_HOST       = aws_elasticache_replication_group.this.primary_endpoint_address
    REDIS_PORT       = 6379
    REDIS_AUTH_TOKEN = random_password.redis_auth[0].result
    REDIS_TLS        = true
  })
}