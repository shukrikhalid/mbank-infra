variable "security_account_id" {
  description = "AWS account ID of the Security/Audit account (GuardDuty, Security Hub, Config delegated admin)."
  type        = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.security_account_id))
    error_message = "Must be a 12-digit AWS account ID."
  }
}

variable "log_archive_account_id" {
  description = "AWS account ID of the Log Archive account (CloudTrail KMS decrypt access)."
  type        = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.log_archive_account_id))
    error_message = "Must be a 12-digit AWS account ID."
  }
}

variable "security_alert_email" {
  description = "Email address for HIGH/CRITICAL GuardDuty findings and CloudTrail management-event alerts."
  type        = string
}

variable "pagerduty_guardduty_webhook_url" {
  description = "PagerDuty HTTPS Events v2 integration URL for GuardDuty HIGH/CRITICAL findings. Store the value in Secrets Manager and inject at plan time."
  type        = string
  sensitive   = true
}
