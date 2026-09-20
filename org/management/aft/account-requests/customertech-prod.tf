# Account request for the CustomerTech (CRM) BU production account.
module "mbank_customertech_prod" {
  source = "./modules/aft-account-request"

  control_tower_parameters = {
    AccountEmail              = "aws-customertech-prod@mbank.com"
    AccountName               = "mbank-customertech-prod"
    ManagedOrganizationalUnit = "Workloads/CustomerTechBU"
    SSOUserEmail              = "platform-admin@mbank.com"
    SSOUserFirstName          = "Platform"
    SSOUserLastName           = "Admin"
  }

  account_tags = {
    Environment        = "prod"
    Team               = "customertech"
    CostCentre         = "CC-CRM-001"
    DataClassification = "internal"
    ManagedBy          = "aft"
  }

  change_management_parameters = {
    change_requested_by = "platform-team"
    change_reason       = "Initial provisioning of CustomerTech BU production account"
  }

  # PDPA scope — CRM holds customer PII.
  custom_fields = {
    data_classification = "internal"
    pdpa_scope          = "true"
    backup_vault        = "mbank-backup-internal"
  }

  account_customizations_name = "mbank-common"
}
