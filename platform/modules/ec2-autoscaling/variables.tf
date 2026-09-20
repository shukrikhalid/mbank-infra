# Task 9 — EC2 Auto Scaling module variables

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

variable "data_classification" {
  type        = string
  description = "Data classification level"
  validation {
    condition     = contains(["public", "internal", "confidential", "restricted"], var.data_classification)
    error_message = "Data classification must be public, internal, confidential, or restricted."
  }
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type"
  default     = "t3.medium"
}

variable "ami_id" {
  type        = string
  description = "AMI ID for EC2 instances"
}

variable "min_size" {
  type        = number
  description = "Minimum number of instances"
  default     = 2
  validation {
    condition     = var.min_size >= 1
    error_message = "Min size must be at least 1."
  }
}

variable "max_size" {
  type        = number
  description = "Maximum number of instances"
  default     = 10
  validation {
    condition     = var.max_size >= var.min_size
    error_message = "Max size must be >= min size."
  }
}

variable "desired_capacity" {
  type        = number
  description = "Desired number of instances"
  default     = 2
  validation {
    condition     = var.desired_capacity >= var.min_size && var.desired_capacity <= var.max_size
    error_message = "Desired capacity must be between min and max size."
  }
}

variable "vpc_id" {
  type        = string
  description = "VPC ID"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs for ASG (3 AZs)"
  validation {
    condition     = length(var.private_subnet_ids) >= 3
    error_message = "At least 3 subnets (one per AZ) are required."
  }
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "Public subnet IDs for ALB (optional)"
  default     = []
}

variable "key_name" {
  type        = string
  description = "SSH key pair name (optional, not recommended for prod)"
  default     = ""
}

variable "user_data_b64" {
  type        = string
  description = "Base64 encoded user data script"
  default     = ""
}

variable "enable_ssm" {
  type        = bool
  description = "Enable Systems Manager Session Manager access"
  default     = true
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

variable "kms_key_id" {
  type        = string
  description = "KMS key ID for EBS encryption"
}

variable "app_port" {
  type        = number
  description = "Application port for health checks and ALB listener"
  default     = 80
}

variable "health_check_path" {
  type        = string
  description = "Health check path for ALB target group"
  default     = "/health"
}

variable "tags" {
  type        = map(string)
  description = "Resource tags"
  default     = {}
}
