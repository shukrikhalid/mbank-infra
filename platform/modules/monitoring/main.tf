# Task 11g — Monitoring Terraform module

locals {
  tags = merge(
    var.tags,
    {
      Application = var.app_name
      Environment = var.environment
      Team        = var.team
      CostCentre  = var.cost_centre
      Module      = "monitoring"
    }
  )
}

data "aws_caller_identity" "current" {}

# SNS Topic for alarms
resource "aws_sns_topic" "alarms" {
  name              = "${var.app_name}-alarms-${var.environment}"
  kms_master_key_id = var.kms_key_id

  tags = local.tags
}

# SNS Topic Policy
resource "aws_sns_topic_policy" "alarms" {
  arn = aws_sns_topic.alarms.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.alarms.arn
      }
    ]
  })
}

# Fetch PagerDuty service key if configured
data "aws_secretsmanager_secret_version" "pagerduty" {
  count     = var.pagerduty_service_key_secret != "" ? 1 : 0
  secret_id = var.pagerduty_service_key_secret
}

# SNS Subscription to PagerDuty
resource "aws_sns_topic_subscription" "pagerduty" {
  count     = var.pagerduty_service_key_secret != "" ? 1 : 0
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "https"
  endpoint  = "https://events.pagerduty.com/v2/enqueue"

  filter_policy = jsonencode({
    AlarmName = [{ prefix = var.app_name }]
  })
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "cpu_utilization" {
  alarm_name          = "${var.app_name}-cpu-high-${var.environment}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Average"
  threshold           = var.alarm_cpu_threshold
  alarm_description   = "CPU utilization above ${var.alarm_cpu_threshold}%"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "memory_utilization" {
  alarm_name          = "${var.app_name}-memory-high-${var.environment}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Average"
  threshold           = var.alarm_memory_threshold
  alarm_description   = "Memory utilization above ${var.alarm_memory_threshold}%"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "error_5xx_rate" {
  alarm_name          = "${var.app_name}-5xx-errors-${var.environment}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = var.alarm_5xx_threshold
  alarm_description   = "5xx errors above ${var.alarm_5xx_threshold} per 5 minutes"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "target_response_time" {
  alarm_name          = "${var.app_name}-latency-p99-${var.environment}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Average"
  threshold           = var.alarm_latency_p99_ms / 1000  # Convert to seconds
  alarm_description   = "P99 latency above ${var.alarm_latency_p99_ms}ms"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${var.app_name}-unhealthy-hosts-${var.environment}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 1
  alarm_description   = "Alert immediately when any host becomes unhealthy"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  treat_missing_data = "notBreaching"

  tags = local.tags
}

# CloudWatch Log Metric Filter for ERROR logs
resource "aws_cloudwatch_log_group" "app" {
  name              = "/app/${var.app_name}/${var.environment}"
  retention_in_days = var.environment == "prod" ? 90 : 30
  kms_key_id        = "arn:aws:kms:ap-southeast-5:${data.aws_caller_identity.current.account_id}:key/${var.kms_key_id}"

  tags = local.tags
}

resource "aws_cloudwatch_log_metric_filter" "errors" {
  name           = "${var.app_name}-errors-${var.environment}"
  log_group_name = aws_cloudwatch_log_group.app.name
  filter_pattern = "[ERROR]"

  metric_transformation {
    name      = "${var.app_name}-error-count"
    namespace = "Application/${var.app_name}"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "log_errors" {
  alarm_name          = "${var.app_name}-log-errors-${var.environment}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "${var.app_name}-error-count"
  namespace           = "Application/${var.app_name}"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "ERROR log entries >= 10 in 5 minutes"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  treat_missing_data = "notBreaching"

  tags = local.tags
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "main" {
  count          = var.enable_dashboard ? 1 : 0
  dashboard_name = "${var.app_name}-dashboard-${var.environment}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", { stat = "Sum" }],
            [".", "TargetResponseTime", { stat = "Average" }],
            [".", "HTTPCode_Target_4XX_Count", { stat = "Sum" }],
            [".", "HTTPCode_Target_5XX_Count", { stat = "Sum" }],
            [".", "CPUUtilization", { stat = "Average" }],
            [".", "MemoryUtilization", { stat = "Average" }]
          ]
          period = 60
          stat   = "Average"
          region = "ap-southeast-5"
          title  = "${var.app_name} - Overview"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      }
    ]
  })
}
