# Task 11c — ElastiCache Terraform module

locals {
  tags = merge(
    var.tags,
    {
      Application = var.app_name
      Environment = var.environment
      Team        = var.team
      CostCentre  = var.cost_centre
      Module      = "elasticache"
    }
  )
}

# Generate AUTH token
resource "random_password" "auth_token" {
  length  = 32
  special = false  # ElastiCache auth tokens don't support special characters
}

# Store AUTH token in Secrets Manager
resource "aws_secretsmanager_secret" "auth_token" {
  name                    = "/elasticache/${var.app_name}/${var.environment}/auth-token"
  description             = "ElastiCache AUTH token for ${var.app_name}"
  kms_key_id              = var.kms_key_id
  recovery_window_in_days = 7

  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "auth_token" {
  secret_id      = aws_secretsmanager_secret.auth_token.id
  secret_string  = random_password.auth_token.result
}

# ElastiCache Subnet Group
resource "aws_elasticache_subnet_group" "cache" {
  name       = "${var.app_name}-subnet-group-${var.environment}"
  subnet_ids = var.private_subnet_ids

  tags = merge(local.tags, {
    Name = "${var.app_name}-subnet-group-${var.environment}"
  })
}

# Security Group for ElastiCache
resource "aws_security_group" "cache" {
  name        = "${var.app_name}-cache-sg-${var.environment}"
  description = "Security group for ${var.app_name} ElastiCache"
  vpc_id      = var.vpc_id

  # Ingress from compute layer on port 6379 (Redis/Valkey default)
  ingress {
    description              = "Cache from compute layer"
    from_port                = 6379
    to_port                  = 6379
    protocol                 = "tcp"
    source_security_group_id = var.compute_sg_id
  }

  # Egress: allow all
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${var.app_name}-cache-sg-${var.environment}"
  })
}

# ElastiCache Replication Group
resource "aws_elasticache_replication_group" "cache" {
  replication_group_description = "${var.app_name} cache cluster ${var.environment}"
  engine                         = var.engine
  engine_version                 = var.engine_version
  node_type                      = var.node_type
  num_cache_clusters             = var.num_cache_nodes
  port                           = 6379
  parameter_group_name           = aws_elasticache_parameter_group.cache.name
  subnet_group_name              = aws_elasticache_subnet_group.cache.name
  security_group_ids             = [aws_security_group.cache.id]

  # Encryption
  at_rest_encryption_enabled = var.at_rest_encryption_enabled
  kms_key_id                 = var.at_rest_encryption_enabled ? "arn:aws:kms:ap-southeast-5:${data.aws_caller_identity.current.account_id}:key/${var.kms_key_id}" : null
  transit_encryption_enabled = var.transit_encryption_enabled
  transit_encryption_mode    = var.transit_encryption_enabled ? "preferred" : null
  auth_token                 = var.transit_encryption_enabled ? random_password.auth_token.result : null
  auth_token_update_strategy = "ROTATE"

  # High availability
  automatic_failover_enabled = var.automatic_failover_enabled
  multi_az_enabled          = var.multi_az_enabled
  
  # Backups and maintenance
  snapshot_retention_limit = var.snapshot_retention_limit
  snapshot_window          = "03:00-05:00"
  maintenance_window       = "sun:05:00-sun:07:00"
  notification_topic_arn   = aws_sns_topic.elasticache.arn
  
  # Automated updates
  auto_minor_version_upgrade = var.environment == "prod" ? false : true
  
  # Deletion protection
  deletion_protection_enabled = var.environment == "prod"

  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.slow_log.name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "slow-log"
    enabled          = true
  }

  tags = merge(local.tags, {
    Name = "${var.app_name}-replication-group-${var.environment}"
  })
}

data "aws_caller_identity" "current" {}

# ElastiCache Parameter Group
resource "aws_elasticache_parameter_group" "cache" {
  name   = "${var.app_name}-params-${var.environment}"
  family = var.engine == "redis" ? "redis7" : "valkey7"

  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }

  parameter {
    name  = "notify-keyspace-events"
    value = "Ex"
  }

  tags = local.tags
}

# CloudWatch Log Group for slow logs
resource "aws_cloudwatch_log_group" "slow_log" {
  name              = "/aws/elasticache/${var.app_name}/${var.environment}/slow-log"
  retention_in_days = var.environment == "prod" ? 90 : 30
  kms_key_id        = "arn:aws:kms:ap-southeast-5:${data.aws_caller_identity.current.account_id}:key/${var.kms_key_id}"

  tags = local.tags
}

# SNS Topic for ElastiCache notifications
resource "aws_sns_topic" "elasticache" {
  name              = "${var.app_name}-elasticache-notifications-${var.environment}"
  kms_master_key_id = var.kms_key_id

  tags = local.tags
}

resource "aws_sns_topic_policy" "elasticache" {
  arn = aws_sns_topic.elasticache.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "elasticache.amazonaws.com"
        }
        Action = "SNS:Publish"
        Resource = aws_sns_topic.elasticache.arn
      }
    ]
  })
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "cpu_utilization" {
  alarm_name          = "${var.app_name}-elasticache-cpu-${var.environment}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Average"
  threshold           = 75
  alarm_description   = "Alert when CPU utilization >= 75%"
  alarm_actions       = [aws_sns_topic.elasticache.arn]

  dimensions = {
    ReplicationGroupId = aws_elasticache_replication_group.cache.id
  }

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "memory_utilization" {
  alarm_name          = "${var.app_name}-elasticache-memory-${var.environment}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseMemoryUsagePercentage"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Average"
  threshold           = 85
  alarm_description   = "Alert when memory utilization >= 85%"
  alarm_actions       = [aws_sns_topic.elasticache.arn]

  dimensions = {
    ReplicationGroupId = aws_elasticache_replication_group.cache.id
  }

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "evictions" {
  alarm_name          = "${var.app_name}-elasticache-evictions-${var.environment}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Evictions"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Average"
  threshold           = 1000
  alarm_description   = "Alert when evictions >= 1000"
  alarm_actions       = [aws_sns_topic.elasticache.arn]

  dimensions = {
    ReplicationGroupId = aws_elasticache_replication_group.cache.id
  }

  tags = local.tags
}
