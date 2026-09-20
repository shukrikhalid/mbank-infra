# ── KMS key for ECR registry encryption ───────────────────────────────────────

data "aws_iam_policy_document" "ecr_kms" {
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

  # ECR service needs to use the key to encrypt image layers
  statement {
    sid    = "AllowECRService"
    effect = "Allow"
    actions = [
      "kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*",
      "kms:GenerateDataKey*", "kms:DescribeKey",
    ]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["ecr.amazonaws.com"]
    }
  }

  # All org accounts can use the key to decrypt images they pull
  statement {
    sid    = "AllowOrgAccountsDecrypt"
    effect = "Allow"
    actions = [
      "kms:Decrypt", "kms:DescribeKey", "kms:GenerateDataKey*",
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
}

resource "aws_kms_key" "ecr" {
  description             = "CMK for Mbank shared ECR registry encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.ecr_kms.json
  tags                    = merge(local.common_tags, { Name = "mbank-ecr-cmk" })
}

resource "aws_kms_alias" "ecr" {
  name          = "alias/mbank-ecr"
  target_key_id = aws_kms_key.ecr.key_id
}

# ── Registry policy: org-wide image pull ──────────────────────────────────────

data "aws_iam_policy_document" "ecr_registry" {
  statement {
    sid    = "AllowOrgPull"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
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

  # ECR replication service needs CreateRepository in the destination registry
  statement {
    sid    = "AllowReplicationService"
    effect = "Allow"
    actions = [
      "ecr:CreateRepository",
      "ecr:ReplicateImage",
    ]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["replication.ecr.amazonaws.com"]
    }
  }
}

resource "aws_ecr_registry_policy" "shared" {
  policy = data.aws_iam_policy_document.ecr_registry.json
}

# ── Cross-region replication to ap-southeast-2 (Sydney, DR) ──────────────────
# Replicates all repositories to the same account in the DR region.
# No repository_filter = replicate everything.

resource "aws_ecr_replication_configuration" "dr" {
  replication_configuration {
    rule {
      destination {
        registry_id = data.aws_caller_identity.current.account_id
        region      = "ap-southeast-2"
      }
    }
  }
}

# ── Enhanced scanning via Amazon Inspector v2 ─────────────────────────────────
# Inspector v2 must be enabled in this account for ENHANCED scan type to work.
# SCAN_ON_PUSH: fires immediately after each push.
# CONTINUOUS_SCAN: fires when new vulnerabilities are published for existing images.

resource "aws_ecr_registry_scanning_configuration" "enhanced" {
  scan_type = "ENHANCED"

  rule {
    scan_frequency = "SCAN_ON_PUSH"
    repository_filter {
      filter      = "*"
      filter_type = "WILDCARD"
    }
  }

  rule {
    scan_frequency = "CONTINUOUS_SCAN"
    repository_filter {
      filter      = "*"
      filter_type = "WILDCARD"
    }
  }
}

# ── Default lifecycle policy template ─────────────────────────────────────────
# ECR has no registry-wide lifecycle policy. This canonical JSON is exported via
# SSM so the pipeline applies it to every repository it creates.

locals {
  ecr_default_lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep last 10 tagged images (v*, release-*, latest)"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "release-", "latest"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = { type = "expire" }
      },
    ]
  })
}

# ── SSM exports ───────────────────────────────────────────────────────────────

resource "aws_ssm_parameter" "ecr_kms_arn" {
  name  = "/mbank/shared/ecr/kms-key-arn"
  type  = "String"
  value = aws_kms_key.ecr.arn
  tags  = local.common_tags
}

resource "aws_ssm_parameter" "ecr_lifecycle_policy" {
  name  = "/mbank/shared/ecr/default-lifecycle-policy"
  type  = "String"
  value = local.ecr_default_lifecycle_policy
  tags  = local.common_tags
}

