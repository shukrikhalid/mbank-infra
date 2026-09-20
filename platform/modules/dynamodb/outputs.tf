# Task 11b — DynamoDB module outputs

output "table_arn" {
  description = "ARN of the DynamoDB table"
  value       = aws_dynamodb_table.table.arn
}

output "table_name" {
  description = "Name of the DynamoDB table"
  value       = aws_dynamodb_table.table.name
}

output "stream_arn" {
  description = "ARN of the DynamoDB Streams (if enabled)"
  value       = var.enable_streams ? aws_dynamodb_table.table.stream_arn : null
}

output "stream_label" {
  description = "Stream label of the DynamoDB Streams (if enabled)"
  value       = var.enable_streams ? aws_dynamodb_table.table.stream_label : null
}
