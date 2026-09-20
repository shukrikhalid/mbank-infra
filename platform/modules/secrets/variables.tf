# Task 11e — Secrets Terraform module variables

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

variable "secret_names" {
  type        = list(string)
  description = "List of secret names to create"
}

variable "enable_rotation" {
  type        = bool
  description = "Enable automatic secret rotation"
  default     = false
}

variable "rotation_lambda_arn" {
  type        = string
  description = "ARN of Lambda function for rotation (required if enable_rotation=true)"
  default     = ""
}

variable "rotation_days" {
  type        = number
  description = "Rotation period in days"
  default     = 30
  validation {
    condition     = var.rotation_days >= 1
    error_message = "Rotation days must be at least 1."
  }
}

variable "allowed_principal_arns" {
  type        = list(string)
  description = "List of IAM principal ARNs allowed to read secrets"
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
