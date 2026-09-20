# Task 11d — S3 Bucket Terraform module

locals {
  tags = merge(
    var.tags,
    {
      Application    = var.app_name
      Environment    = var.environment
      Team           = var.team
      CostCentre     = var.cost_centre
      Classification = var.data_classification
      Module         = "s3-bucket"
    }
  )

  # Generate unique bucket name: app-suffix-env-accountid
  bucket_name = "${var.app_name}-${var.bucket_name_suffix}-${var.environment}-${data.aws_caller_identity.current.account_id}"
}

data "aws_caller_identity" "current" {}

# S3 Bucket
resource "aws_s3_bucket" "bucket" {
  bucket = local.bucket_name

  tags = merge(local.tags, {
    Name = local.bucket_name
  })
}

# Versioning
resource "aws_s3_bucket_versioning" "bucket" {
  bucket = aws_s3_bucket.bucket.id

  versioning_configuration {
    status     = var.versioning_enabled ? "Enabled" : "Suspended"
    mfa_delete = var.environment == "prod" && var.versioning_enabled ? "Enabled" : "Disabled"
  }
}

# Encryption at rest (KMS)
resource "aws_s3_bucket_server_side_encryption_configuration" "bucket" {
  bucket = aws_s3_bucket.bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = "arn:aws:kms:ap-southeast-5:${data.aws_caller_identity.current.account_id}:key/${var.kms_key_id}"
    }
    bucket_key_enabled = true
  }
}

# Block Public Access (enforced, cannot be disabled)
resource "aws_s3_bucket_public_access_block" "bucket" {
  bucket = aws_s3_bucket.bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle Policy
resource "aws_s3_bucket_lifecycle_configuration" "bucket" {
  bucket = aws_s3_bucket.bucket.id

  depends_on = [aws_s3_bucket_versioning.bucket]

  rule {
    id     = "transition-to-ia"
    status = "Enabled"

    transition {
      days          = var.lifecycle_transition_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.lifecycle_transition_days + 60  # 90 days total
      storage_class = "GLACIER"
    }

    dynamic "expiration" {
      for_each = var.lifecycle_expiration_days != null ? [1] : []
      content {
        days = var.lifecycle_expiration_days
      }
    }

    # Clean up incomplete multipart uploads
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    # Clean up delete markers
    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_transition {
      noncurrent_days = 90
      storage_class   = "GLACIER"
    }

    dynamic "noncurrent_version_expiration" {
      for_each = var.lifecycle_expiration_days != null ? [1] : []
      content {
        noncurrent_days = var.lifecycle_expiration_days
      }
    }
  }
}

# Logging (if bucket provided)
resource "aws_s3_bucket_logging" "bucket" {
  count  = var.logging_bucket_name != "" ? 1 : 0
  bucket = aws_s3_bucket.bucket.id

  target_bucket = var.logging_bucket_name
  target_prefix = "${var.app_name}/${var.environment}/"
}

# Bucket Policy — Deny non-HTTPS
resource "aws_s3_bucket_policy" "deny_insecure_transport" {
  bucket = aws_s3_bucket.bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyInsecureTransport"
        Effect = "Deny"
        Principal = "*"
        Action = "s3:*"
        Resource = [
          aws_s3_bucket.bucket.arn,
          "${aws_s3_bucket.bucket.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# Replication (if enabled for prod)
resource "aws_s3_bucket_replication_configuration" "bucket" {
  count  = var.enable_replication && var.environment == "prod" ? 1 : 0
  bucket = aws_s3_bucket.bucket.id

  depends_on = [aws_s3_bucket_versioning.bucket]

  role = aws_iam_role.replication[0].arn

  rule {
    id       = "replicate-all-objects"
    status   = "Enabled"
    priority = 1

    filter {
      prefix = ""
    }

    destination {
      bucket       = var.replication_destination_bucket_arn
      storage_class = "STANDARD"

      replication_time {
        status = "Enabled"
        time {
          minutes = 15
        }
      }

      metrics {
        status = "Enabled"
        event_threshold {
          minutes = 15
        }
      }
    }
  }
}

# IAM Role for Replication
resource "aws_iam_role" "replication" {
  count = var.enable_replication && var.environment == "prod" ? 1 : 0
  name  = "${var.app_name}-s3-replication-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "replication" {
  count  = var.enable_replication && var.environment == "prod" ? 1 : 0
  name   = "${var.app_name}-s3-replication-policy"
  role   = aws_iam_role.replication[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.bucket.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl"
        ]
        Resource = "${aws_s3_bucket.bucket.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete"
        ]
        Resource = "${var.replication_destination_bucket_arn}/*"
      }
    ]
  })
}
