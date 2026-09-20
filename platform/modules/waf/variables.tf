# Task 11f — WAF Terraform module variables

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

variable "scope" {
  type        = string
  description = "WAF scope (CLOUDFRONT or REGIONAL)"
  default     = "REGIONAL"
  validation {
    condition     = contains(["CLOUDFRONT", "REGIONAL"], var.scope)
    error_message = "Scope must be CLOUDFRONT or REGIONAL."
  }
}

variable "alb_arn" {
  type        = string
  description = "ARN of ALB to associate WAF with (required for REGIONAL scope)"
  default     = ""
}

variable "rate_limit" {
  type        = number
  description = "Rate limit (requests per 5 minutes per IP)"
  default     = 2000
  validation {
    condition     = var.rate_limit >= 100 && var.rate_limit <= 2000000
    error_message = "Rate limit must be between 100 and 2000000."
  }
}

variable "block_ips" {
  type        = list(string)
  description = "List of CIDR blocks to block"
  default     = []
}

variable "allowed_countries" {
  type        = list(string)
  description = "List of country codes to allow (empty = allow all)"
  default     = []
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
