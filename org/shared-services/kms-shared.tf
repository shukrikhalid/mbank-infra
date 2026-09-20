# ── Shared KMS key policy (applied to all four classification keys) ───────────

data "aws_iam_policy_document" "kms_classification" {
  # Root: full admin access to allow key recovery and break-glass scenarios
  statement {
    sid       = "EnableRootAdmin"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  # Platform team: full key lifecycle management (rotation schedule, deletion, grants)
  statement {
    sid    = "AllowPlatformTeamManagement"
    effect = "Allow"
    actions = [
      "kms:Create*", "kms:Describe*", "kms:Enable*", "kms:List*",
      "kms:Put*", "kms:Update*", "kms:Revoke*", "kms:Disable*",
      "kms:Get*", "kms:Delete*", "kms:TagResource", "kms:UntagResource",
      "kms:ScheduleKeyDeletion", "kms:CancelKeyDeletion",
    ]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/PlatformAutomationRole"]
    }
  }

  # All org accounts: encrypt/decrypt/describe (use the key but not manage it)
  statement {
    sid    = "AllowOrgAccountsKeyUse"
    effect = "Allow"
    actions = [
      "kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*",
      "kms:GenerateDataKey*", "kms:DescribeKey",
    ]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalOrgID"
      values   = [data.aws_organizations_organization.this.id]
    }
  }

  # Allow AWS services (EBS, RDS, S3, Secrets Manager, etc.) to use grants
  statement {
    sid    = "AllowOrgAccountsServiceGrants"
    effect = "Allow"
    actions = [
      "kms:CreateGrant",
      "kms:ListGrants",
      "kms:RevokeGrant",
    ]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalOrgID"
      values   = [data.aws_organizations_organization.this.id]
    }
    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]  # only AWS services can use grants, not arbitrary principals
    }
  }
}

# ── KMS keys per data classification ──────────────────────────────────────────

locals {
  kms_keys = {
    public = {
      description = "Mbank shared CMK — DataClassification:public"
      alias       = "alias/mbank-public"
      ssm_path    = "/mbank/shared/kms-arn/public"
    }
    internal = {
      description = "Mbank shared CMK — DataClassification:internal"
      alias       = "alias/mbank-internal"
      ssm_path    = "/mbank/shared/kms-arn/internal"
    }
    confidential = {
      description = "Mbank shared CMK — DataClassification:confidential (PCI-DSS scope; payment card data)"
      alias       = "alias/mbank-confidential"
      ssm_path    = "/mbank/shared/kms-arn/confidential"
    }
    restricted = {
      description = "Mbank shared CMK — DataClassification:restricted (financial reporting; securities scope)"
      alias       = "alias/mbank-restricted"
      ssm_path    = "/mbank/shared/kms-arn/restricted"
    }
  }
}

resource "aws_kms_key" "classification" {
  for_each = local.kms_keys

  description             = each.value.description
  deletion_window_in_days = 30
  enable_key_rotation     = true  # annual rotation; satisfies BNM TRM and PCI DSS 3.6.4
  policy                  = data.aws_iam_policy_document.kms_classification.json

  tags = merge(local.common_tags, {
    Name               = "mbank-cmk-${each.key}"
    DataClassification = each.key
  })
}

resource "aws_kms_alias" "classification" {
  for_each = local.kms_keys

  name          = each.value.alias
  target_key_id = aws_kms_key.classification[each.key].key_id
}

# ── SSM exports: spoke accounts resolve key ARN by classification at deploy time ─

resource "aws_ssm_parameter" "kms_arn" {
  for_each = local.kms_keys

  name  = each.value.ssm_path
  type  = "String"
  value = aws_kms_key.classification[each.key].arn

  tags = merge(local.common_tags, { DataClassification = each.key })
}

