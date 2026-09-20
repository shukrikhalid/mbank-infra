# Task 11b — DynamoDB Terraform module

locals {
  tags = merge(
    var.tags,
    {
      Application = var.app_name
      Environment = var.environment
      Team        = var.team
      CostCentre  = var.cost_centre
      Module      = "dynamodb"
    }
  )
  
  # Automatically append account ID to table name for uniqueness
  full_table_name = "${var.table_name}-${data.aws_caller_identity.current.account_id}"
}

data "aws_caller_identity" "current" {}

# DynamoDB Table
resource "aws_dynamodb_table" "table" {
  name             = local.full_table_name
  billing_mode     = var.billing_mode
  hash_key         = var.hash_key
  range_key        = var.range_key != "" ? var.range_key : null
  stream_enabled   = var.enable_streams
  stream_view_type = var.enable_streams ? var.stream_view_type : null

  # Read/Write capacity for PROVISIONED mode
  dynamic "read_capacity" {
    for_each = var.billing_mode == "PROVISIONED" ? [1] : []
    content {
      value = var.read_capacity
    }
  }

  dynamic "write_capacity" {
    for_each = var.billing_mode == "PROVISIONED" ? [1] : []
    content {
      value = var.write_capacity
    }
  }

  # Attributes
  attribute {
    name = var.hash_key
    type = var.hash_key_type
  }

  dynamic "attribute" {
    for_each = var.range_key != "" ? [var.range_key] : []
    content {
      name = attribute.value
      type = var.range_key_type
    }
  }

  # Global Secondary Indexes
  dynamic "global_secondary_index" {
    for_each = var.global_secondary_indexes
    content {
      name            = global_secondary_index.value.name
      hash_key        = global_secondary_index.value.hash_key
      range_key       = global_secondary_index.value.range_key
      projection_type = global_secondary_index.value.projection_type
      read_capacity   = var.billing_mode == "PROVISIONED" ? global_secondary_index.value.read_capacity : null
      write_capacity  = var.billing_mode == "PROVISIONED" ? global_secondary_index.value.write_capacity : null
    }
  }

  # Encryption at rest
  server_side_encryption {
    enabled     = var.enable_encryption
    kms_key_arn = var.enable_encryption ? "arn:aws:kms:ap-southeast-5:${data.aws_caller_identity.current.account_id}:key/${var.kms_key_id}" : null
  }

  # Point-in-time recovery
  point_in_time_recovery_specification {
    point_in_time_recovery_enabled = true
  }

  # TTL
  dynamic "ttl" {
    for_each = var.ttl_attribute != "" ? [var.ttl_attribute] : []
    content {
      attribute_name = ttl.value
      enabled        = true
    }
  }

  # Deletion protection
  deletion_protection_enabled = var.environment == "prod" ? true : false

  tags = merge(local.tags, {
    Name = local.full_table_name
  })

  # Cross-region replica for prod
  dynamic "replica" {
    for_each = var.environment == "prod" ? [1] : []
    content {
      region_name = "ap-southeast-2"
    }
  }
}

# Application Auto Scaling for PROVISIONED mode
resource "aws_appautoscaling_target" "table" {
  count              = var.billing_mode == "PROVISIONED" ? 1 : 0
  max_capacity       = 40000
  min_capacity       = var.read_capacity
  resource_id        = "table/${aws_dynamodb_table.table.name}"
  scalable_dimension = "dynamodb:table:ReadCapacityUnits"
  service_namespace  = "dynamodb"
}

resource "aws_appautoscaling_policy" "table_read" {
  count              = var.billing_mode == "PROVISIONED" ? 1 : 0
  name               = "${var.app_name}-read-scaling-${var.environment}"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.table[0].resource_id
  scalable_dimension = aws_appautoscaling_target.table[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.table[0].service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = 70.0
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBReadCapacityUtilization"
    }
    scale_out_cooldown  = 60
    scale_in_cooldown   = 300
  }
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "read_throttle" {
  alarm_name          = "${var.app_name}-dynamodb-read-throttle-${var.environment}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "ReadThrottleEvents"
  namespace           = "AWS/DynamoDB"
  period              = 300
  statistic           = "Sum"
  threshold           = var.alarm_read_throttle_threshold
  alarm_description   = "Alert when read throttle events >= ${var.alarm_read_throttle_threshold}"

  dimensions = {
    TableName = aws_dynamodb_table.table.name
  }

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "write_throttle" {
  alarm_name          = "${var.app_name}-dynamodb-write-throttle-${var.environment}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "WriteThrottleEvents"
  namespace           = "AWS/DynamoDB"
  period              = 300
  statistic           = "Sum"
  threshold           = var.alarm_write_throttle_threshold
  alarm_description   = "Alert when write throttle events >= ${var.alarm_write_throttle_threshold}"

  dimensions = {
    TableName = aws_dynamodb_table.table.name
  }

  tags = local.tags
}

# AWS Backup Plan
resource "aws_backup_vault" "dynamodb" {
  name = "${var.app_name}-dynamodb-vault-${var.environment}"

  tags = local.tags
}

resource "aws_backup_plan" "dynamodb" {
  name = "${var.app_name}-dynamodb-backup-${var.environment}"

  rule {
    rule_name                 = "daily_backup"
    target_backup_vault_name  = aws_backup_vault.dynamodb.name
    schedule                  = "cron(0 2 * * ? *)"
    start_window              = 60
    completion_window         = 120

    lifecycle {
      delete_after = 35
    }
  }

  tags = local.tags
}

resource "aws_backup_selection" "dynamodb" {
  name         = "${var.app_name}-dynamodb-selection-${var.environment}"
  plan_id      = aws_backup_plan.dynamodb.id
  iam_role_arn = aws_iam_role.backup_role.arn
  resources    = [aws_dynamodb_table.table.arn]
}

resource "aws_iam_role" "backup_role" {
  name = "${var.app_name}-dynamodb-backup-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "backup_policy" {
  role       = aws_iam_role.backup_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForDynamoDB"
}
