# Task 11b — DynamoDB Terraform module variables

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

variable "table_name" {
  type        = string
  description = "DynamoDB table name"
}

variable "hash_key" {
  type        = string
  description = "Hash key (partition key) attribute name"
}

variable "hash_key_type" {
  type        = string
  description = "Hash key type (S, N, B)"
  default     = "S"
  validation {
    condition     = contains(["S", "N", "B"], var.hash_key_type)
    error_message = "Key type must be S (String), N (Number), or B (Binary)."
  }
}

variable "range_key" {
  type        = string
  description = "Range key (sort key) attribute name (optional)"
  default     = ""
}

variable "range_key_type" {
  type        = string
  description = "Range key type (S, N, B)"
  default     = "S"
}

variable "billing_mode" {
  type        = string
  description = "Billing mode (PAY_PER_REQUEST or PROVISIONED)"
  default     = "PAY_PER_REQUEST"
  validation {
    condition     = contains(["PAY_PER_REQUEST", "PROVISIONED"], var.billing_mode)
    error_message = "Billing mode must be PAY_PER_REQUEST or PROVISIONED."
  }
}

variable "read_capacity" {
  type        = number
  description = "Read capacity units (for PROVISIONED mode)"
  default     = 5
}

variable "write_capacity" {
  type        = number
  description = "Write capacity units (for PROVISIONED mode)"
  default     = 5
}

variable "ttl_attribute" {
  type        = string
  description = "TTL attribute name (optional)"
  default     = ""
}

variable "enable_streams" {
  type        = bool
  description = "Enable DynamoDB Streams"
  default     = false
}

variable "stream_view_type" {
  type        = string
  description = "Stream view type (NEW_IMAGE, OLD_IMAGE, NEW_AND_OLD_IMAGES, KEYS_ONLY)"
  default     = "NEW_AND_OLD_IMAGES"
}

variable "global_secondary_indexes" {
  type = list(object({
    name               = string
    hash_key           = string
    range_key          = optional(string)
    projection_type    = optional(string, "ALL")
    read_capacity      = optional(number, 5)
    write_capacity     = optional(number, 5)
  }))
  description = "Global secondary indexes"
  default     = []
}

variable "enable_encryption" {
  type        = bool
  description = "Enable encryption at rest with KMS"
  default     = true
}

variable "kms_key_id" {
  type        = string
  description = "KMS key ID for encryption"
}

variable "alarm_read_throttle_threshold" {
  type        = number
  description = "Alarm threshold for read throttle events"
  default     = 5
}

variable "alarm_write_throttle_threshold" {
  type        = number
  description = "Alarm threshold for write throttle events"
  default     = 5
}

variable "tags" {
  type        = map(string)
  description = "Resource tags"
  default     = {}
}
