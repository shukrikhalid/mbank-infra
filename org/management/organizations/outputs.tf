output "organization_id" {
  description = "AWS Organizations ID."
  value       = data.aws_organizations_organization.this.id
}

output "root_id" {
  description = "Organizations root ID."
  value       = local.root_id
}

output "ou_ids" {
  description = "Map of OU name to OU ID for the full hierarchy."
  value = {
    workloads       = aws_organizations_organizational_unit.workloads.id
    payments_bu     = aws_organizations_organizational_unit.payments_bu.id
    customertech_bu = aws_organizations_organizational_unit.customertech_bu.id
    finance_bu      = aws_organizations_organizational_unit.finance_bu.id
    public_bu       = aws_organizations_organizational_unit.public_bu.id
  }
}

output "scp_ids" {
  description = "Map of SCP name to policy ID."
  value = {
    deny_root_access = aws_organizations_policy.deny_root_access.id
    require_mfa_iam  = aws_organizations_policy.require_mfa_iam.id
    deny_public_s3   = aws_organizations_policy.deny_public_s3.id
    require_region   = aws_organizations_policy.require_region.id
  }
}

output "account_ou_map" {
  description = "Map of account name to the OU ID it belongs to."
  value       = local.account_ou_map
}
