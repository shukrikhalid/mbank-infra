# Task 10 — EKS Workload module outputs

output "irsa_role_arn" {
  description = "ARN of the IRSA role for pod identity"
  value       = aws_iam_role.irsa_role.arn
}

output "namespace" {
  description = "Kubernetes namespace name"
  value       = kubernetes_namespace.workload.metadata[0].name
}

output "service_account_name" {
  description = "Kubernetes service account name"
  value       = kubernetes_service_account.workload.metadata[0].name
}

output "service_account_arn" {
  description = "ARN of the service account (with IRSA annotation)"
  value       = aws_iam_role.irsa_role.arn
}
