terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

# Must run in the management account; assume OrganizationManagementRole via caller config.
provider "aws" {
  region = "ap-southeast-5"
}

# ── Locals ─────────────────────────────────────────────────────────────────────

locals {
  common_tags = {
    Environment = "management"
    Team        = "platform"
    ManagedBy   = "terraform"
  }

  # Convenience map consumed by AFT customizations and spoke-account modules.
  account_ou_map = {
    "payments-prod"     = aws_organizations_organizational_unit.payments_bu.id
    "customertech-prod" = aws_organizations_organizational_unit.customertech_bu.id
    "finance-prod"      = aws_organizations_organizational_unit.finance_bu.id
    "public-prod"       = aws_organizations_organizational_unit.public_bu.id
  }

  root_id = data.aws_organizations_organization.this.roots[0].id
}

# ── Existing organisation (do not create) ──────────────────────────────────────

data "aws_organizations_organization" "this" {}

# ── Enable SCP policy type on the root ─────────────────────────────────────────
# Idempotent: no-op if already enabled by Control Tower.

resource "aws_organizations_policy_type" "scp" {
  root_id     = local.root_id
  policy_type = "SERVICE_CONTROL_POLICY"
}

# ── OU hierarchy ───────────────────────────────────────────────────────────────

resource "aws_organizations_organizational_unit" "workloads" {
  name      = "Workloads"
  parent_id = local.root_id
  tags      = local.common_tags
}

resource "aws_organizations_organizational_unit" "payments_bu" {
  name      = "PaymentsBU"
  parent_id = aws_organizations_organizational_unit.workloads.id
  tags      = local.common_tags
}

resource "aws_organizations_organizational_unit" "customertech_bu" {
  name      = "CustomerTechBU"
  parent_id = aws_organizations_organizational_unit.workloads.id
  tags      = local.common_tags
}

resource "aws_organizations_organizational_unit" "finance_bu" {
  name      = "FinanceBU"
  parent_id = aws_organizations_organizational_unit.workloads.id
  tags      = local.common_tags
}

resource "aws_organizations_organizational_unit" "public_bu" {
  name      = "PublicBU"
  parent_id = aws_organizations_organizational_unit.workloads.id
  tags      = local.common_tags
}

# ── SCP definitions ────────────────────────────────────────────────────────────

resource "aws_organizations_policy" "deny_root_access" {
  name        = "mbank-deny-root-access"
  description = "Deny all actions by the root user in any member account."
  type        = "SERVICE_CONTROL_POLICY"
  content     = file("${path.module}/scps/deny-root-access.json")
  tags        = local.common_tags

  depends_on = [aws_organizations_policy_type.scp]
}

resource "aws_organizations_policy" "require_mfa_iam" {
  name        = "mbank-require-mfa-iam"
  description = "Deny IAM write actions unless MFA is present in the session."
  type        = "SERVICE_CONTROL_POLICY"
  content     = file("${path.module}/scps/require-mfa-iam.json")
  tags        = local.common_tags

  depends_on = [aws_organizations_policy_type.scp]
}

resource "aws_organizations_policy" "deny_public_s3" {
  name        = "mbank-deny-public-s3"
  description = "Deny public S3 ACLs and disabling of S3 Block Public Access settings."
  type        = "SERVICE_CONTROL_POLICY"
  content     = file("${path.module}/scps/deny-public-s3.json")
  tags        = local.common_tags

  depends_on = [aws_organizations_policy_type.scp]
}

resource "aws_organizations_policy" "require_region" {
  name        = "mbank-require-region-ap-southeast"
  description = "Restrict all non-global actions to ap-southeast-5 (Malaysia) and ap-southeast-2 (Sydney DR)."
  type        = "SERVICE_CONTROL_POLICY"
  content     = file("${path.module}/scps/require-region-ap-southeast.json")
  tags        = local.common_tags

  depends_on = [aws_organizations_policy_type.scp]
}

# ── SCP attachments ────────────────────────────────────────────────────────────
# Root: deny-root-access + require-mfa-iam apply to every account in the org.
# Workloads OU: deny-public-s3 + require-region apply to all workload accounts
# and are inherited by all BU child OUs.

resource "aws_organizations_policy_attachment" "deny_root_access_root" {
  policy_id = aws_organizations_policy.deny_root_access.id
  target_id = local.root_id
}

resource "aws_organizations_policy_attachment" "require_mfa_iam_root" {
  policy_id = aws_organizations_policy.require_mfa_iam.id
  target_id = local.root_id
}

resource "aws_organizations_policy_attachment" "deny_public_s3_workloads" {
  policy_id = aws_organizations_policy.deny_public_s3.id
  target_id = aws_organizations_organizational_unit.workloads.id
}

resource "aws_organizations_policy_attachment" "require_region_workloads" {
  policy_id = aws_organizations_policy.require_region.id
  target_id = aws_organizations_organizational_unit.workloads.id
}

# ── Delegated administrators ───────────────────────────────────────────────────
# All security services delegate to the dedicated Security/Audit account so that
# the management account is used only for org-level orchestration.

resource "aws_organizations_delegated_administrator" "config" {
  account_id        = var.security_account_id
  service_principal = "config.amazonaws.com"
}

resource "aws_organizations_delegated_administrator" "config_multiregion" {
  account_id        = var.security_account_id
  service_principal = "config-multiaccountsetup.amazonaws.com"
}

resource "aws_organizations_delegated_administrator" "guardduty" {
  account_id        = var.security_account_id
  service_principal = "guardduty.amazonaws.com"
}

resource "aws_organizations_delegated_administrator" "securityhub" {
  account_id        = var.security_account_id
  service_principal = "securityhub.amazonaws.com"
}

resource "aws_organizations_delegated_administrator" "cloudtrail" {
  account_id        = var.security_account_id
  service_principal = "cloudtrail.amazonaws.com"
}

resource "aws_organizations_delegated_administrator" "access_analyzer" {
  account_id        = var.security_account_id
  service_principal = "access-analyzer.amazonaws.com"
}

# ── SSM exports ────────────────────────────────────────────────────────────────
# Spoke-account modules resolve OU IDs at runtime via SSM rather than hard-coding.

resource "aws_ssm_parameter" "ou_id" {
  for_each = {
    workloads       = aws_organizations_organizational_unit.workloads.id
    payments_bu     = aws_organizations_organizational_unit.payments_bu.id
    customertech_bu = aws_organizations_organizational_unit.customertech_bu.id
    finance_bu      = aws_organizations_organizational_unit.finance_bu.id
    public_bu       = aws_organizations_organizational_unit.public_bu.id
  }

  name  = "/mbank/org/ou-id/${each.key}"
  type  = "String"
  value = each.value
  tags  = local.common_tags
}

resource "aws_ssm_parameter" "org_id" {
  name  = "/mbank/org/organization-id"
  type  = "String"
  value = data.aws_organizations_organization.this.id
  tags  = local.common_tags
}

resource "aws_ssm_parameter" "root_id" {
  name  = "/mbank/org/root-id"
  type  = "String"
  value = local.root_id
  tags  = local.common_tags
}

