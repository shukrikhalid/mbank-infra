variable "dx_connection_name" {
  description = "Name of the existing Direct Connect connection provisioned by the NOC team."
  type        = string
}

variable "dx_vlan_id" {
  description = "VLAN ID for the Direct Connect private virtual interface."
  type        = number
}

variable "dx_customer_address" {
  description = "Customer-side BGP peer IP in /30 CIDR notation (e.g. '169.254.0.2/30')."
  type        = string
}

variable "dx_amazon_address" {
  description = "AWS-side BGP peer IP in /30 CIDR notation (e.g. '169.254.0.1/30')."
  type        = string
}

variable "onprem_bgp_asn" {
  description = "BGP ASN of the on-premises edge router."
  type        = number
  default     = 65000
}

variable "onprem_bgp_auth_key" {
  description = "MD5 BGP authentication key for the DX virtual interface. Inject from Secrets Manager at plan time; never commit to source control."
  type        = string
  sensitive   = true
}

variable "onprem_cgw_public_ip" {
  description = "Public IP address of the on-premises VPN/customer gateway device."
  type        = string
}

variable "onprem_cidr" {
  description = "Aggregate CIDR block for all on-premises networks (used as TGW static route)."
  type        = string
  default     = "10.0.0.0/8"
}
