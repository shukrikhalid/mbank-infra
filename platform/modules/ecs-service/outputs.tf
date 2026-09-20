output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer."
  value       = aws_lb.this.dns_name
}

output "ecs_cluster_name" {
  description = "ECS cluster name."
  value       = aws_ecs_cluster.this.name
}

output "ecr_repository_url" {
  description = "ECR repository URL (without tag) for use in CI/CD image push commands."
  value       = aws_ecr_repository.this.repository_url
}

output "service_sg_id" {
  description = "Security group ID attached to ECS tasks. Reference this in database security group ingress rules."
  value       = aws_security_group.service.id
}

output "task_role_arn" {
  description = "IAM role ARN assumed by the running ECS task (application permissions)."
  value       = aws_iam_role.task.arn
}

output "alb_sg_id" {
  description = "Security group ID of the ALB. Attach WAF or additional ingress rules here."
  value       = aws_security_group.alb.id
}

output "alarms_sns_topic_arn" {
  description = "SNS topic ARN receiving all CloudWatch alarms for this service."
  value       = aws_sns_topic.alarms.arn
}

output "log_group_name" {
  description = "CloudWatch log group name for ECS task logs."
  value       = aws_cloudwatch_log_group.app.name
}

