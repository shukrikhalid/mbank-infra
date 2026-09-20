# ── KMS CMK for CloudTrail ────────────────────────────────────────────────────

data "aws_iam_policy_document" "cloudtrail_kms" {
  statement {
    sid       = "EnableRootAdministration"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.management.account_id}:root"]
    }
  }

  statement {
    sid     = "AllowCloudTrailEncrypt"
    effect  = "Allow"
    actions = ["kms:GenerateDataKey*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:aws:cloudtrail:arn"
      values   = ["arn:${data.aws_partition.current.partition}:cloudtrail:*:${data.aws_caller_identity.management.account_id}:trail/*"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.management.account_id}:trail/mbank-org-trail"]
    }
  }

  statement {
    sid       = "AllowCloudTrailDescribe"
    effect    = "Allow"
    actions   = ["kms:DescribeKey"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }

  statement {
    sid    = "AllowCloudWatchLogsEncryptDecrypt"
    effect = "Allow"
    actions = [
      "kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*",
      "kms:GenerateDataKey*", "kms:DescribeKey",
    ]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["logs.${data.aws_region.current.name}.amazonaws.com"]
    }
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.name}:${data.aws_caller_identity.management.account_id}:*"]
    }
  }

  # Log Archive account can decrypt for audit review purposes
  statement {
    sid       = "AllowLogArchiveDecrypt"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:DescribeKey"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${var.log_archive_account_id}:root"]
    }
  }
}

resource "aws_kms_key" "cloudtrail" {
  description             = "CMK for Mbank org-level CloudTrail"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.cloudtrail_kms.json
  tags                    = merge(local.common_tags, { Name = "mbank-cloudtrail-cmk" })
}

resource "aws_kms_alias" "cloudtrail" {
  name          = "alias/mbank-cloudtrail"
  target_key_id = aws_kms_key.cloudtrail.key_id
}

# ── S3 bucket — Object Lock COMPLIANCE, 7-year minimum retention ──────────────
# object_lock_enabled must be set at bucket creation; cannot be changed later.

resource "aws_s3_bucket" "cloudtrail" {
  bucket        = "mbank-cloudtrail-org-${data.aws_caller_identity.management.account_id}"
  force_destroy = false
  object_lock_enabled = true
  tags          = merge(local.common_tags, { Name = "mbank-cloudtrail-org" })
}

resource "aws_s3_bucket_versioning" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_object_lock_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  rule {
    default_retention {
      mode = "COMPLIANCE"
      days = 2555  # BNM audit trail requirement: 7 years
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.cloudtrail.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket                  = aws_s3_bucket.cloudtrail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  rule {
    id     = "glacier-after-90-days"
    status = "Enabled"
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
    # Object Lock COMPLIANCE prevents actual deletion before 2555 days regardless
    expiration { days = 2556 }
  }
}

data "aws_iam_policy_document" "cloudtrail_bucket" {
  statement {
    sid     = "AWSCloudTrailAclCheck"
    effect  = "Allow"
    actions = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.cloudtrail.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.management.account_id}:trail/mbank-org-trail"]
    }
  }

  statement {
    sid     = "AWSCloudTrailWrite"
    effect  = "Allow"
    actions = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.cloudtrail.arn}/AWSLogs/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.management.account_id}:trail/mbank-org-trail"]
    }
  }

  statement {
    sid     = "DenyNonHTTPS"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [aws_s3_bucket.cloudtrail.arn, "${aws_s3_bucket.cloudtrail.arn}/*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket     = aws_s3_bucket.cloudtrail.id
  policy     = data.aws_iam_policy_document.cloudtrail_bucket.json
  depends_on = [aws_s3_bucket_public_access_block.cloudtrail]
}

# ── CloudWatch Logs ────────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/aws/cloudtrail/mbank-org"
  retention_in_days = 2557  # nearest valid CW value to 7 years
  kms_key_id        = aws_kms_key.cloudtrail.arn
  tags              = local.common_tags
}

data "aws_iam_policy_document" "cloudtrail_cw_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.management.account_id}:trail/mbank-org-trail"]
    }
  }
}

data "aws_iam_policy_document" "cloudtrail_cw_write" {
  statement {
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.cloudtrail.arn}:*"]
  }
}

resource "aws_iam_role" "cloudtrail_cw" {
  name               = "mbank-cloudtrail-cw-role"
  assume_role_policy = data.aws_iam_policy_document.cloudtrail_cw_assume.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy" "cloudtrail_cw" {
  name   = "cloudtrail-cw-logs-write"
  role   = aws_iam_role.cloudtrail_cw.id
  policy = data.aws_iam_policy_document.cloudtrail_cw_write.json
}

# ── SNS for management-event notifications ────────────────────────────────────

resource "aws_sns_topic" "cloudtrail_events" {
  name              = "mbank-cloudtrail-management-events"
  kms_master_key_id = aws_kms_key.cloudtrail.arn
  tags              = local.common_tags
}

resource "aws_sns_topic_subscription" "cloudtrail_email" {
  topic_arn = aws_sns_topic.cloudtrail_events.arn
  protocol  = "email"
  endpoint  = var.security_alert_email
}

# ── Org-level CloudTrail ───────────────────────────────────────────────────────

resource "aws_cloudtrail" "org" {
  name                          = "mbank-org-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = true
  is_organization_trail         = true
  enable_log_file_validation    = true
  kms_key_id                    = aws_kms_key.cloudtrail.arn
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.cloudtrail_cw.arn
  sns_topic_name                = aws_sns_topic.cloudtrail_events.name

  # Data events: S3 write + Lambda invoke for compliance evidence
  event_selector {
    read_write_type           = "WriteOnly"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3"]  # all buckets in all member accounts
    }

    data_resource {
      type   = "AWS::Lambda::Function"
      values = ["arn:aws:lambda"]  # all Lambda functions
    }
  }

  depends_on = [
    aws_s3_bucket_policy.cloudtrail,
    aws_iam_role.cloudtrail_cw,
  ]

  tags = merge(local.common_tags, { Name = "mbank-org-trail" })
}
