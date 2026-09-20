variable "ct_management_account_id" {
  description = "AWS account ID of the Control Tower management (root) account."
  type        = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.ct_management_account_id))
    error_message = "Must be a 12-digit AWS account ID."
  }
}

variable "log_archive_account_id" {
  description = "AWS account ID of the Log Archive account."
  type        = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.log_archive_account_id))
    error_message = "Must be a 12-digit AWS account ID."
  }
}

variable "audit_account_id" {
  description = "AWS account ID of the Audit (Security) account."
  type        = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.audit_account_id))
    error_message = "Must be a 12-digit AWS account ID."
  }
}

variable "aft_management_account_id" {
  description = "AWS account ID of the dedicated AFT management account."
  type        = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.aft_management_account_id))
    error_message = "Must be a 12-digit AWS account ID."
  }
}
