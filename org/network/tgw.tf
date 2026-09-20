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
    Environment = "network"
    Team        = "platform"
    ManagedBy   = "terraform"
  }

  azs = ["ap-southeast-5a", "ap-southeast-5b", "ap-southeast-5c"]
}

data "aws_organizations_organization" "this" {}
data "aws_caller_identity" "current" {}

# ── Transit Gateway ────────────────────────────────────────────────────────────

resource "aws_ec2_transit_gateway" "hub" {
  description                     = "Mbank central Transit Gateway"
  amazon_side_asn                 = 64512
  auto_accept_shared_attachments  = "disable"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"  # active/active VPN with DX backup
  multicast_support               = "disable"

  tags = merge(local.common_tags, { Name = "mbank-tgw-hub" })
}

# ── TGW route tables ───────────────────────────────────────────────────────────

resource "aws_ec2_transit_gateway_route_table" "workloads" {
  transit_gateway_id = aws_ec2_transit_gateway.hub.id
  tags               = merge(local.common_tags, { Name = "mbank-tgw-workloads-rt" })
}

resource "aws_ec2_transit_gateway_route_table" "inspection" {
  transit_gateway_id = aws_ec2_transit_gateway.hub.id
  tags               = merge(local.common_tags, { Name = "mbank-tgw-inspection-rt" })
}

resource "aws_ec2_transit_gateway_route_table" "shared_services" {
  transit_gateway_id = aws_ec2_transit_gateway.hub.id
  tags               = merge(local.common_tags, { Name = "mbank-tgw-shared-services-rt" })
}

# ── RAM: share TGW with the entire AWS Organization ───────────────────────────

resource "aws_ram_resource_share" "tgw" {
  name                      = "mbank-tgw-org-share"
  allow_external_principals = false
  tags                      = local.common_tags
}

resource "aws_ram_resource_association" "tgw" {
  resource_share_arn = aws_ram_resource_share.tgw.arn
  resource_arn       = aws_ec2_transit_gateway.hub.arn
}

resource "aws_ram_principal_association" "org" {
  resource_share_arn = aws_ram_resource_share.tgw.arn
  # Share with the entire org so any vended account can attach a spoke VPC
  principal = data.aws_organizations_organization.this.arn
}

# ── TGW attachment for the inspection VPC ─────────────────────────────────────
# Subnet IDs come from inspection-vpc.tf (same Terraform root module).

resource "aws_ec2_transit_gateway_vpc_attachment" "inspection" {
  transit_gateway_id = aws_ec2_transit_gateway.hub.id
  vpc_id             = aws_vpc.inspection.id
  subnet_ids         = [for az in local.azs : aws_subnet.tgw_attachment[az].id]

  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false
  dns_support                                     = "enable"

  tags = merge(local.common_tags, { Name = "mbank-tgw-attach-inspection" })
}

# ── Route table associations ───────────────────────────────────────────────────
# Inspection VPC attachment → inspection-rt
# (Return path: after firewall inspects and allows, traffic goes back into TGW
#  and is delivered to the originating spoke via inspection-rt propagation.)

resource "aws_ec2_transit_gateway_route_table_association" "inspection" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.inspection.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.inspection.id
}

# ── Route table propagation ────────────────────────────────────────────────────
# Allow inspection VPC routes to appear in workloads-rt so spokes can return
# traffic after it has been NATed and inspected.

resource "aws_ec2_transit_gateway_route_table_propagation" "inspection_to_workloads" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.inspection.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.workloads.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "inspection_to_shared_services" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.inspection.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.shared_services.id
}

# ── Static default routes: force all spoke traffic through inspection ──────────

resource "aws_ec2_transit_gateway_route" "workloads_default" {
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.workloads.id
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.inspection.id
}

resource "aws_ec2_transit_gateway_route" "shared_services_default" {
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.shared_services.id
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.inspection.id
}

