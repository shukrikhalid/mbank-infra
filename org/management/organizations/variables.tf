variable "security_account_id" {
  description = "AWS account ID of the Security/Audit account — receives delegated admin for GuardDuty, Config, Security Hub, CloudTrail, and IAM Access Analyzer."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.security_account_id))
    error_message = "Must be a 12-digit AWS account ID."
  }
}

variable "log_archive_account_id" {
  description = "AWS account ID of the Log Archive account — destination for org-level CloudTrail and VPC Flow Logs."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.log_archive_account_id))
    error_message = "Must be a 12-digit AWS account ID."
  }
}
