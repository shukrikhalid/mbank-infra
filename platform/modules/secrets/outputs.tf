# Task 11e — Secrets module outputs

output "secret_arns" {
  description = "Map of secret names to their ARNs"
  value       = { for name, secret in aws_secretsmanager_secret.secrets : name => secret.arn }
}
