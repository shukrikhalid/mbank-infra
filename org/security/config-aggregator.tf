# ── IAM role for Config org aggregator ────────────────────────────────────────

data "aws_iam_policy_document" "config_aggregator_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "config_aggregator" {
  provider           = aws.security
  name               = "mbank-config-aggregator-role"
  assume_role_policy = data.aws_iam_policy_document.config_aggregator_assume.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "config_aggregator" {
  provider   = aws.security
  role       = aws_iam_role.config_aggregator.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSConfigRoleForOrganizations"
}

# ── Org Config aggregator (security account is delegated admin) ───────────────

resource "aws_config_configuration_aggregator" "org" {
  provider = aws.security
  name     = "mbank-org-aggregator"

  organization_aggregation_source {
    all_regions = true
    role_arn    = aws_iam_role.config_aggregator.arn
  }

  tags       = local.common_tags
  depends_on = [aws_iam_role_policy_attachment.config_aggregator]
}

# ── AWS Config rules (managed, applied org-wide via delegated admin) ──────────

resource "aws_config_config_rule" "s3_public_read_prohibited" {
  provider = aws.security
  name     = "s3-bucket-public-read-prohibited"
  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
  }
  tags       = local.common_tags
  depends_on = [aws_config_configuration_aggregator.org]
}

resource "aws_config_config_rule" "encrypted_volumes" {
  provider = aws.security
  name     = "encrypted-volumes"
  source {
    owner             = "AWS"
    source_identifier = "ENCRYPTED_VOLUMES"
  }
  tags       = local.common_tags
  depends_on = [aws_config_configuration_aggregator.org]
}

resource "aws_config_config_rule" "access_keys_rotated" {
  provider         = aws.security
  name             = "access-keys-rotated"
  input_parameters = jsonencode({ maxAccessKeyAge = "90" })
  source {
    owner             = "AWS"
    source_identifier = "ACCESS_KEYS_ROTATED"
  }
  tags       = local.common_tags
  depends_on = [aws_config_configuration_aggregator.org]
}

resource "aws_config_config_rule" "rds_storage_encrypted" {
  provider = aws.security
  name     = "rds-storage-encrypted"
  source {
    owner             = "AWS"
    source_identifier = "RDS_STORAGE_ENCRYPTED"
  }
  tags       = local.common_tags
  depends_on = [aws_config_configuration_aggregator.org]
}

# ── Conformance pack: financial services best practices ───────────────────────
# Inline template keeps the pack version-controlled alongside this Terraform code.

resource "aws_config_conformance_pack" "financial_services" {
  provider = aws.security
  name     = "Mbank-Financial-Services-Best-Practices"

  template_body = <<-TEMPLATE
    Resources:
      CloudTrailEnabled:
        Type: AWS::Config::ConfigRule
        Properties:
          ConfigRuleName: cloud-trail-enabled
          Source:
            Owner: AWS
            SourceIdentifier: CLOUD_TRAIL_ENABLED
      RootMFAEnabled:
        Type: AWS::Config::ConfigRule
        Properties:
          ConfigRuleName: root-account-mfa-enabled
          Source:
            Owner: AWS
            SourceIdentifier: ROOT_ACCOUNT_MFA_ENABLED
      CMKKeyRotation:
        Type: AWS::Config::ConfigRule
        Properties:
          ConfigRuleName: cmk-backing-key-rotation-enabled
          Source:
            Owner: AWS
            SourceIdentifier: CMK_BACKING_KEY_ROTATION_ENABLED
      RDSMultiAZ:
        Type: AWS::Config::ConfigRule
        Properties:
          ConfigRuleName: rds-multi-az-support
          Source:
            Owner: AWS
            SourceIdentifier: RDS_MULTI_AZ_SUPPORT
      RDSBackupEnabled:
        Type: AWS::Config::ConfigRule
        Properties:
          ConfigRuleName: db-instance-backup-enabled
          Source:
            Owner: AWS
            SourceIdentifier: DB_INSTANCE_BACKUP_ENABLED
      VPCFlowLogsEnabled:
        Type: AWS::Config::ConfigRule
        Properties:
          ConfigRuleName: vpc-flow-logs-enabled
          Source:
            Owner: AWS
            SourceIdentifier: VPC_FLOW_LOGS_ENABLED
      GuardDutyEnabled:
        Type: AWS::Config::ConfigRule
        Properties:
          ConfigRuleName: guardduty-enabled-centralized
          Source:
            Owner: AWS
            SourceIdentifier: GUARDDUTY_ENABLED_CENTRALIZED
      SecurityHubEnabled:
        Type: AWS::Config::ConfigRule
        Properties:
          ConfigRuleName: securityhub-enabled
          Source:
            Owner: AWS
            SourceIdentifier: SECURITYHUB_ENABLED
  TEMPLATE

  depends_on = [aws_config_configuration_aggregator.org]
}

# ── Auto-remediation: s3-bucket-public-read-prohibited ────────────────────────
# SSM Automation runs AWS-DisableS3BucketPublicReadWrite on non-compliant buckets.

data "aws_iam_policy_document" "config_remediation_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ssm.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "config_remediation_s3" {
  statement {
    effect    = "Allow"
    actions   = ["s3:PutBucketPublicAccessBlock", "s3:GetBucketPublicAccessBlock"]
    resources = ["*"]
  }
}

resource "aws_iam_role" "config_remediation" {
  provider           = aws.security
  name               = "mbank-config-remediation-s3"
  assume_role_policy = data.aws_iam_policy_document.config_remediation_assume.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy" "config_remediation_s3" {
  provider = aws.security
  name     = "s3-block-public-access"
  role     = aws_iam_role.config_remediation.id
  policy   = data.aws_iam_policy_document.config_remediation_s3.json
}

resource "aws_config_remediation_configuration" "s3_public_read" {
  provider         = aws.security
  config_rule_name = aws_config_config_rule.s3_public_read_prohibited.name
  resource_type    = "AWS::S3::Bucket"
  target_type      = "SSM_DOCUMENT"
  target_id        = "AWS-DisableS3BucketPublicReadWrite"

  automatic                  = true
  maximum_automatic_attempts = 3
  retry_attempt_seconds      = 60

  parameter {
    name         = "AutomationAssumeRole"
    static_value = aws_iam_role.config_remediation.arn
  }
  parameter {
    name           = "S3BucketName"
    resource_value = "RESOURCE_ID"
  }

  execution_controls {
    ssm_controls {
      concurrent_execution_rate_percentage = 25
      error_percentage                     = 20
    }
  }
}
