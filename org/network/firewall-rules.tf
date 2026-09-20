# ── Stateless rule group: allow TCP/UDP/ICMP to SFE, drop everything else ─────
# Stateless engine runs first at line-rate. Only well-known transport protocols
# are forwarded to the stateful engine; all others are silently dropped here.

resource "aws_networkfirewall_rule_group" "stateless_protocols" {
  name        = "mbank-stateless-protocol-filter"
  description = "Forward TCP/UDP/ICMP to stateful engine; drop all other protocols"
  type        = "STATELESS"
  capacity    = 100

  rule_group {
    rules_source {
      stateless_rules_and_custom_actions {
        stateless_rule {
          priority = 10
          rule_definition {
            actions = ["aws:forward_to_sfe"]
            match_attributes {
              protocols = [6]  # TCP
              source      { address_definition = "0.0.0.0/0" }
              destination { address_definition = "0.0.0.0/0" }
            }
          }
        }
        stateless_rule {
          priority = 20
          rule_definition {
            actions = ["aws:forward_to_sfe"]
            match_attributes {
              protocols = [17]  # UDP
              source      { address_definition = "0.0.0.0/0" }
              destination { address_definition = "0.0.0.0/0" }
            }
          }
        }
        stateless_rule {
          priority = 30
          rule_definition {
            actions = ["aws:forward_to_sfe"]
            match_attributes {
              protocols = [1]  # ICMP
              source      { address_definition = "0.0.0.0/0" }
              destination { address_definition = "0.0.0.0/0" }
            }
          }
        }
      }
    }
  }

  tags = local.common_tags
}

# ── Stateful rule group 1: block known malicious IPs ─────────────────────────
# STRICT_ORDER: rules are evaluated lowest priority-number first; first match wins.
# In production feed this rule group from a threat-intel automation pipeline that
# updates the Suricata rule string via Terraform or AWS Network Firewall API.

resource "aws_networkfirewall_rule_group" "stateful_threat_intel" {
  name        = "mbank-stateful-threat-intel-blocklist"
  description = "Drop traffic to/from known malicious IPs (threat-intel feed)"
  type        = "STATEFUL"
  capacity    = 5000

  rule_group {
    stateful_rule_options {
      rule_order = "STRICT_ORDER"
    }

    rules_source {
      # RFC 5737 test ranges used as placeholder — replace with live threat-intel CIDRs
      rules_string = <<-SURICATA
        drop ip [192.0.2.0/24,198.51.100.0/24,203.0.113.0/24] any -> any any (msg:"[ThreatIntel] Block inbound from malicious IP"; flow:established; sid:2000001; rev:1;)
        drop ip any any -> [192.0.2.0/24,198.51.100.0/24,203.0.113.0/24] any (msg:"[ThreatIntel] Block outbound to malicious IP"; flow:to_server,established; sid:2000002; rev:1;)
      SURICATA
    }
  }

  tags = local.common_tags
}

# ── Stateful rule group 2: domain allowlist + default deny ────────────────────
# Allow TLS/443 only to *.amazonaws.com and *.mbank.com (SNI inspection).
# Pass established/return traffic so stateful sessions are not broken.
# Default-deny rule drops all other outbound (explicit block at end of STRICT_ORDER).

resource "aws_networkfirewall_rule_group" "stateful_outbound_policy" {
  name        = "mbank-stateful-outbound-policy"
  description = "Allow HTTPS to AWS/Mbank; block all other outbound"
  type        = "STATEFUL"
  capacity    = 1000

  rule_group {
    stateful_rule_options {
      rule_order = "STRICT_ORDER"
    }

    rules_source {
      rules_string = <<-SURICATA
        # Allow established return traffic first (stateful: matches existing sessions)
        pass ip any any -> any any (msg:"Allow established/related"; flow:established,to_client; sid:3000001; rev:1;)

        # Allow HTTPS to AWS service endpoints (SNI suffix match)
        pass tls any any -> any 443 (tls.sni; pcre:"/\.amazonaws\.com$/i"; msg:"Allow TLS to amazonaws.com"; flow:to_server,established; sid:3000010; rev:1;)
        pass tls any any -> any 443 (tls.sni; pcre:"/\.aws\.amazon\.com$/i"; msg:"Allow TLS to aws.amazon.com"; flow:to_server,established; sid:3000011; rev:1;)

        # Allow HTTPS to all Mbank domains
        pass tls any any -> any 443 (tls.sni; pcre:"/\.mbank\.com$/i"; msg:"Allow TLS to mbank.com"; flow:to_server,established; sid:3000020; rev:1;)

        # Default deny — drop everything not explicitly allowed above
        drop ip any any -> any any (msg:"[DefaultDeny] Block all other outbound"; sid:3000099; rev:1;)
      SURICATA
    }
  }

  tags = local.common_tags
}

# ── Firewall policy ───────────────────────────────────────────────────────────
# Stateless default: drop (any protocol not matched above is dropped immediately).
# Stateful STRICT_ORDER: threat-intel blocklist evaluated before domain policy.

resource "aws_networkfirewall_firewall_policy" "inspection" {
  name = "mbank-inspection-policy"

  firewall_policy {
    # Non-matching stateless traffic is dropped at line-rate (no SFE overhead)
    stateless_default_actions          = ["aws:drop"]
    stateless_fragment_default_actions = ["aws:drop"]  # never allow IP fragments

    stateless_rule_group_reference {
      priority     = 10
      resource_arn = aws_networkfirewall_rule_group.stateless_protocols.arn
    }

    stateful_engine_options {
      rule_order = "STRICT_ORDER"
    }

    # Threat intel runs first (priority 10) — malicious IPs blocked before domain check
    stateful_rule_group_reference {
      priority     = 10
      resource_arn = aws_networkfirewall_rule_group.stateful_threat_intel.arn
    }

    # Domain policy runs second (priority 20) — allow/deny by SNI + default deny
    stateful_rule_group_reference {
      priority     = 20
      resource_arn = aws_networkfirewall_rule_group.stateful_outbound_policy.arn
    }
  }

  tags = local.common_tags
}

