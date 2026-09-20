# Task 9 — EC2 Auto Scaling Terraform module
# Provisions EC2 instances with Auto Scaling Group, ALB, and monitoring

locals {
  app_name_normalized = replace(var.app_name, "-", "_")
  tags = merge(
    var.tags,
    {
      Application  = var.app_name
      Environment  = var.environment
      Team         = var.team
      CostCentre   = var.cost_centre
      Classification = var.data_classification
      Module       = "ec2-autoscaling"
    }
  )
}

# IAM Role for EC2 instances
resource "aws_iam_role" "instance_role" {
  name = "${var.app_name}-ec2-instance-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = local.tags
}

# IAM Policy for SSM access
resource "aws_iam_role_policy_attachment" "ssm_managed_instance" {
  count      = var.enable_ssm ? 1 : 0
  role       = aws_iam_role.instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# IAM Policy for CloudWatch
resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# IAM Policy for Secrets Manager read
resource "aws_iam_role_policy" "secrets_read" {
  name = "${var.app_name}-secrets-read-${var.environment}"
  role = aws_iam_role.instance_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "arn:aws:secretsmanager:*:*:secret:/mbank/${var.app_name}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "instance_profile" {
  name = "${var.app_name}-instance-profile-${var.environment}"
  role = aws_iam_role.instance_role.name
}

# Security Group for EC2 instances
resource "aws_security_group" "instance_sg" {
  name        = "${var.app_name}-instance-sg-${var.environment}"
  description = "Security group for ${var.app_name} EC2 instances"
  vpc_id      = var.vpc_id

  # Inbound from ALB on app port
  ingress {
    description     = "ALB to application"
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  # Outbound allow all
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${var.app_name}-instance-sg-${var.environment}"
  })
}

# Security Group for ALB
resource "aws_security_group" "alb_sg" {
  name        = "${var.app_name}-alb-sg-${var.environment}"
  description = "Security group for ${var.app_name} ALB"
  vpc_id      = var.vpc_id

  # Inbound HTTP from VPC
  ingress {
    description = "HTTP from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.vpc.cidr_block]
  }

  # Inbound HTTPS from VPC
  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.vpc.cidr_block]
  }

  # Outbound allow all
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${var.app_name}-alb-sg-${var.environment}"
  })
}

# Data source for VPC CIDR
data "aws_vpc" "vpc" {
  id = var.vpc_id
}

# CloudWatch Log Group for CloudWatch Agent
resource "aws_cloudwatch_log_group" "agent_logs" {
  name              = "/ec2/${var.app_name}-${var.environment}/agent"
  retention_in_days = var.environment == "prod" ? 90 : 30
  kms_key_id        = var.kms_key_id

  tags = local.tags
}

# SSM Parameter for CloudWatch Agent Config
resource "aws_ssm_parameter" "cw_agent_config" {
  name        = "/ec2/${var.app_name}/${var.environment}/cloudwatch-config"
  description = "CloudWatch Agent configuration for ${var.app_name}"
  type        = "String"
  value = jsonencode({
    metrics = {
      namespace   = "${var.app_name}/${var.environment}"
      metrics_collected = {
        cpu = {
          measurement = [
            { name = "cpu_usage_idle", rename = "CPU_USAGE_IDLE", unit = "Percent" },
            { name = "cpu_usage_iowait", rename = "CPU_USAGE_IOWAIT", unit = "Percent" },
            "cpu_time_guest"
          ]
          totalcpu = false
          metrics_collection_interval = 60
        }
        mem = {
          measurement = [
            { name = "mem_used_percent", rename = "MEM_USAGE_PERCENT", unit = "Percent" }
          ]
          metrics_collection_interval = 60
        }
        disk = {
          measurement = [
            { name = "used_percent", rename = "DISK_USAGE_PERCENT", unit = "Percent" }
          ]
          metrics_collection_interval = 60
          resources = ["/"]
        }
      }
    }
    logs = {
      logs_collected = {
        files = {
          collect_list = [
            {
              file_path       = "/var/log/cloud-init-output.log"
              log_group_name  = aws_cloudwatch_log_group.agent_logs.name
              log_stream_name = "{instance_id}/cloud-init"
            },
            {
              file_path       = "/var/log/messages"
              log_group_name  = aws_cloudwatch_log_group.agent_logs.name
              log_stream_name = "{instance_id}/syslog"
            }
          ]
        }
      }
    }
  })

  tags = local.tags
}

# Launch Template
resource "aws_launch_template" "instance" {
  name_prefix   = "${var.app_name}-lt-"
  image_id      = var.ami_id
  instance_type = var.instance_type

  # IMDSv2 required
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"  # IMDSv2 only
    http_put_response_hop_limit = 1
  }

  # IAM Instance Profile
  iam_instance_profile {
    arn = aws_iam_instance_profile.instance_profile.arn
  }

  # Root volume: EBS gp3, encrypted, 30 GB
  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 30
      volume_type           = "gp3"
      encrypted             = true
      kms_key_id            = var.kms_key_id
      delete_on_termination = true
      iops                  = 3000
      throughput            = 125
    }
  }

  # SSH key only if specified (not recommended for prod)
  key_name = var.key_name != "" ? var.key_name : null

  # Security group
  vpc_security_group_ids = [aws_security_group.instance_sg.id]

  # User data: Install SSM agent, CloudWatch agent, and custom script
  user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    cw_config_param = aws_ssm_parameter.cw_agent_config.name
    user_data_b64   = var.user_data_b64
  }))

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.tags, {
      Name = "${var.app_name}-instance-${var.environment}"
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = local.tags
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "asg" {
  name                = "${var.app_name}-asg-${var.environment}"
  vpc_zone_identifier = slice(var.private_subnet_ids, 0, 3)
  target_group_arns   = [aws_lb_target_group.app.arn]
  health_check_type   = "ELB"
  health_check_grace_period = 300
  min_size            = var.min_size
  max_size            = var.max_size
  desired_capacity    = var.desired_capacity

  launch_template {
    id      = aws_launch_template.instance.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 80
      instance_warmup        = 300
    }
  }

  lifecycle {
    create_before_destroy = true
  }

  tag {
    key                 = "Name"
    value               = "${var.app_name}-asg-${var.environment}"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = local.tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}

# Application Load Balancer (internal)
resource "aws_lb" "alb" {
  name               = "${var.app_name}-alb-${var.environment}"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = var.private_subnet_ids

  enable_deletion_protection = var.environment == "prod" ? true : false
  enable_http2               = true
  enable_cross_zone_load_balancing = true

  tags = merge(local.tags, {
    Name = "${var.app_name}-alb-${var.environment}"
  })
}

# ALB Target Group
resource "aws_lb_target_group" "app" {
  name_prefix = substr(replace(var.app_name, "-", ""), 0, 6)
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = var.health_check_path
    matcher             = "200-399"
    port                = "traffic-port"
  }

  deregistration_delay = 30

  tags = merge(local.tags, {
    Name = "${var.app_name}-tg-${var.environment}"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ALB Listener
resource "aws_lb_listener" "app" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# Auto Scaling Policy - Target Tracking
resource "aws_autoscaling_policy" "cpu_target_tracking" {
  name                   = "${var.app_name}-cpu-tracking-${var.environment}"
  autoscaling_group_name = aws_autoscaling_group.asg.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 70.0
  }
}

# CloudWatch Alarms - CPU High
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.app_name}-cpu-high-${var.environment}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = var.alarm_cpu_threshold
  alarm_description   = "Alert when CPU exceeds ${var.alarm_cpu_threshold}%"
  alarm_actions       = var.environment == "prod" ? [] : []

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.asg.name
  }
}

# CloudWatch Alarms - CPU Low
resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "${var.app_name}-cpu-low-${var.environment}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = var.alarm_cpu_threshold * 0.3
  alarm_description   = "Alert when CPU drops below 30% of threshold"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.asg.name
  }
}

# CloudWatch Alarms - Unhealthy Host Count
resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${var.app_name}-unhealthy-hosts-${var.environment}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Average"
  threshold           = 1
  alarm_description   = "Alert when unhealthy host count >= 1"

  dimensions = {
    LoadBalancer = aws_lb.alb.arn_suffix
    TargetGroup  = aws_lb_target_group.app.arn_suffix
  }
}
