# Task 11c — ElastiCache module outputs

output "primary_endpoint_address" {
  description = "Primary endpoint address for cache writes"
  value       = aws_elasticache_replication_group.cache.primary_endpoint_address
}

output "reader_endpoint_address" {
  description = "Reader endpoint address for cache reads"
  value       = aws_elasticache_replication_group.cache.reader_endpoint_address
}

output "replication_group_id" {
  description = "ID of the replication group"
  value       = aws_elasticache_replication_group.cache.id
}

output "auth_token_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the AUTH token"
  value       = aws_secretsmanager_secret.auth_token.arn
}

output "security_group_id" {
  description = "Security group ID for the ElastiCache cluster"
  value       = aws_security_group.cache.id
}
