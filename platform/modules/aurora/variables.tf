# Task 11a — Aurora RDS module variables

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

variable "engine" {
  type        = string
  description = "Database engine (aurora-postgresql or aurora-mysql)"
  default     = "aurora-postgresql"
  validation {
    condition     = contains(["aurora-postgresql", "aurora-mysql"], var.engine)
    error_message = "Engine must be aurora-postgresql or aurora-mysql."
  }
}

variable "engine_version" {
  type        = string
  description = "Database engine version"
  default     = "15.4"
}

variable "instance_class" {
  type        = string
  description = "RDS instance class"
  default     = "db.r6g.large"
}

variable "num_instances" {
  type        = number
  description = "Number of database instances (1 writer + rest readers)"
  default     = 3
  validation {
    condition     = var.num_instances >= 1 && var.num_instances <= 15
    error_message = "Number of instances must be between 1 and 15."
  }
}

variable "db_name" {
  type        = string
  description = "Initial database name"
}

variable "master_username" {
  type        = string
  description = "Master database username"
  default     = "admin"
  sensitive   = true
}

variable "vpc_id" {
  type        = string
  description = "VPC ID"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs for RDS (multi-AZ)"
  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "At least 2 subnets (for multi-AZ) are required."
  }
}

variable "compute_sg_id" {
  type        = string
  description = "Security group ID of compute layer (to allow ingress from)"
}

variable "backup_retention_days" {
  type        = number
  description = "Database backup retention in days"
  default     = 35
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 35
    error_message = "Backup retention must be between 1 and 35 days."
  }
}

variable "deletion_protection" {
  type        = bool
  description = "Enable deletion protection on the database"
  default     = true
}

variable "enable_rds_proxy" {
  type        = bool
  description = "Enable RDS Proxy for connection pooling"
  default     = false
}

variable "alarm_cpu_threshold" {
  type        = number
  description = "CPU utilization alarm threshold (percent)"
  default     = 80
  validation {
    condition     = var.alarm_cpu_threshold > 0 && var.alarm_cpu_threshold <= 100
    error_message = "CPU threshold must be between 1 and 100."
  }
}

variable "alarm_replica_lag_threshold" {
  type        = number
  description = "Replica lag alarm threshold (milliseconds)"
  default     = 1000
}

variable "kms_key_id" {
  type        = string
  description = "KMS key ID for database encryption"
}

variable "tags" {
  type        = map(string)
  description = "Resource tags"
  default     = {}
}
