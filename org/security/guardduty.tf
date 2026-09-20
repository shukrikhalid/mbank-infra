terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

# Default provider — management account
provider "aws" {
  region = "ap-southeast-5"
}

# Alias for operations that must run inside the delegated Security/Audit account
provider "aws" {
  alias  = "security"
  region = "ap-southeast-5"
  assume_role {
    role_arn     = "arn:aws:iam::${var.security_account_id}:role/PlatformAutomationRole"
    session_name = "TerraformSecurityBaseline"
  }
}

locals {
  common_tags = {
    Environment = "management"
    Team        = "platform"
    ManagedBy   = "terraform"
  }
}

data "aws_caller_identity" "management" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

# ── GuardDuty: management account ─────────────────────────────────────────────
# A detector must exist in the management account before delegation is possible.

resource "aws_guardduty_detector" "management" {
  enable = true
  tags   = local.common_tags
}

resource "aws_guardduty_organization_admin_account" "security" {
  admin_account_id = var.security_account_id
  depends_on       = [aws_guardduty_detector.management]
}

# ── GuardDuty: security account (delegated admin) ─────────────────────────────

resource "aws_guardduty_detector" "security" {
  provider = aws.security
  enable   = true
  tags     = local.common_tags
  depends_on = [aws_guardduty_organization_admin_account.security]
}

resource "aws_guardduty_organization_configuration" "this" {
  provider    = aws.security
  detector_id = aws_guardduty_detector.security.id
  # NEW accounts added to the org automatically get GuardDuty enabled
  auto_enable_organization_members = "ALL"

  features {
    name        = "S3_DATA_EVENTS"
    auto_enable = "ALL"
  }
  features {
    name        = "EKS_AUDIT_LOGS"
    auto_enable = "ALL"
  }
  features {
    name        = "EBS_MALWARE_PROTECTION"
    auto_enable = "ALL"
  }
  features {
    name        = "RDS_LOGIN_EVENTS"
    auto_enable = "ALL"
  }
  features {
    name        = "LAMBDA_NETWORK_LOGS"
    auto_enable = "ALL"
  }
  features {
    name        = "RUNTIME_MONITORING"
    auto_enable = "ALL"
    additional_configuration {
      name        = "EKS_ADDON_MANAGEMENT"
      auto_enable = "ALL"
    }
    additional_configuration {
      name        = "ECS_FARGATE_AGENT_MANAGEMENT"
      auto_enable = "ALL"
    }
    additional_configuration {
      name        = "EC2_AGENT_MANAGEMENT"
      auto_enable = "ALL"
    }
  }
}

# ── SNS for HIGH/CRITICAL findings ────────────────────────────────────────────
# Lives in the security account where GuardDuty aggregates all org findings.

resource "aws_sns_topic" "guardduty_findings" {
  provider          = aws.security
  name              = "mbank-guardduty-high-critical"
  kms_master_key_id = "alias/aws/sns"
  tags              = local.common_tags
}

data "aws_iam_policy_document" "guardduty_sns_policy" {
  provider = aws.security
  statement {
    sid     = "AllowEventsPublish"
    effect  = "Allow"
    actions = ["sns:Publish"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    resources = [aws_sns_topic.guardduty_findings.arn]
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:events:${data.aws_region.current.name}:${var.security_account_id}:rule/*"]
    }
  }
}

resource "aws_sns_topic_policy" "guardduty_findings" {
  provider = aws.security
  arn      = aws_sns_topic.guardduty_findings.arn
  policy   = data.aws_iam_policy_document.guardduty_sns_policy.json
}

resource "aws_sns_topic_subscription" "guardduty_email" {
  provider  = aws.security
  topic_arn = aws_sns_topic.guardduty_findings.arn
  protocol  = "email"
  endpoint  = var.security_alert_email
}

resource "aws_sns_topic_subscription" "guardduty_pagerduty" {
  provider  = aws.security
  topic_arn = aws_sns_topic.guardduty_findings.arn
  protocol  = "https"
  endpoint  = var.pagerduty_guardduty_webhook_url
}

# ── EventBridge: forward severity >= 7.0 (HIGH + CRITICAL) to SNS ─────────────

resource "aws_cloudwatch_event_rule" "guardduty_high_critical" {
  provider    = aws.security
  name        = "mbank-guardduty-high-critical"
  description = "GuardDuty findings with severity >= 7 (HIGH + CRITICAL)"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail      = { severity = [{ numeric = [">=", 7] }] }
  })

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "guardduty_findings_sns" {
  provider  = aws.security
  rule      = aws_cloudwatch_event_rule.guardduty_high_critical.name
  target_id = "GuardDutyToSNS"
  arn       = aws_sns_topic.guardduty_findings.arn

  input_transformer {
    input_paths = {
      severity   = "$.detail.severity"
      type       = "$.detail.type"
      account    = "$.detail.accountId"
      region     = "$.region"
      finding_id = "$.detail.id"
    }
    # Single-quoted JSON string required by EventBridge input transformer
    input_template = "\"GuardDuty | Sev:<severity> | <type> | Acct:<account> | Region:<region> | ID:<finding_id>\""
  }
}
