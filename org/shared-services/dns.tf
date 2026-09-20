terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = "ap-southeast-5"
}

locals {
  common_tags = {
    Environment = "shared"
    Team        = "platform"
    ManagedBy   = "terraform"
  }

  resolver_subnet_cidrs = {
    "ap-southeast-5a" = "10.0.32.0/24"
    "ap-southeast-5b" = "10.0.33.0/24"
    "ap-southeast-5c" = "10.0.34.0/24"
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}
data "aws_organizations_organization" "this" {}

# ── Shared Services VPC (hosts resolver endpoints) ────────────────────────────

resource "aws_vpc" "shared_services" {
  cidr_block           = "10.0.32.0/20"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = merge(local.common_tags, { Name = "mbank-shared-services-vpc" })
}

resource "aws_subnet" "resolver" {
  for_each                = local.resolver_subnet_cidrs
  vpc_id                  = aws_vpc.shared_services.id
  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = false
  tags = merge(local.common_tags, {
    Name = "mbank-ss-resolver-${each.key}"
    Tier = "resolver"
  })
}

# ── Security groups for resolver endpoints ─────────────────────────────────────

resource "aws_security_group" "resolver_inbound" {
  name        = "mbank-resolver-inbound"
  description = "DNS ingress from on-prem to Route53 inbound resolver endpoint"
  vpc_id      = aws_vpc.shared_services.id

  ingress {
    description = "DNS UDP from RFC1918"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["10.0.0.0/8"]
  }
  ingress {
    description = "DNS TCP from RFC1918"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(local.common_tags, { Name = "mbank-resolver-inbound-sg" })
}

resource "aws_security_group" "resolver_outbound" {
  name        = "mbank-resolver-outbound"
  description = "DNS egress from Route53 outbound endpoint to on-prem resolvers"
  vpc_id      = aws_vpc.shared_services.id

  egress {
    description = "DNS UDP to on-prem"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["10.0.0.0/8"]
  }
  egress {
    description = "DNS TCP to on-prem"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }
  tags = merge(local.common_tags, { Name = "mbank-resolver-outbound-sg" })
}

# ── Route53 Resolver: inbound (on-prem queries AWS-hosted DNS) ────────────────

resource "aws_route53_resolver_endpoint" "inbound" {
  name               = "mbank-resolver-inbound"
  direction          = "INBOUND"
  security_group_ids = [aws_security_group.resolver_inbound.id]

  dynamic "ip_address" {
    for_each = aws_subnet.resolver
    content {
      subnet_id = ip_address.value.id
      # IP auto-assigned; on-prem DNS servers forward to these IPs
    }
  }

  tags = merge(local.common_tags, { Name = "mbank-resolver-inbound" })
}

# ── Route53 Resolver: outbound (AWS resolves on-prem internal names) ──────────

resource "aws_route53_resolver_endpoint" "outbound" {
  name               = "mbank-resolver-outbound"
  direction          = "OUTBOUND"
  security_group_ids = [aws_security_group.resolver_outbound.id]

  dynamic "ip_address" {
    for_each = aws_subnet.resolver
    content {
      subnet_id = ip_address.value.id
    }
  }

  tags = merge(local.common_tags, { Name = "mbank-resolver-outbound" })
}

# ── Forwarding rule: *.mbank.com → on-prem DNS ──────────────────────────────

resource "aws_route53_resolver_rule" "mbank_forward" {
  domain_name          = "mbank.com"
  name                 = "mbank-forward-mbank-com"
  rule_type            = "FORWARD"
  resolver_endpoint_id = aws_route53_resolver_endpoint.outbound.id

  target_ip {
    ip   = var.onprem_dns_ip_primary
    port = 53
  }

  dynamic "target_ip" {
    for_each = var.onprem_dns_ip_secondary != "" ? [var.onprem_dns_ip_secondary] : []
    content {
      ip   = target_ip.value
      port = 53
    }
  }

  tags = merge(local.common_tags, { Name = "mbank-forward-mbank-com" })
}

# ── Share resolver rules org-wide via RAM ─────────────────────────────────────
# Spoke accounts accept the RAM share then create aws_route53_resolver_rule_association
# in their own account for their VPCs.

resource "aws_ram_resource_share" "resolver_rules" {
  name                      = "mbank-resolver-rules-share"
  allow_external_principals = false
  tags                      = local.common_tags
}

resource "aws_ram_resource_association" "mbank_forward" {
  resource_share_arn = aws_ram_resource_share.resolver_rules.arn
  resource_arn       = aws_route53_resolver_rule.mbank_forward.arn
}

resource "aws_ram_principal_association" "resolver_rules_org" {
  resource_share_arn = aws_ram_resource_share.resolver_rules.arn
  principal          = data.aws_organizations_organization.this.arn
}

# ── Private Hosted Zones ───────────────────────────────────────────────────────
# lifecycle.ignore_changes on vpc: additional spoke associations are managed via
# aws_route53_vpc_association_authorization + aws_route53_zone_association in spoke accts.

resource "aws_route53_zone" "internal" {
  name    = "internal.mbank.com"
  comment = "Internal service discovery — managed by platform team"

  vpc {
    vpc_id = aws_vpc.shared_services.id
  }

  tags      = merge(local.common_tags, { Name = "internal.mbank.com" })
  lifecycle { ignore_changes = [vpc] }
}

resource "aws_route53_zone" "aws_internal" {
  name    = "aws.mbank.com"
  comment = "AWS infrastructure DNS — managed by platform team"

  vpc {
    vpc_id = aws_vpc.shared_services.id
  }

  tags      = merge(local.common_tags, { Name = "aws.mbank.com" })
  lifecycle { ignore_changes = [vpc] }
}

# ── Spoke VPC IDs from SSM (written by AFT customizations per vended account) ─

data "aws_ssm_parameters_by_path" "spoke_vpc_ids" {
  path      = "/mbank/spoke/vpc-id"
  recursive = false
}

locals {
  spoke_vpc_id_map = {
    for idx, name in data.aws_ssm_parameters_by_path.spoke_vpc_ids.names :
    trimprefix(name, "/mbank/spoke/vpc-id/") => data.aws_ssm_parameters_by_path.spoke_vpc_ids.values[idx]
  }
}

# ── PHZ association authorization for each spoke VPC ──────────────────────────
# This grants permission for the spoke account to associate its VPC with our PHZs.
# Spoke accounts complete the association via aws_route53_zone_association.

resource "aws_route53_vpc_association_authorization" "internal" {
  for_each = local.spoke_vpc_id_map
  zone_id  = aws_route53_zone.internal.id
  vpc_id   = each.value
}

resource "aws_route53_vpc_association_authorization" "aws_internal" {
  for_each = local.spoke_vpc_id_map
  zone_id  = aws_route53_zone.aws_internal.id
  vpc_id   = each.value
}

# ── SSM exports for downstream modules ────────────────────────────────────────

resource "aws_ssm_parameter" "resolver_inbound_endpoint_id" {
  name  = "/mbank/shared/resolver/inbound-endpoint-id"
  type  = "String"
  value = aws_route53_resolver_endpoint.inbound.id
  tags  = local.common_tags
}

resource "aws_ssm_parameter" "resolver_rule_mbank_id" {
  name  = "/mbank/shared/resolver/rule-id/mbank-forward"
  type  = "String"
  value = aws_route53_resolver_rule.mbank_forward.id
  tags  = local.common_tags
}

resource "aws_ssm_parameter" "phz_internal_zone_id" {
  name  = "/mbank/shared/dns/zone-id/internal-mbank-com"
  type  = "String"
  value = aws_route53_zone.internal.zone_id
  tags  = local.common_tags
}

resource "aws_ssm_parameter" "phz_aws_internal_zone_id" {
  name  = "/mbank/shared/dns/zone-id/aws-mbank-com"
  type  = "String"
  value = aws_route53_zone.aws_internal.zone_id
  tags  = local.common_tags
}

