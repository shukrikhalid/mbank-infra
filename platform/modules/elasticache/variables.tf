# Task 11c — ElastiCache Terraform module variables

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

variable "engine" {
  type        = string
  description = "Cache engine (redis or valkey)"
  default     = "redis"
  validation {
    condition     = contains(["redis", "valkey"], var.engine)
    error_message = "Engine must be redis or valkey."
  }
}

variable "engine_version" {
  type        = string
  description = "Engine version"
  default     = "7.0"
}

variable "node_type" {
  type        = string
  description = "Node type for cache cluster"
  default     = "cache.t3.medium"
}

variable "num_cache_nodes" {
  type        = number
  description = "Number of cache nodes"
  default     = 2
  validation {
    condition     = var.num_cache_nodes >= 1 && var.num_cache_nodes <= 500
    error_message = "Number of nodes must be between 1 and 500."
  }
}

variable "vpc_id" {
  type        = string
  description = "VPC ID"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs for ElastiCache"
  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "At least 2 subnets are required."
  }
}

variable "compute_sg_id" {
  type        = string
  description = "Security group ID of compute layer (to allow ingress from)"
}

variable "at_rest_encryption_enabled" {
  type        = bool
  description = "Enable encryption at rest"
  default     = true
}

variable "transit_encryption_enabled" {
  type        = bool
  description = "Enable in-transit encryption (TLS)"
  default     = true
}

variable "automatic_failover_enabled" {
  type        = bool
  description = "Enable automatic failover"
  default     = true
}

variable "multi_az_enabled" {
  type        = bool
  description = "Enable Multi-AZ for automatic failover"
  default     = true
}

variable "snapshot_retention_limit" {
  type        = number
  description = "Snapshot retention limit in days"
  default     = 7
  validation {
    condition     = var.snapshot_retention_limit >= 0 && var.snapshot_retention_limit <= 35
    error_message = "Snapshot retention must be between 0 and 35 days."
  }
}

variable "kms_key_id" {
  type        = string
  description = "KMS key ID for encryption at rest"
}

variable "tags" {
  type        = map(string)
  description = "Resource tags"
  default     = {}
}
