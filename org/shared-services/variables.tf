variable "onprem_dns_ip_primary" {
  description = "Primary on-premises DNS server IP address (10.0.0.53 by convention)."
  type        = string
  default     = "10.0.0.53"
}

variable "onprem_dns_ip_secondary" {
  description = "Optional secondary on-premises DNS server IP. Empty string disables the second target."
  type        = string
  default     = "10.0.1.53"
}
