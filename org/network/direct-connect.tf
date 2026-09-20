# ── Direct Connect: existing connection (provisioned by NOC, do not create) ───
# The physical cross-connect is managed by the NOC team. We reference it by ID.

data "aws_dx_connection" "onprem" {
  name = var.dx_connection_name
}

# ── Virtual Private Gateway for Direct Connect private VIF ────────────────────
# A VGW is required as the termination point for a private VIF. The VGW is
# attached to the inspection VPC; its routes propagate to the firewall route
# tables so on-prem traffic traverses the firewall like workload traffic.

resource "aws_vpn_gateway" "dx" {
  amazon_side_asn = 64512
  tags            = merge(local.common_tags, { Name = "mbank-dx-vgw" })
}

resource "aws_vpn_gateway_attachment" "dx_inspection" {
  vpc_id         = aws_vpc.inspection.id
  vpn_gateway_id = aws_vpn_gateway.dx.id
}

# Propagate on-prem BGP routes into the firewall subnet route tables
resource "aws_vpn_gateway_route_propagation" "firewall" {
  for_each       = toset(local.azs)
  route_table_id = aws_route_table.firewall[each.key].id
  vpn_gateway_id = aws_vpn_gateway.dx.id
  depends_on     = [aws_vpn_gateway_attachment.dx_inspection]
}

# ── Direct Connect private virtual interface ──────────────────────────────────

resource "aws_dx_private_virtual_interface" "onprem" {
  connection_id    = data.aws_dx_connection.onprem.id
  name             = "mbank-dx-private-vif-onprem"
  vlan             = var.dx_vlan_id
  address_family   = "ipv4"
  bgp_asn          = var.onprem_bgp_asn
  bgp_auth_key     = var.onprem_bgp_auth_key  # stored in Secrets Manager, injected at plan time
  customer_address = var.dx_customer_address   # on-prem router BGP peer IP (/30)
  amazon_address   = var.dx_amazon_address     # AWS BGP peer IP (/30)
  vpn_gateway_id   = aws_vpn_gateway.dx.id
  mtu              = 9001  # jumbo frames for maximum throughput

  tags = merge(local.common_tags, { Name = "mbank-dx-private-vif" })
}

# ── Customer gateway for IPsec VPN backup ─────────────────────────────────────

resource "aws_customer_gateway" "onprem" {
  bgp_asn    = var.onprem_bgp_asn
  ip_address = var.onprem_cgw_public_ip
  type       = "ipsec.1"
  tags       = merge(local.common_tags, { Name = "mbank-onprem-cgw" })
}

# ── Site-to-site VPN backup (attached directly to TGW, BGP dynamic routing) ──
# Connects to TGW so that if DX fails, BGP reconverges and VPN takes over.
# vpn_ecmp_support on the TGW allows active/active if two tunnels are healthy.

resource "aws_vpn_connection" "backup" {
  transit_gateway_id  = aws_ec2_transit_gateway.hub.id
  customer_gateway_id = aws_customer_gateway.onprem.id
  type                = "ipsec.1"
  static_routes_only  = false  # BGP dynamic routing; on-prem ASN = var.onprem_bgp_asn

  tags = merge(local.common_tags, {
    Name = "mbank-vpn-dx-backup"
    Role = "dx-failover"
  })
}

# ── TGW route table wiring for VPN attachment ─────────────────────────────────
# The VPN creates a TGW attachment automatically; expose its ID via the resource attribute.

resource "aws_ec2_transit_gateway_route_table_association" "vpn" {
  transit_gateway_attachment_id  = aws_vpn_connection.backup.transit_gateway_attachment_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.inspection.id
}

# On-prem routes from VPN BGP propagate into workloads-rt and shared-services-rt
# so spoke VPCs can reach on-prem networks without explicitly adding static routes.
resource "aws_ec2_transit_gateway_route_table_propagation" "vpn_to_workloads" {
  transit_gateway_attachment_id  = aws_vpn_connection.backup.transit_gateway_attachment_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.workloads.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "vpn_to_shared_services" {
  transit_gateway_attachment_id  = aws_vpn_connection.backup.transit_gateway_attachment_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.shared_services.id
}

# Static on-prem aggregate in inspection-rt (return path: inspection VPC → on-prem)
resource "aws_ec2_transit_gateway_route" "inspection_to_onprem" {
  destination_cidr_block         = var.onprem_cidr
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.inspection.id
  transit_gateway_attachment_id  = aws_vpn_connection.backup.transit_gateway_attachment_id
}

