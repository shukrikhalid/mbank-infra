# Account request for the Public/CMS BU production account.
module "mbank_public_prod" {
  source = "./modules/aft-account-request"

  control_tower_parameters = {
    AccountEmail              = "aws-public-prod@mbank.com"
    AccountName               = "mbank-public-prod"
    ManagedOrganizationalUnit = "Workloads/PublicBU"
    SSOUserEmail              = "platform-admin@mbank.com"
    SSOUserFirstName          = "Platform"
    SSOUserLastName           = "Admin"
  }

  account_tags = {
    Environment        = "prod"
    Team               = "public"
    CostCentre         = "CC-PUB-001"
    DataClassification = "public"
    ManagedBy          = "aft"
  }

  change_management_parameters = {
    change_requested_by = "platform-team"
    change_reason       = "Initial provisioning of Public/CMS BU production account"
  }

  custom_fields = {
    data_classification = "public"
    internet_facing     = "true"
    backup_vault        = "mbank-backup-public"
  }

  account_customizations_name = "mbank-public"
}
