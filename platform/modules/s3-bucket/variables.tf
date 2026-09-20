# Task 11d — S3 Bucket Terraform module variables

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

variable "bucket_name_suffix" {
  type        = string
  description = "Suffix for bucket name (e.g., 'data', 'logs', 'uploads')"
}

variable "data_classification" {
  type        = string
  description = "Data classification level"
  validation {
    condition     = contains(["public", "internal", "confidential", "restricted"], var.data_classification)
    error_message = "Must be public, internal, confidential, or restricted."
  }
}

variable "versioning_enabled" {
  type        = bool
  description = "Enable versioning on the bucket"
  default     = true
}

variable "lifecycle_transition_days" {
  type        = number
  description = "Days before transitioning to S3-IA"
  default     = 30
  validation {
    condition     = var.lifecycle_transition_days >= 1
    error_message = "Must be at least 1 day."
  }
}

variable "lifecycle_expiration_days" {
  type        = number
  description = "Days before expiring objects (optional, null to disable)"
  default     = null
  validation {
    condition     = var.lifecycle_expiration_days == null || var.lifecycle_expiration_days >= 1
    error_message = "Must be at least 1 day or null."
  }
}

variable "enable_replication" {
  type        = bool
  description = "Enable cross-region replication (only for prod)"
  default     = false
}

variable "replication_destination_bucket_arn" {
  type        = string
  description = "ARN of destination bucket for replication"
  default     = ""
}

variable "logging_bucket_name" {
  type        = string
  description = "Name of the bucket for access logs"
  default     = ""
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
