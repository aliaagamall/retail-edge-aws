output "db_instance_id" {
  value = aws_db_instance.this.identifier
}

output "db_endpoint" {
  value = aws_db_instance.this.address
}

output "db_secret_arn" {
  value = aws_secretsmanager_secret.db.arn
}

output "db_secret_name" {
  value = aws_secretsmanager_secret.db.name
}