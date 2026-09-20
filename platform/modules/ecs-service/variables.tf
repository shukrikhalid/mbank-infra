# ── Identity ──────────────────────────────────────────────────────────────────

variable "app_name" {
  description = "Application name. Used as a prefix for all resource names."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.app_name))
    error_message = "app_name must be lowercase alphanumeric and hyphens only."
  }
}

variable "environment" {
  description = "Deployment environment."
  type        = string
  validation {
    condition     = contains(["prod", "staging", "dev"], var.environment)
    error_message = "environment must be prod, staging, or dev."
  }
}

variable "team" {
  description = "Owning team (used in tags and IAM naming)."
  type        = string
}

variable "cost_centre" {
  description = "Cost centre code (e.g. CC-PAY-001). Required tag."
  type        = string
}

variable "data_classification" {
  description = "Data classification tier. Drives KMS key selection from SSM."
  type        = string
  validation {
    condition     = contains(["public", "internal", "confidential", "restricted"], var.data_classification)
    error_message = "data_classification must be public, internal, confidential, or restricted."
  }
}

# ── Container ─────────────────────────────────────────────────────────────────

variable "container_image" {
  description = "Full container image URI (registry/repo:tag)."
  type        = string
}

variable "container_port" {
  description = "Port the container listens on."
  type        = number
  default     = 8080
}

variable "cpu" {
  description = "Fargate task CPU units (256 | 512 | 1024 | 2048 | 4096)."
  type        = number
  default     = 512
}

variable "memory" {
  description = "Fargate task memory in MiB."
  type        = number
  default     = 1024
}

variable "desired_count" {
  description = "Initial number of running task instances."
  type        = number
  default     = 2
}

variable "min_capacity" {
  description = "Minimum number of tasks for auto scaling."
  type        = number
  default     = 1
}

variable "max_capacity" {
  description = "Maximum number of tasks for auto scaling."
  type        = number
  default     = 10
}

variable "health_check_path" {
  description = "ALB and container health check HTTP path."
  type        = string
  default     = "/health"
}

variable "enable_xray" {
  description = "Attach AWS X-Ray sidecar container to the task."
  type        = bool
  default     = false
}

variable "secrets_arns" {
  description = "Secrets Manager ARNs to inject as environment variables. Env var name is derived from the last path segment of the secret name."
  type        = list(string)
  default     = []
}

# ── Network ───────────────────────────────────────────────────────────────────

variable "public_facing" {
  description = "true → internet-facing ALB (HTTPS/443); false → internal ALB (HTTP/80)."
  type        = bool
  default     = false
}

variable "vpc_id" {
  description = "VPC in which to deploy the service."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for ECS tasks and internal ALB."
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for internet-facing ALB. Required when public_facing = true."
  type        = list(string)
  default     = []
}

variable "certificate_arn" {
  description = "ACM certificate ARN for HTTPS. If empty and public_facing = true, the module looks up *.mbank.com."
  type        = string
  default     = ""
}

# ── Observability ─────────────────────────────────────────────────────────────

variable "alarm_cpu_threshold" {
  description = "CPU utilisation (%) that triggers the high-CPU alarm."
  type        = number
  default     = 80
}

variable "alarm_5xx_threshold" {
  description = "5xx error rate (%) that triggers the error-rate alarm."
  type        = number
  default     = 5
}

variable "pagerduty_service_key_secret" {
  description = "Secrets Manager secret name/ARN containing the PagerDuty Events v2 integration key. Leave empty to disable PagerDuty."
  type        = string
  default     = ""
}

