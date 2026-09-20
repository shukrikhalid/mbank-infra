# ── Security Hub: management account ──────────────────────────────────────────

resource "aws_securityhub_account" "management" {
  enable_default_standards = false
  auto_enable_controls     = false
}

resource "aws_securityhub_organization_admin_account" "security" {
  admin_account_id = var.security_account_id
  depends_on       = [aws_securityhub_account.management]
}

# ── Security Hub: security account (delegated admin) ──────────────────────────

resource "aws_securityhub_account" "security" {
  provider                 = aws.security
  enable_default_standards = false  # we subscribe explicitly below
  auto_enable_controls     = true
  depends_on               = [aws_securityhub_organization_admin_account.security]
}

resource "aws_securityhub_organization_configuration" "this" {
  provider = aws.security
  # All new member accounts automatically get Security Hub enabled
  auto_enable           = true
  auto_enable_standards = "NONE"  # explicit subscriptions below prevent drift
  depends_on            = [aws_securityhub_account.security]
}

# ── Standards subscriptions ────────────────────────────────────────────────────
# PCI DSS v3.2.1: Mbank's payment processing is in PCI scope.
# CIS v1.4: BNM TRM baseline aligns closely with CIS L1.

resource "aws_securityhub_standards_subscription" "fsbp" {
  provider      = aws.security
  standards_arn = "arn:${data.aws_partition.current.partition}:securityhub:${data.aws_region.current.name}::standards/aws-foundational-security-best-practices/v/1.0.0"
  depends_on    = [aws_securityhub_account.security]
}

resource "aws_securityhub_standards_subscription" "cis_v14" {
  provider      = aws.security
  standards_arn = "arn:${data.aws_partition.current.partition}:securityhub:${data.aws_region.current.name}::standards/cis-aws-foundations-benchmark/v/1.4.0"
  depends_on    = [aws_securityhub_account.security]
}

resource "aws_securityhub_standards_subscription" "pci_dss" {
  provider      = aws.security
  standards_arn = "arn:${data.aws_partition.current.partition}:securityhub:${data.aws_region.current.name}::standards/pci-dss/v/3.2.1"
  depends_on    = [aws_securityhub_account.security]
}

# ── Insight: active CRITICAL findings not yet resolved ────────────────────────

resource "aws_securityhub_insight" "critical_unresolved" {
  provider = aws.security
  name     = "Mbank Critical Unresolved Findings"

  filters {
    severity_label {
      comparison = "EQUALS"
      value      = "CRITICAL"
    }
    record_state {
      comparison = "EQUALS"
      value      = "ACTIVE"
    }
    workflow_status {
      comparison = "NOT_EQUALS"
      value      = "RESOLVED"
    }
  }

  group_by_attribute = "ProductName"
  depends_on         = [aws_securityhub_account.security]
}
