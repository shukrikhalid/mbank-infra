# Task 9 — EC2 Auto Scaling module outputs

output "alb_dns_name" {
  description = "DNS name of the load balancer"
  value       = aws_lb.alb.dns_name
}

output "alb_arn" {
  description = "ARN of the load balancer"
  value       = aws_lb.alb.arn
}

output "asg_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.asg.name
}

output "instance_sg_id" {
  description = "Security group ID for EC2 instances"
  value       = aws_security_group.instance_sg.id
}

output "instance_profile_arn" {
  description = "ARN of the EC2 instance profile"
  value       = aws_iam_instance_profile.instance_profile.arn
}

output "target_group_arn" {
  description = "ARN of the ALB target group"
  value       = aws_lb_target_group.app.arn
}

output "launch_template_id" {
  description = "ID of the launch template"
  value       = aws_launch_template.instance.id
}
