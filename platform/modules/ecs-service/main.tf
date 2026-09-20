# ── Locals ────────────────────────────────────────────────────────────────────

locals {
  prefix = "${var.app_name}-${var.environment}"

  tags = {
    Name               = local.prefix
    Environment        = var.environment
    Team               = var.team
    CostCentre         = var.cost_centre
    DataClassification = var.data_classification
    ManagedBy          = "terraform"
  }

  # Derive env var name from the last path segment of each secret ARN
  secret_definitions = [
    for arn in var.secrets_arns : {
      name      = upper(replace(reverse(split("/", element(split(":secret:", arn), 1)))[0], "-", "_"))
      valueFrom = arn
    }
  ]

  app_container = {
    name      = var.app_name
    image     = var.container_image
    essential = true
    portMappings = [{ containerPort = var.container_port, protocol = "tcp" }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.app.name
        "awslogs-region"        = data.aws_region.current.name
        "awslogs-stream-prefix" = "ecs"
      }
    }

    secrets = local.secret_definitions

    environment = concat(
      [
        { name = "APP_NAME", value = var.app_name },
        { name = "ENVIRONMENT", value = var.environment },
      ],
      var.enable_xray ? [{ name = "AWS_XRAY_DAEMON_ADDRESS", value = "xray-daemon:2000" }] : []
    )

    healthCheck = {
      command     = ["CMD-SHELL", "wget -q -O- http://localhost:${var.container_port}${var.health_check_path} || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }
  }

  xray_sidecar = var.enable_xray ? [{
    name      = "xray-daemon"
    image     = "public.ecr.aws/xray/aws-xray-daemon:latest"
    essential = false
    cpu       = 32
    memory    = 256
    portMappings = [{ containerPort = 2000, protocol = "udp" }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.app.name
        "awslogs-region"        = data.aws_region.current.name
        "awslogs-stream-prefix" = "xray"
      }
    }
  }] : []

  container_definitions = jsonencode(concat([local.app_container], local.xray_sidecar))
}

# ── Data sources ───────────────────────────────────────────────────────────────

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# Resolve KMS key from the shared services account via SSM
data "aws_ssm_parameter" "kms_arn" {
  name = "/mbank/shared/kms-arn/${var.data_classification}"
}

# Optional: resolve ACM cert for public-facing deployments
data "aws_acm_certificate" "wildcard" {
  count       = var.public_facing && var.certificate_arn == "" ? 1 : 0
  domain      = "*.mbank.com"
  statuses    = ["ISSUED"]
  most_recent = true
}

locals {
  cert_arn = var.public_facing ? (
    var.certificate_arn != "" ? var.certificate_arn : data.aws_acm_certificate.wildcard[0].arn
  ) : null

  alb_subnets = var.public_facing ? var.public_subnet_ids : var.private_subnet_ids
}

# Optional: fetch PagerDuty integration key from Secrets Manager
data "aws_secretsmanager_secret_version" "pagerduty" {
  count     = var.pagerduty_service_key_secret != "" ? 1 : 0
  secret_id = var.pagerduty_service_key_secret
}

# ── ECS Cluster ────────────────────────────────────────────────────────────────

resource "aws_ecs_cluster" "this" {
  name = local.prefix

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = local.tags
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }
}

# ── CloudWatch Log Group ───────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.app_name}"
  retention_in_days = 90
  kms_key_id        = data.aws_ssm_parameter.kms_arn.value
  tags              = local.tags
}

# ── ECR Repository ─────────────────────────────────────────────────────────────

resource "aws_ecr_repository" "this" {
  name                 = "${var.team}/${var.app_name}"
  image_tag_mutability = "IMMUTABLE"  # prevents tag overwrites; enforces immutable artefacts

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = data.aws_ssm_parameter.kms_arn.value
  }

  tags = local.tags
}

resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep last 10 tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "release-"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = { type = "expire" }
      },
    ]
  })
}

# ── IAM: Task Execution Role ───────────────────────────────────────────────────

data "aws_iam_policy_document" "ecs_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
    # Confused-deputy protection: only tasks from this account can assume
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "task_execution" {
  name               = "${local.prefix}-task-exec"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "task_execution_managed" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "task_exec_extras" {
  # ECR public registry pull (needed for X-Ray sidecar image)
  statement {
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  dynamic "statement" {
    for_each = length(var.secrets_arns) > 0 ? [1] : []
    content {
      effect    = "Allow"
      actions   = ["secretsmanager:GetSecretValue"]
      resources = var.secrets_arns
    }
  }

  # Allow decryption of secrets and log group using the classification KMS key
  statement {
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey*"]
    resources = [data.aws_ssm_parameter.kms_arn.value]
  }
}

resource "aws_iam_role_policy" "task_exec_extras" {
  name   = "ecr-logs-secrets"
  role   = aws_iam_role.task_execution.id
  policy = data.aws_iam_policy_document.task_exec_extras.json
}

# ── IAM: Task Role (application permissions) ──────────────────────────────────

resource "aws_iam_role" "task" {
  name               = "${local.prefix}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
  tags               = local.tags
}

data "aws_iam_policy_document" "task_xray" {
  count = var.enable_xray ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords",
      "xray:GetSamplingRules",
      "xray:GetSamplingTargets",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "task_xray" {
  count  = var.enable_xray ? 1 : 0
  name   = "xray-write"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task_xray[0].json
}

# ── ECS Task Definition ────────────────────────────────────────────────────────

resource "aws_ecs_task_definition" "this" {
  family                   = local.prefix
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn
  container_definitions    = local.container_definitions

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  tags = local.tags
}

# ── Security Groups ────────────────────────────────────────────────────────────

resource "aws_security_group" "alb" {
  name        = "${local.prefix}-alb"
  description = "ALB ingress for ${local.prefix}"
  vpc_id      = var.vpc_id

  ingress {
    description = var.public_facing ? "HTTPS from internet" : "HTTP from RFC1918"
    from_port   = var.public_facing ? 443 : 80
    to_port     = var.public_facing ? 443 : 80
    protocol    = "tcp"
    cidr_blocks = var.public_facing ? ["0.0.0.0/0"] : ["10.0.0.0/8"]
  }

  dynamic "ingress" {
    for_each = var.public_facing ? [1] : []
    content {
      description = "HTTP → HTTPS redirect"
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    from_port   = var.container_port
    to_port     = var.container_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.prefix}-alb" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "service" {
  name        = "${local.prefix}-service"
  description = "ECS task ingress — ALB only on container port"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Container port from ALB only"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "All outbound (VPC NAT routes to inspection firewall)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.prefix}-service" })

  lifecycle {
    create_before_destroy = true
  }
}

# ── Application Load Balancer ──────────────────────────────────────────────────

resource "aws_lb" "this" {
  # ALB name max 32 chars
  name               = substr(local.prefix, 0, 32)
  internal           = !var.public_facing
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = local.alb_subnets

  enable_deletion_protection = var.environment == "prod"
  drop_invalid_header_fields = true  # security: block requests with invalid HTTP headers

  tags = local.tags
}

resource "aws_lb_target_group" "this" {
  name        = substr(local.prefix, 0, 32)
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"  # required for Fargate awsvpc networking

  health_check {
    enabled             = true
    path                = var.health_check_path
    protocol            = "HTTP"
    matcher             = "200-299"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  deregistration_delay = 30  # short drain; Fargate tasks stop quickly

  tags = local.tags
}

resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.this.arn
  port              = var.public_facing ? 443 : 80
  protocol          = var.public_facing ? "HTTPS" : "HTTP"
  ssl_policy        = var.public_facing ? "ELBSecurityPolicy-TLS13-1-2-2021-06" : null
  certificate_arn   = local.cert_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  tags = local.tags
}

# HTTP → HTTPS redirect for public-facing load balancers
resource "aws_lb_listener" "http_redirect" {
  count             = var.public_facing ? 1 : 0
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = local.tags
}

# ── ECS Service ────────────────────────────────────────────────────────────────

resource "aws_ecs_service" "this" {
  name            = var.app_name
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.service.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = var.app_name
    container_port   = var.container_port
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_controller {
    type = "ECS"
  }

  health_check_grace_period_seconds = 120

  # CI/CD manages task_definition updates and desired_count scaling outside Terraform
  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }

  tags       = local.tags
  depends_on = [aws_lb_listener.main]
}

# ── Auto Scaling ───────────────────────────────────────────────────────────────

resource "aws_appautoscaling_target" "this" {
  max_capacity       = var.max_capacity
  min_capacity       = var.min_capacity
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.this.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "cpu" {
  name               = "${local.prefix}-cpu-target-tracking"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.this.resource_id
  scalable_dimension = aws_appautoscaling_target.this.scalable_dimension
  service_namespace  = aws_appautoscaling_target.this.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 70.0
    scale_in_cooldown  = 300  # conservative scale-in to avoid flapping
    scale_out_cooldown = 60
  }
}

# ── SNS for alarms ─────────────────────────────────────────────────────────────

resource "aws_sns_topic" "alarms" {
  name              = "${local.prefix}-alarms"
  kms_master_key_id = "alias/aws/sns"
  tags              = local.tags
}

resource "aws_sns_topic_subscription" "pagerduty" {
  count     = var.pagerduty_service_key_secret != "" ? 1 : 0
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "https"
  # Construct the PagerDuty Events v2 URL from the secret value
  endpoint = "https://events.pagerduty.com/integration/${data.aws_secretsmanager_secret_version.pagerduty[0].secret_string}/enqueue"
}

# ── CloudWatch Alarms ──────────────────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${local.prefix}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = var.alarm_cpu_threshold
  alarm_description   = "ECS CPU > ${var.alarm_cpu_threshold}% for 3 consecutive minutes"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = aws_ecs_cluster.this.name
    ServiceName = aws_ecs_service.this.name
  }

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "memory_high" {
  alarm_name          = "${local.prefix}-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "ECS memory > 80% for 3 consecutive minutes"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = aws_ecs_cluster.this.name
    ServiceName = aws_ecs_service.this.name
  }

  tags = local.tags
}

# 5xx error rate: metric math (errors / total requests × 100)
resource "aws_cloudwatch_metric_alarm" "alb_5xx_rate" {
  alarm_name          = "${local.prefix}-5xx-rate-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = var.alarm_5xx_threshold
  alarm_description   = "ALB 5xx error rate > ${var.alarm_5xx_threshold}% over 2 minutes"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "error_rate"
    expression  = "100 * m2 / m1"
    label       = "5xx Error Rate (%)"
    return_data = true
  }
  metric_query {
    id = "m1"
    metric {
      metric_name = "RequestCount"
      namespace   = "AWS/ApplicationELB"
      period      = 60
      stat        = "Sum"
      dimensions  = { LoadBalancer = aws_lb.this.arn_suffix }
    }
  }
  metric_query {
    id = "m2"
    metric {
      metric_name = "HTTPCode_Target_5XX_Count"
      namespace   = "AWS/ApplicationELB"
      period      = 60
      stat        = "Sum"
      dimensions  = { LoadBalancer = aws_lb.this.arn_suffix }
    }
  }

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "p99_latency" {
  alarm_name          = "${local.prefix}-p99-latency-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  extended_statistic  = "p99"
  threshold           = 2  # 2 seconds
  alarm_description   = "ALB P99 target response time > 2 s"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.this.arn_suffix
  }

  tags = local.tags
}

# Unhealthy hosts: immediate page — any value > 0 means service degradation
resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${local.prefix}-unhealthy-hosts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "At least one ECS task is failing health checks"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.this.arn_suffix
    TargetGroup  = aws_lb_target_group.this.arn_suffix
  }

  tags = local.tags
}

