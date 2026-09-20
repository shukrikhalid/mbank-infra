# Global customizations — applied by AFT to every vended account immediately after provisioning.
# Runs in the context of the target (vended) account via AWSAFTExecution role.

terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── IAM account password policy ────────────────────────────────────────────────
# BNM TRM guideline 10.1: passwords >= 16 chars, complexity required, 90-day rotation.

resource "aws_iam_account_password_policy" "baseline" {
  minimum_password_length        = 16
  require_uppercase_characters   = true
  require_lowercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true
  max_password_age               = 90
  password_reuse_prevention      = 12
  hard_expiry                    = false
}

# ── Default EBS encryption ─────────────────────────────────────────────────────
# Ensures any EBS volume created without an explicit KMS key is still encrypted.

resource "aws_ebs_encryption_by_default" "enabled" {
  enabled = true
}

# ── S3 account-level Block Public Access ───────────────────────────────────────
# Belt-and-suspenders alongside the deny-public-s3 SCP.

resource "aws_s3_account_public_access_block" "enabled" {
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── Delete default VPCs in all regions except ap-southeast-5 ──────────────────
# AFT's aft_feature_delete_default_vpcs_enabled covers all regions; this
# null_resource acts as belt-and-suspenders and provides an audit trail.

resource "null_resource" "delete_default_vpcs" {
  triggers = {
    account_id = data.aws_caller_identity.current.account_id
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      PRIMARY_REGION="ap-southeast-5"

      REGIONS=$(aws ec2 describe-regions \
        --all-regions \
        --query "Regions[?RegionName!='${PRIMARY_REGION}'].RegionName" \
        --output text)

      for REGION in $REGIONS; do
        VPC_ID=$(aws ec2 describe-vpcs \
          --region "$REGION" \
          --filters Name=isDefault,Values=true \
          --query "Vpcs[0].VpcId" \
          --output text 2>/dev/null || true)

        [ "$VPC_ID" = "None" ] || [ -z "$VPC_ID" ] && continue

        echo "Removing default VPC $VPC_ID in $REGION"

        # Delete all subnets
        SUBNETS=$(aws ec2 describe-subnets \
          --region "$REGION" \
          --filters "Name=vpc-id,Values=$VPC_ID" \
          --query "Subnets[].SubnetId" --output text)
        for SUBNET in $SUBNETS; do
          aws ec2 delete-subnet --region "$REGION" --subnet-id "$SUBNET"
        done

        # Detach and delete internet gateway
        IGW=$(aws ec2 describe-internet-gateways \
          --region "$REGION" \
          --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
          --query "InternetGateways[0].InternetGatewayId" --output text 2>/dev/null || true)
        if [ "$IGW" != "None" ] && [ -n "$IGW" ]; then
          aws ec2 detach-internet-gateway --region "$REGION" --internet-gateway-id "$IGW" --vpc-id "$VPC_ID"
          aws ec2 delete-internet-gateway --region "$REGION" --internet-gateway-id "$IGW"
        fi

        # Delete the VPC itself
        aws ec2 delete-vpc --region "$REGION" --vpc-id "$VPC_ID"
        echo "Deleted default VPC $VPC_ID in $REGION"
      done

      echo "Default VPC cleanup complete for account ${data.aws_caller_identity.current.account_id}"
    EOT
  }
}

# ── VPC Flow Logs in ap-southeast-5 ───────────────────────────────────────────
# Captures ALL traffic on the default VPC in the primary region until the
# platform team provisions the org VPC via the network module.

resource "aws_cloudwatch_log_group" "vpc_flow_log" {
  name              = "/mbank/vpc-flow-logs/${data.aws_caller_identity.current.account_id}"
  retention_in_days = 90 # matches org-wide app log retention minimum

  tags = {
    Environment = "management"
    Team        = "platform"
    ManagedBy   = "aft"
  }
}

data "aws_iam_policy_document" "vpc_flow_log_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "vpc_flow_log_write" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = [aws_cloudwatch_log_group.vpc_flow_log.arn]
  }
}

resource "aws_iam_role" "vpc_flow_log" {
  name               = "mbank-vpc-flow-log-role"
  assume_role_policy = data.aws_iam_policy_document.vpc_flow_log_assume.json

  tags = {
    Environment = "management"
    Team        = "platform"
    ManagedBy   = "aft"
  }
}

resource "aws_iam_role_policy" "vpc_flow_log" {
  name   = "vpc-flow-log-write"
  role   = aws_iam_role.vpc_flow_log.id
  policy = data.aws_iam_policy_document.vpc_flow_log_write.json
}

data "aws_vpc" "default_primary" {
  default = true
}

resource "aws_flow_log" "default_vpc_primary" {
  vpc_id          = data.aws_vpc.default_primary.id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.vpc_flow_log.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_log.arn

  tags = {
    Environment = "management"
    Team        = "platform"
    ManagedBy   = "aft"
  }
}
