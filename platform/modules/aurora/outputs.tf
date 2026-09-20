# Task 11a — Aurora module outputs

output "cluster_endpoint" {
  description = "Aurora cluster endpoint for database writes"
  value       = aws_rds_cluster.aurora.endpoint
}

output "reader_endpoint" {
  description = "Aurora reader endpoint for database reads"
  value       = aws_rds_cluster.aurora.reader_endpoint
}

output "cluster_arn" {
  description = "ARN of the Aurora cluster"
  value       = aws_rds_cluster.aurora.arn
}

output "secret_arn" {
  description = "ARN of the Secrets Manager secret containing database credentials"
  value       = aws_secretsmanager_secret.db_password.arn
}

output "proxy_endpoint" {
  description = "RDS Proxy endpoint (if enabled)"
  value       = var.enable_rds_proxy ? aws_db_proxy.aurora[0].endpoint : null
}

output "security_group_id" {
  description = "Security group ID for the Aurora cluster"
  value       = aws_security_group.aurora.id
}

output "subnet_group_name" {
  description = "DB subnet group name"
  value       = aws_db_subnet_group.aurora.name
}
