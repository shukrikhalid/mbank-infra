# Task 11f — WAF Terraform module

locals {
  tags = merge(
    var.tags,
    {
      Application = var.app_name
      Environment = var.environment
      Team        = var.team
      CostCentre  = var.cost_centre
      Module      = "waf"
    }
  )
}

data "aws_caller_identity" "current" {}

# IP Set for blocked IPs
resource "aws_wafv2_ip_set" "blocked_ips" {
  scope              = var.scope
  name               = "${var.app_name}-blocked-ips-${var.environment}"
  description        = "Blocked IP addresses for ${var.app_name}"
  ip_address_version = "IPV4"
  addresses          = var.block_ips

  tags = local.tags
}

# Web ACL
resource "aws_wafv2_web_acl" "main" {
  name        = "${var.app_name}-acl-${var.environment}"
  description = "Web ACL for ${var.app_name}"
  scope       = var.scope

  default_action {
    allow {}
  }

  # AWS Managed Rule: Common Rule Set
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 0

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
        
        excluded_rule {
          name = "SizeRestrictions_BODY"
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.app_name}-common-rule-set"
      sampled_requests_enabled   = true
    }
  }

  # AWS Managed Rule: SQL Injection Protection
  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.app_name}-sql-injection"
      sampled_requests_enabled   = true
    }
  }

  # AWS Managed Rule: Known Bad Inputs
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.app_name}-known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  # AWS Managed Rule: IP Reputation List
  rule {
    name     = "AWSManagedRulesAmazonIpReputationList"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.app_name}-ip-reputation"
      sampled_requests_enabled   = true
    }
  }

  # Custom IP blocklist
  rule {
    name     = "BlockCustomIPs"
    priority = 4
    action {
      block {}
    }

    statement {
      ip_set_reference_statement {
        arn = aws_wafv2_ip_set.blocked_ips.arn
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.app_name}-blocked-ips"
      sampled_requests_enabled   = true
    }
  }

  # Rate limiting
  rule {
    name     = "RateLimit"
    priority = 5
    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.app_name}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  # Geo-blocking (if countries specified)
  dynamic "rule" {
    for_each = length(var.allowed_countries) > 0 ? [1] : []
    content {
      name     = "GeoBlocking"
      priority = 6
      action {
        block {}
      }

      statement {
        geo_match_statement {
          country_codes = var.allowed_countries
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.app_name}-geo-block"
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.app_name}-waf-acl"
    sampled_requests_enabled   = true
  }

  tags = local.tags
}

# WAF Association (for REGIONAL scope only)
resource "aws_wafv2_web_acl_association" "alb" {
  count        = var.scope == "REGIONAL" && var.alb_arn != "" ? 1 : 0
  resource_arn = var.alb_arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}

# CloudWatch Log Group for WAF logs
resource "aws_cloudwatch_log_group" "waf" {
  name              = "/aws/wafv2/${var.app_name}-${var.environment}"
  retention_in_days = var.environment == "prod" ? 90 : 30
  kms_key_id        = "arn:aws:kms:ap-southeast-5:${data.aws_caller_identity.current.account_id}:key/${var.kms_key_id}"

  tags = local.tags
}

# CloudWatch Log Group resource policy
resource "aws_cloudwatch_log_resource_policy" "waf" {
  policy_name = "${var.app_name}-waf-log-policy-${var.environment}"

  policy_text = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "wafv2.amazonaws.com"
        }
        Action   = "logs:PutLogEvents"
        Resource = "${aws_cloudwatch_log_group.waf.arn}:*"
      }
    ]
  })
}

# WAF Logging Configuration
resource "aws_wafv2_web_acl_logging_configuration" "waf" {
  resource_arn            = aws_wafv2_web_acl.main.arn
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]

  redacted_fields {
    single_header {
      name = "authorization"
    }
  }

  logging_filter {
    default_behavior = "KEEP"

    filter {
      behavior = "KEEP"
      condition {
        action_condition {
          action = "BLOCK"
        }
      }
      requirement = "MEETS_ANY"
    }
  }
}

# CloudWatch Alarm for blocked requests spike
resource "aws_cloudwatch_metric_alarm" "blocked_requests" {
  alarm_name          = "${var.app_name}-waf-blocked-spike-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "BlockedRequests"
  namespace           = "AWS/WAFV2"
  period              = 300
  statistic           = "Sum"
  threshold           = 100
  alarm_description   = "Alert when WAF blocks > 100 requests in 5 minutes"

  dimensions = {
    WebACL = aws_wafv2_web_acl.main.name
    Rule   = "ALL"
    Region = "ap-southeast-5"
  }

  tags = local.tags
}
