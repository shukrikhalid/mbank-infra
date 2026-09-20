# Account request for the Payments BU production account.
# AFT reads this file and triggers the account vending pipeline.
module "mbank_payments_prod" {
  source = "./modules/aft-account-request"

  control_tower_parameters = {
    AccountEmail              = "aws-payments-prod@mbank.com"
    AccountName               = "mbank-payments-prod"
    ManagedOrganizationalUnit = "Workloads/PaymentsBU"
    SSOUserEmail              = "platform-admin@mbank.com"
    SSOUserFirstName          = "Platform"
    SSOUserLastName           = "Admin"
  }

  account_tags = {
    Environment        = "prod"
    Team               = "payments"
    CostCentre         = "CC-PAY-001"
    DataClassification = "confidential"
    ManagedBy          = "aft"
  }

  change_management_parameters = {
    change_requested_by = "platform-team"
    change_reason       = "Initial provisioning of Payments BU production account"
  }

  # PCI-DSS scope; data_classification drives KMS key selection in customizations.
  custom_fields = {
    data_classification = "confidential"
    pci_scope           = "true"
    backup_vault        = "mbank-backup-confidential"
  }

  account_customizations_name = "mbank-payments"
}
