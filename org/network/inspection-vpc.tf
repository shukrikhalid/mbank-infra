# ── Inspection VPC ────────────────────────────────────────────────────────────

resource "aws_vpc" "inspection" {
  cidr_block           = "100.64.0.0/16"  # RFC 6598 carrier-grade NAT space
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = merge(local.common_tags, { Name = "mbank-inspection-vpc" })
}

resource "aws_internet_gateway" "inspection" {
  vpc_id = aws_vpc.inspection.id
  tags   = merge(local.common_tags, { Name = "mbank-inspection-igw" })
}

# ── Subnet CIDR allocation ─────────────────────────────────────────────────────

locals {
  fw_subnet_cidrs = {
    "ap-southeast-5a" = "100.64.0.0/24"
    "ap-southeast-5b" = "100.64.1.0/24"
    "ap-southeast-5c" = "100.64.2.0/24"
  }
  natgw_subnet_cidrs = {
    "ap-southeast-5a" = "100.64.10.0/24"
    "ap-southeast-5b" = "100.64.11.0/24"
    "ap-southeast-5c" = "100.64.12.0/24"
  }
  # /28 is sufficient for TGW attachment ENIs (requires only a handful of IPs)
  tgw_subnet_cidrs = {
    "ap-southeast-5a" = "100.64.20.0/28"
    "ap-southeast-5b" = "100.64.20.16/28"
    "ap-southeast-5c" = "100.64.20.32/28"
  }
}

resource "aws_subnet" "firewall" {
  for_each                = local.fw_subnet_cidrs
  vpc_id                  = aws_vpc.inspection.id
  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = false
  tags = merge(local.common_tags, {
    Name = "mbank-inspection-fw-${each.key}"
    Tier = "firewall"
  })
}

resource "aws_subnet" "natgw" {
  for_each                = local.natgw_subnet_cidrs
  vpc_id                  = aws_vpc.inspection.id
  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = false
  tags = merge(local.common_tags, {
    Name = "mbank-inspection-natgw-${each.key}"
    Tier = "nat-gateway"
  })
}

resource "aws_subnet" "tgw_attachment" {
  for_each                = local.tgw_subnet_cidrs
  vpc_id                  = aws_vpc.inspection.id
  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = false
  tags = merge(local.common_tags, {
    Name = "mbank-inspection-tgw-${each.key}"
    Tier = "tgw-attachment"
  })
}

# ── Network Firewall ──────────────────────────────────────────────────────────
# Firewall endpoints land in the firewall subnets (one endpoint per AZ).
# firewall_policy_arn references the policy in firewall-rules.tf (same root module).

resource "aws_networkfirewall_firewall" "inspection" {
  name                = "mbank-inspection-firewall"
  description         = "Centralised stateful inspection for all Mbank outbound workload traffic"
  vpc_id              = aws_vpc.inspection.id
  firewall_policy_arn = aws_networkfirewall_firewall_policy.inspection.arn

  # Protect against accidental policy/subnet/firewall changes
  delete_protection                 = true
  firewall_policy_change_protection = true
  subnet_change_protection          = true

  dynamic "subnet_mapping" {
    for_each = aws_subnet.firewall
    content {
      subnet_id = subnet_mapping.value.id
    }
  }

  tags = merge(local.common_tags, { Name = "mbank-inspection-firewall" })
}

# Build a map of AZ → firewall VPC endpoint ID for use in route tables below.
locals {
  fw_endpoints = {
    for ss in tolist(aws_networkfirewall_firewall.inspection.firewall_status[0].sync_states) :
    ss.availability_zone => ss.attachment[0].endpoint_id
  }
}

# ── Elastic IPs and NAT Gateways (one per AZ) ─────────────────────────────────

resource "aws_eip" "natgw" {
  for_each = toset(local.azs)
  domain   = "vpc"
  tags     = merge(local.common_tags, { Name = "mbank-inspection-natgw-eip-${each.key}" })
}

resource "aws_nat_gateway" "inspection" {
  for_each      = toset(local.azs)
  allocation_id = aws_eip.natgw[each.key].id
  subnet_id     = aws_subnet.natgw[each.key].id
  depends_on    = [aws_internet_gateway.inspection]
  tags          = merge(local.common_tags, { Name = "mbank-inspection-natgw-${each.key}" })
}

# ── Route tables ──────────────────────────────────────────────────────────────
#
# Traffic flow (outbound):
#   Spoke → TGW → tgw-attachment subnet
#     → (0.0.0.0/0 → fw endpoint) → Firewall subnet
#     → (0.0.0.0/0 → NAT GW)      → NAT GW subnet
#     → (0.0.0.0/0 → IGW)         → Internet
#
# Traffic flow (return):
#   Internet → NAT GW subnet
#     → (10.0.0.0/8 → fw endpoint) → Firewall subnet (stateful allows)
#     → (10.0.0.0/8 → TGW)         → TGW → Spoke

# TGW attachment subnet: all traffic → firewall endpoint (same AZ)
resource "aws_route_table" "tgw_attachment" {
  for_each = toset(local.azs)
  vpc_id   = aws_vpc.inspection.id
  tags     = merge(local.common_tags, { Name = "mbank-inspection-tgw-rt-${each.key}" })
}

resource "aws_route_table_association" "tgw_attachment" {
  for_each       = toset(local.azs)
  subnet_id      = aws_subnet.tgw_attachment[each.key].id
  route_table_id = aws_route_table.tgw_attachment[each.key].id
}

resource "aws_route" "tgw_to_fw" {
  for_each               = toset(local.azs)
  route_table_id         = aws_route_table.tgw_attachment[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = local.fw_endpoints[each.key]
}

# Firewall subnet: outbound → NAT GW; return to RFC1918 → TGW
resource "aws_route_table" "firewall" {
  for_each = toset(local.azs)
  vpc_id   = aws_vpc.inspection.id
  tags     = merge(local.common_tags, { Name = "mbank-inspection-fw-rt-${each.key}" })
}

resource "aws_route_table_association" "firewall" {
  for_each       = toset(local.azs)
  subnet_id      = aws_subnet.firewall[each.key].id
  route_table_id = aws_route_table.firewall[each.key].id
}

resource "aws_route" "fw_to_natgw" {
  for_each               = toset(local.azs)
  route_table_id         = aws_route_table.firewall[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.inspection[each.key].id
}

# RFC1918 return path: firewall → TGW (delivers inspected return traffic to spoke)
resource "aws_route" "fw_to_tgw_rfc1918" {
  for_each               = toset(local.azs)
  route_table_id         = aws_route_table.firewall[each.key].id
  destination_cidr_block = "10.0.0.0/8"
  transit_gateway_id     = aws_ec2_transit_gateway.hub.id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.inspection]
}

# NAT GW subnet: internet → IGW; return to RFC1918 → firewall endpoint for inspection
resource "aws_route_table" "natgw" {
  for_each = toset(local.azs)
  vpc_id   = aws_vpc.inspection.id
  tags     = merge(local.common_tags, { Name = "mbank-inspection-natgw-rt-${each.key}" })
}

resource "aws_route_table_association" "natgw" {
  for_each       = toset(local.azs)
  subnet_id      = aws_subnet.natgw[each.key].id
  route_table_id = aws_route_table.natgw[each.key].id
}

resource "aws_route" "natgw_to_igw" {
  for_each               = toset(local.azs)
  route_table_id         = aws_route_table.natgw[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.inspection.id
}

# Return path: post-NAT un-translation, send RFC1918-destined traffic through firewall
resource "aws_route" "natgw_to_fw_rfc1918" {
  for_each               = toset(local.azs)
  route_table_id         = aws_route_table.natgw[each.key].id
  destination_cidr_block = "10.0.0.0/8"
  vpc_endpoint_id        = local.fw_endpoints[each.key]
}

