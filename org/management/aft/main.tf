terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

# Must run in the AFT management account.
provider "aws" {
  region = "ap-southeast-5"
}

# ── AFT bootstrap ──────────────────────────────────────────────────────────────

module "aft" {
  source  = "aws-ia/control_tower_account_factory/aws"
  version = "~> 1.0"

  # ── Account IDs ─────────────────────────────────────────────
  ct_management_account_id  = var.ct_management_account_id
  log_archive_account_id    = var.log_archive_account_id
  audit_account_id          = var.audit_account_id
  aft_management_account_id = var.aft_management_account_id

  # ── Regions ──────────────────────────────────────────────────
  ct_home_region              = "ap-southeast-5"
  tf_backend_secondary_region = "ap-southeast-2"

  # ── Terraform runtime ────────────────────────────────────────
  terraform_version      = "1.7.5"
  terraform_distribution = "oss"

  # ── VCS ──────────────────────────────────────────────────────
  # These repos are managed by the platform team; app teams never push here directly.
  vcs_provider                                          = "github"
  account_request_repo_name                             = "mbank/aft-account-request"
  account_request_repo_branch                           = "main"
  account_customizations_repo_name                      = "mbank/aft-account-customizations"
  account_customizations_repo_branch                    = "main"
  global_customizations_repo_name                       = "mbank/aft-global-customizations"
  global_customizations_repo_branch                     = "main"
  account_provisioning_customizations_repo_name         = "mbank/aft-account-provisioning-customizations"
  account_provisioning_customizations_repo_branch       = "main"

  # ── Features ─────────────────────────────────────────────────
  aft_feature_cloudtrail_data_events      = true   # S3 + Lambda data events on every vended account
  aft_feature_enterprise_support          = false  # Enable if Mbank upgrades to Enterprise Support
  aft_feature_delete_default_vpcs_enabled = true   # AFT deletes default VPCs in all regions post-vend

  # ── Metrics ──────────────────────────────────────────────────
  aft_metrics_reporting = true
}

