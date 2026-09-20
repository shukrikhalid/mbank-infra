# Task 11g — Monitoring Terraform module variables

variable "app_name" {
  type        = string
  description = "Application name"
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

variable "compute_type" {
  type        = string
  description = "Compute type (ecs, ec2, or eks)"
  validation {
    condition     = contains(["ecs", "ec2", "eks"], var.compute_type)
    error_message = "Compute type must be ecs, ec2, or eks."
  }
}

variable "alarm_cpu_threshold" {
  type        = number
  description = "CPU utilization alarm threshold (%)"
  default     = 80
  validation {
    condition     = var.alarm_cpu_threshold > 0 && var.alarm_cpu_threshold <= 100
    error_message = "Must be between 1 and 100."
  }
}

variable "alarm_memory_threshold" {
  type        = number
  description = "Memory utilization alarm threshold (%)"
  default     = 80
  validation {
    condition     = var.alarm_memory_threshold > 0 && var.alarm_memory_threshold <= 100
    error_message = "Must be between 1 and 100."
  }
}

variable "alarm_5xx_threshold" {
  type        = number
  description = "5xx error alarm threshold (errors per 5 min)"
  default     = 5
  validation {
    condition     = var.alarm_5xx_threshold >= 1
    error_message = "Must be at least 1."
  }
}

variable "alarm_latency_p99_ms" {
  type        = number
  description = "P99 latency alarm threshold (milliseconds)"
  default     = 2000
  validation {
    condition     = var.alarm_latency_p99_ms >= 100
    error_message = "Must be at least 100ms."
  }
}

variable "pagerduty_service_key_secret" {
  type        = string
  description = "Secrets Manager secret name for PagerDuty service key (optional)"
  default     = ""
  sensitive   = true
}

variable "enable_dashboard" {
  type        = bool
  description = "Enable CloudWatch Dashboard"
  default     = true
}

variable "kms_key_id" {
  type        = string
  description = "KMS key ID for encryption"
}

variable "tags" {
  type        = map(string)
  description = "Resource tags"
  default     = {}
}
