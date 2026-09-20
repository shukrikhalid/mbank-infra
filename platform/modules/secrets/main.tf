# Task 11e — Secrets Terraform module

locals {
  tags = merge(
    var.tags,
    {
      Application = var.app_name
      Environment = var.environment
      Team        = var.team
      CostCentre  = var.cost_centre
      Module      = "secrets"
    }
  )
}

# Create secrets
resource "aws_secretsmanager_secret" "secrets" {
  for_each = toset(var.secret_names)

  name                    = each.value
  description             = "Secret: ${each.value} for ${var.app_name}"
  kms_key_id              = var.kms_key_id
  recovery_window_in_days = 7
  
  # Force overwrite if the secret exists
  force_overwrite_replica_secret = false

  tags = merge(local.tags, {
    SecretName = each.value
  })
}

# Bucket policy for each secret — restrict access to allowed principals only
resource "aws_secretsmanager_secret_policy" "policy" {
  for_each = toset(var.secret_names)

  secret_id = aws_secretsmanager_secret.secrets[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyInsecureTransport"
        Effect = "Deny"
        Principal = "*"
        Action   = "secretsmanager:*"
        Resource = "*"
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
      {
        Sid    = "AllowPrincipals"
        Effect = "Allow"
        Principal = {
          AWS = var.allowed_principal_arns
        }
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "*"
      }
    ]
  })
}

# Rotation (if enabled)
resource "aws_secretsmanager_secret_rotation" "rotation" {
  for_each = var.enable_rotation ? toset(var.secret_names) : toset([])

  secret_id = aws_secretsmanager_secret.secrets[each.key].id

  rotation_rules {
    automatically_after_days = var.rotation_days
  }

  rotation_lambda_arn = var.rotation_lambda_arn
}

# SSM Parameters for secret ARN discovery
resource "aws_ssm_parameter" "secret_arns" {
  for_each = toset(var.secret_names)

  name        = "/secrets/${var.app_name}/${each.value}/arn"
  description = "Secret ARN for ${each.value}"
  type        = "String"
  value       = aws_secretsmanager_secret.secrets[each.key].arn

  tags = local.tags
}
