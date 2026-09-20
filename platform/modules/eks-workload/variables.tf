# Task 10 — EKS Workload module variables
# Note: This module provisions namespace-level resources for an app team.
# The EKS cluster itself is managed separately by the platform team.

variable "app_name" {
  type        = string
  description = "Application name"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.app_name))
    error_message = "App name must be lowercase alphanumeric with hyphens."
  }
}

variable "environment" {
  type        = string
  description = "Environment (prod, staging, dev)"
  validation {
    condition     = contains(["prod", "staging", "dev"], var.environment)
    error_message = "Environment must be prod, staging, or dev."
  }
}

variable "team" {
  type        = string
  description = "Team name"
}

variable "cost_centre" {
  type        = string
  description = "Cost centre identifier"
}

variable "eks_cluster_name" {
  type        = string
  description = "Name of the EKS cluster"
}

variable "namespace" {
  type        = string
  description = "Kubernetes namespace for the workload"
}

variable "service_account_name" {
  type        = string
  description = "Kubernetes service account name"
}

variable "iam_policy_arns" {
  type        = list(string)
  description = "IAM policy ARNs to attach to the IRSA role"
  default     = []
}

variable "hpa_min_replicas" {
  type        = number
  description = "Minimum replicas for Horizontal Pod Autoscaler"
  default     = 2
  validation {
    condition     = var.hpa_min_replicas >= 1
    error_message = "Minimum replicas must be at least 1."
  }
}

variable "hpa_max_replicas" {
  type        = number
  description = "Maximum replicas for Horizontal Pod Autoscaler"
  default     = 10
  validation {
    condition     = var.hpa_max_replicas >= var.hpa_min_replicas
    error_message = "Maximum replicas must be >= minimum replicas."
  }
}

variable "hpa_cpu_target" {
  type        = number
  description = "Target CPU utilization percentage for HPA"
  default     = 70
  validation {
    condition     = var.hpa_cpu_target > 0 && var.hpa_cpu_target <= 100
    error_message = "CPU target must be between 1 and 100."
  }
}

variable "resource_limits_cpu" {
  type        = string
  description = "CPU limit for containers"
  default     = "1"
}

variable "resource_limits_memory" {
  type        = string
  description = "Memory limit for containers"
  default     = "1Gi"
}

variable "tags" {
  type        = map(string)
  description = "Resource tags"
  default     = {}
}
