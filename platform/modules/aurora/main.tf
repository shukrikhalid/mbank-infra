# Task 11a — Aurora RDS Terraform module

locals {
  tags = merge(
    var.tags,
    {
      Application = var.app_name
      Environment = var.environment
      Team        = var.team
      CostCentre  = var.cost_centre
      Module      = "aurora"
    }
  )
  
  db_port = contains(["aurora-postgresql"], var.engine) ? 5432 : 3306
}

# RDS DB Subnet Group
resource "aws_db_subnet_group" "aurora" {
  name       = "${var.app_name}-db-subnet-${var.environment}"
  subnet_ids = var.private_subnet_ids

  tags = merge(local.tags, {
    Name = "${var.app_name}-db-subnet-${var.environment}"
  })
}

# Security Group for RDS
resource "aws_security_group" "aurora" {
  name        = "${var.app_name}-db-sg-${var.environment}"
  description = "Security group for ${var.app_name} Aurora database"
  vpc_id      = var.vpc_id

  # Ingress from compute layer
  ingress {
    description              = "Database from compute layer"
    from_port                = local.db_port
    to_port                  = local.db_port
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
    Name = "${var.app_name}-db-sg-${var.environment}"
  })
}

# Random password for master username
resource "random_password" "master_password" {
  length  = 32
  special = true
}

# Secrets Manager secret for database credentials
resource "aws_secretsmanager_secret" "db_password" {
  name                    = "/rds/${var.app_name}/${var.environment}/db-password"
  description             = "RDS master password for ${var.app_name}"
  kms_key_id              = var.kms_key_id
  recovery_window_in_days = 7

  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id = aws_secretsmanager_secret.db_password.id
  secret_string = jsonencode({
    username = var.master_username
    password = random_password.master_password.result
    engine   = var.engine
    host     = aws_rds_cluster.aurora.endpoint
    port     = local.db_port
    dbname   = var.db_name
  })
}

# DB Parameter Group
resource "aws_db_parameter_group" "aurora" {
  family      = var.engine == "aurora-postgresql" ? "aurora-postgresql15" : "aurora-mysql8.0"
  name        = "${var.app_name}-db-params-${var.environment}"
  description = "Database parameter group for ${var.app_name}"

  # PostgreSQL specific settings
  dynamic "parameter" {
    for_each = var.engine == "aurora-postgresql" ? [
      { name = "log_statement", value = "all" },
      { name = "log_duration", value = "on" },
      { name = "log_min_duration_statement", value = "1000" },
      { name = "shared_preload_libraries", value = "pgaudit,pg_stat_statements" }
    ] : []
    content {
      name  = parameter.value.name
      value = parameter.value.value
    }
  }

  # MySQL specific settings
  dynamic "parameter" {
    for_each = var.engine == "aurora-mysql" ? [
      { name = "general_log", value = "0" },
      { name = "slow_query_log", value = "1" },
      { name = "long_query_time", value = "2" },
      { name = "log_queries_not_using_indexes", value = "1" }
    ] : []
    content {
      name  = parameter.value.name
      value = parameter.value.value
    }
  }

  tags = local.tags
}

# RDS Cluster Parameter Group
resource "aws_rds_cluster_parameter_group" "aurora" {
  family      = var.engine == "aurora-postgresql" ? "aurora-postgresql15" : "aurora-mysql8.0"
  name        = "${var.app_name}-cluster-params-${var.environment}"
  description = "Cluster parameter group for ${var.app_name}"

  parameter {
    name  = "enabled_cloudwatch_logs_exports"
    value = var.engine == "aurora-postgresql" ? "postgresql" : "error,general,slowquery,audit"
  }

  tags = local.tags
}

# RDS Aurora Cluster
resource "aws_rds_cluster" "aurora" {
  cluster_identifier              = "${var.app_name}-cluster-${var.environment}"
  engine                          = var.engine
  engine_version                  = var.engine_version
  database_name                   = var.db_name
  master_username                 = var.master_username
  master_password                 = random_password.master_password.result
  db_subnet_group_name            = aws_db_subnet_group.aurora.name
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.aurora.name
  vpc_security_group_ids          = [aws_security_group.aurora.id]
  
  # Backup and retention
  backup_retention_period         = var.backup_retention_days
  preferred_backup_window         = "03:00-04:00"
  preferred_maintenance_window    = "sun:04:00-sun:05:00"
  
  # Security
  storage_encrypted               = true
  kms_key_id                      = var.kms_key_id
  deletion_protection             = var.deletion_protection
  
  # High availability
  availability_zones              = slice(data.aws_availability_zones.available.names, 0, length(var.private_subnet_ids))
  multi_az                        = var.environment == "prod" ? true : false
  
  # Backup and recovery
  skip_final_snapshot             = var.environment != "prod" ? true : false
  final_snapshot_identifier       = var.environment == "prod" ? "${var.app_name}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}" : null
  copy_tags_to_snapshot           = true
  
  # Point-in-time recovery
  backtrack_window                = var.engine == "aurora-mysql" ? 7 : 0
  enable_http_endpoint            = false
  
  # Monitoring and logging
  enable_cloudwatch_logs_exports  = var.engine == "aurora-postgresql" ? ["postgresql"] : ["error", "general", "slowquery", "audit"]
  enable_enhanced_monitoring      = true
  monitoring_interval             = 60
  monitoring_role_arn             = aws_iam_role.rds_monitoring.arn
  enable_iam_database_authentication = true
  
  # Performance Insights
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = var.kms_key_id
  performance_insights_retention_period = var.environment == "prod" ? 7 : 7

  tags = merge(local.tags, {
    Name = "${var.app_name}-cluster-${var.environment}"
  })

  depends_on = [
    aws_iam_role.rds_monitoring
  ]
}

# Data source for availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# IAM Role for Enhanced Monitoring
resource "aws_iam_role" "rds_monitoring" {
  name = "${var.app_name}-rds-monitoring-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# RDS Cluster Instances
resource "aws_rds_cluster_instance" "aurora" {
  count              = var.num_instances
  identifier         = "${var.app_name}-instance-${count.index + 1}-${var.environment}"
  cluster_identifier = aws_rds_cluster.aurora.id
  instance_class     = var.instance_class
  engine              = aws_rds_cluster.aurora.engine
  engine_version      = aws_rds_cluster.aurora.engine_version

  db_parameter_group_name = aws_db_parameter_group.aurora.name
  publicly_accessible     = false
  auto_minor_version_upgrade = var.environment == "prod" ? false : true
  monitoring_interval     = 60
  monitoring_role_arn     = aws_iam_role.rds_monitoring.arn
  performance_insights_enabled = true
  performance_insights_kms_key_id = var.kms_key_id

  # Writer is the first instance
  promotion_tier = count.index

  tags = merge(local.tags, {
    Name   = "${var.app_name}-instance-${count.index + 1}-${var.environment}"
    Role   = count.index == 0 ? "writer" : "reader"
  })
}

# RDS Proxy for connection pooling
resource "aws_db_proxy" "aurora" {
  count   = var.enable_rds_proxy ? 1 : 0
  name    = "${var.app_name}-proxy-${var.environment}"
  db_proxy_protocol_version = var.engine == "aurora-postgresql" ? "POSTGRES" : "MYSQL"
  engine_family             = var.engine == "aurora-postgresql" ? "POSTGRESQL" : "MYSQL"
  role_arn                  = aws_iam_role.proxy_role[0].arn
  
  auth {
    auth_scheme = "SECRETS"
    secret_arn  = aws_secretsmanager_secret.db_password.arn
  }

  max_connections           = 100
  max_idle_connections      = 10
  connection_borrow_timeout = 120
  session_pinning_filters   = []

  tags = local.tags
}

# Target group for RDS Proxy
resource "aws_db_proxy_target_group" "aurora" {
  count           = var.enable_rds_proxy ? 1 : 0
  db_proxy_name   = aws_db_proxy.aurora[0].name
  name            = "default"
  db_cluster_identifiers = [aws_rds_cluster.aurora.arn]

  connection_pool_config {
    connection_borrow_timeout    = 120
    session_pinning_filters      = []
    init_query                   = ""
    max_idle_connections         = 10
    max_connections              = 100
    max_connection_percent       = 100
  }
}

# IAM Role for RDS Proxy
resource "aws_iam_role" "proxy_role" {
  count = var.enable_rds_proxy ? 1 : 0
  name  = "${var.app_name}-proxy-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "rds.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "proxy_secrets" {
  count = var.enable_rds_proxy ? 1 : 0
  name  = "${var.app_name}-proxy-secrets-policy-${var.environment}"
  role  = aws_iam_role.proxy_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetResourcePolicy",
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecretVersionIds"
        ]
        Resource = aws_secretsmanager_secret.db_password.arn
      }
    ]
  })
}

# CloudWatch Log Group for RDS
resource "aws_cloudwatch_log_group" "aurora" {
  for_each = toset(
    var.engine == "aurora-postgresql" ? ["postgresql"] : ["error", "general", "slowquery", "audit"]
  )
  
  name              = "/aws/rds/cluster/${var.app_name}-${var.environment}/${each.key}"
  retention_in_days = var.environment == "prod" ? 90 : 30
  kms_key_id        = var.kms_key_id

  tags = local.tags
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.app_name}-db-cpu-high-${var.environment}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.alarm_cpu_threshold
  alarm_description   = "Alert when CPU exceeds ${var.alarm_cpu_threshold}%"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.aurora.cluster_identifier
  }

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "replica_lag" {
  count               = var.num_instances > 1 ? 1 : 0
  alarm_name          = "${var.app_name}-db-replica-lag-${var.environment}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "AuroraBinlogReplicaLag"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.alarm_replica_lag_threshold
  alarm_description   = "Alert when replica lag exceeds ${var.alarm_replica_lag_threshold}ms"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.aurora.cluster_identifier
  }

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "free_storage" {
  alarm_name          = "${var.app_name}-db-free-storage-${var.environment}"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 1073741824  # 1 GB
  alarm_description   = "Alert when free storage < 1GB"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.aurora.cluster_identifier
  }

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "db_connections" {
  alarm_name          = "${var.app_name}-db-connections-${var.environment}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Alert when database connections >= 80"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.aurora.cluster_identifier
  }

  tags = local.tags
}

# AWS Backup Plan
resource "aws_backup_vault" "aurora" {
  name        = "${var.app_name}-backup-vault-${var.environment}"
  kms_key_arn = "arn:aws:kms:ap-southeast-5:ACCOUNT_ID:key/${var.kms_key_id}"

  tags = local.tags
}

resource "aws_backup_plan" "aurora" {
  name = "${var.app_name}-backup-plan-${var.environment}"

  rule {
    rule_name         = "daily_backups"
    target_backup_vault_name = aws_backup_vault.aurora.name
    schedule          = "cron(0 2 * * ? *)"  # 2 AM UTC
    start_window      = 60
    completion_window = 120

    lifecycle {
      delete_after = var.backup_retention_days + 1
      cold_storage_after = var.environment == "prod" ? 30 : null
    }

    recovery_point_tags = local.tags
  }

  # Cross-region copy for prod
  dynamic "rule" {
    for_each = var.environment == "prod" ? [1] : []
    content {
      rule_name         = "cross_region_backup"
      target_backup_vault_name = aws_backup_vault.aurora.name
      schedule          = "cron(0 3 * * ? *)"
      start_window      = 60
      completion_window = 120

      copy_action {
        destination_vault_arn = "arn:aws:backup:ap-southeast-2:ACCOUNT_ID:backup-vault:${var.app_name}-backup-vault-dr"
        lifecycle {
          delete_after = var.backup_retention_days + 1
          cold_storage_after = 30
        }
      }
    }
  }

  tags = local.tags
}

resource "aws_backup_selection" "aurora" {
  name            = "${var.app_name}-selection-${var.environment}"
  plan_id         = aws_backup_plan.aurora.id
  iam_role_arn    = aws_iam_role.backup_role.arn
  resources       = [aws_rds_cluster.aurora.arn]

  selection_tag {
    key   = "Environment"
    value = var.environment
  }
}

resource "aws_iam_role" "backup_role" {
  name = "${var.app_name}-backup-role-${var.environment}"

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
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRDS"
}
