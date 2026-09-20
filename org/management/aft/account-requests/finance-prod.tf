# Account request for the Finance BU production account.
module "mbank_finance_prod" {
  source = "./modules/aft-account-request"

  control_tower_parameters = {
    AccountEmail              = "aws-finance-prod@mbank.com"
    AccountName               = "mbank-finance-prod"
    ManagedOrganizationalUnit = "Workloads/FinanceBU"
    SSOUserEmail              = "platform-admin@mbank.com"
    SSOUserFirstName          = "Platform"
    SSOUserLastName           = "Admin"
  }

  account_tags = {
    Environment        = "prod"
    Team               = "finance"
    CostCentre         = "CC-FIN-001"
    DataClassification = "restricted"
    ManagedBy          = "aft"
  }

  change_management_parameters = {
    change_requested_by = "platform-team"
    change_reason       = "Initial provisioning of Finance BU production account"
  }

  # Restricted classification — financial reporting data under BNM / securities regulations.
  custom_fields = {
    data_classification = "restricted"
    securities_scope    = "true"
    backup_vault        = "mbank-backup-restricted"
  }

  account_customizations_name = "mbank-common"
}
