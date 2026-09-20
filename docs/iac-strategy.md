# IaC Strategy — Terraform (Primary) + CloudFormation/CDK (Extension)

## Decision

**Primary IaC: Terraform (HCL)**

**Reason:** Mbank is a multi-cloud organisation. Terraform provides a single control plane across AWS, Azure, and GCP using a consistent HCL language and pipeline pattern. This assessment is AWS-only, but the Terraform estate will extend to other clouds without retooling.

**Extension rule:**
- If a resource is **not yet in the `hashicorp/aws` provider**: wrap a CloudFormation template via `aws_cloudformation_stack` resource — orchestration stays inside Terraform.
- Use **CDK only** as a last resort for isolated resources with genuinely complex wiring that has no viable Terraform or CFN equivalent. Keep it out of the primary path.
- **AFT (Account Factory for Terraform)**: AWS's official Terraform framework for Control Tower account vending — fills the biggest Terraform/Control Tower integration gap without CDK.

---

## Option Comparison

### Option A — Terraform (HCL) ✅ CHOSEN

**What it is:** Declarative HCL language by HashiCorp (now also OpenTofu fork). Uses a provider model. AWS resources declared as `resource "aws_*"` blocks.

**How state works:** State stored externally in an S3 bucket + DynamoDB table for locking. You own and manage the state file. Drift is detected on `terraform plan`.

**Strengths for Mbank:**
- Mature `hashicorp/aws` provider — supports virtually every AWS resource + latest releases
- `terraform plan` output is explicit and auditable — easy to attach to a change ticket + archive for compliance
- Strong community, widely understood in the industry, excellent documentation
- **Multi-cloud capable** — if the bank adds Azure (arm) or GCP later, no retooling required
- Modular via reusable modules (`module` blocks); many community modules exist (e.g., `terraform-aws-modules/eks`)
- Easier to do cross-account deployments using `provider` aliases with `assume_role`
- **Open source** — no vendor lock-in (OpenTofu alternative if needed)
- State file is queryable with `terraform state show/list` — useful for debugging

**Weaknesses & Mitigations:**
| Issue | Mitigation |
|-------|-----------|
| State management is your responsibility | S3 bucket versioning + MFA delete enabled; DynamoDB backup |
| HCL is not a real programming language | Use Python for complex orchestration (generator.py, enforcer.py, merger.py) |
| New AWS services lag behind | Monitor Terraform AWS provider releases; use CloudFormation wrapper for gaps |
| No compile-time checks | Run `terraform validate` + `terraform plan` in CI before apply |
| `terraform destroy` is risky | Implement destroy-guard.sh to block deletion of protected resources |

**Example (Aurora cluster):**
```hcl
resource "aws_rds_cluster" "payments" {
  cluster_identifier      = "payments-aurora"
  engine                  = "aurora-postgresql"
  engine_version          = "15.4"
  master_username         = var.db_username
  manage_master_user_password = true   # Secrets Manager integration
  db_subnet_group_name    = aws_db_subnet_group.payments.name
  vpc_security_group_ids  = [aws_security_group.aurora.id]
  backup_retention_period = 35
  deletion_protection     = true
  storage_encrypted       = true
  kms_key_id              = aws_kms_key.aurora.arn

  tags = var.mandatory_tags
}
```

---

### Option B — AWS CDK (TypeScript / Python)

**What it is:** AWS-developed framework where you write infrastructure in a real programming language (TypeScript, Python, Java, Go). CDK synthesizes your code into CloudFormation templates. CloudFormation then deploys and manages state.

**How state works:** CloudFormation manages state natively — no S3 bucket or DynamoDB table needed. Stack state lives in CloudFormation. Drift detection is built into CloudFormation (`detect-stack-drift`).

**Strengths:**
- **AWS-native** — directly satisfies the assessment constraint to *"use provider-native services."*
- New AWS services get CDK L2 constructs quickly (AWS owns both the service and the CDK)
- **Type safety**: TypeScript compiler catches mistakes before deployment. IDE autocomplete on every property
- Real language features: loops, conditions, reusable classes, unit tests with `jest`
- **CDK Pipelines** (built-in construct) provides a self-mutating CodePipeline: one pipeline manages its own updates
- No state file management — CloudFormation is the single source of truth
- **Higher-level constructs (L2/L3)**: e.g., `new eks.Cluster(this, 'Payments', { ... })` creates the cluster, node groups, OIDC provider, and IAM roles in one call with secure defaults
- `cdk diff` is equivalent to `terraform plan` — shows what will change before applying
- Native integration with **AWS Control Tower** via StackSets

**Weaknesses:**
- **AWS-only** — no value if the bank adds Azure or GCP
- CloudFormation has resource limits (500 resources per stack) — requires stack splitting for large deployments
- CloudFormation rollback behavior can be surprising: a failed update rolls back the entire stack (can be slow)
- Learning curve if the team only knows HCL
- CDK version upgrades can introduce breaking changes across constructs
- Debugging synthesized CloudFormation templates is harder (generated YAML is opaque)

**Example (Aurora Global Database):**
```typescript
import * as rds from 'aws-cdk-lib/aws-rds';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as kms from 'aws-cdk-lib/aws-kms';

const encryptionKey = new kms.Key(this, 'AuroraKey', {
  enableKeyRotation: true,
  description: 'Aurora encryption key for payments',
});

const cluster = new rds.DatabaseCluster(this, 'PaymentsAurora', {
  engine: rds.DatabaseClusterEngine.auroraPostgres({
    version: rds.AuroraPostgresEngineVersion.VER_15_4,
  }),
  writer: rds.ClusterInstance.provisioned('writer', {
    instanceType: ec2.InstanceType.of(ec2.InstanceClass.R6G, ec2.InstanceSize.XLARGE2),
  }),
  readers: [
    rds.ClusterInstance.provisioned('reader1', { instanceType: ... }),
    rds.ClusterInstance.provisioned('reader2', { instanceType: ... }),
  ],
  vpc,
  vpcSubnets: { subnetType: ec2.SubnetType.PRIVATE_ISOLATED },
  storageEncrypted: true,
  storageEncryptionKey: encryptionKey,
  backup: { retention: cdk.Duration.days(35) },
  deletionProtection: true,
  removalPolicy: cdk.RemovalPolicy.RETAIN,
});

// Global database (DR region)
const globalCluster = new rds.CfnGlobalCluster(this, 'GlobalCluster', {
  globalClusterIdentifier: 'payments-global',
  sourceDbClusterIdentifier: cluster.clusterArn,
});
```

**CDK unit test example:**
```typescript
import { Template } from 'aws-cdk-lib/assertions';

test('Aurora has deletion protection enabled', () => {
  const template = Template.fromStack(stack);
  template.hasResourceProperties('AWS::RDS::DBCluster', {
    DeletionProtection: true,
    StorageEncrypted: true,
  });
});
```

---

### Option C — AWS CloudFormation (raw YAML/JSON)

**What it is:** The foundational AWS-native IaC. CDK synthesizes to CloudFormation. StackSets deploy CloudFormation across multiple accounts and regions.

**When to use directly (not via CDK):** Landing zone scaffolding, Control Tower customizations, Service Catalog products. AWS provides official CloudFormation templates for these.

**Strengths:**
- Zero abstraction — full visibility into what is being deployed
- CloudFormation StackSets: deploy the same stack to hundreds of accounts in one operation
- Native AWS Control Tower integration for account vending

**Weaknesses:**
- Verbose YAML — a simple EKS cluster is hundreds of lines
- No abstraction or reuse without significant macro tooling (AWS SAM, Troposphere)
- Resource limits (500 per stack) force awkward stack splitting
- Not recommended as the primary IaC for workloads in 2026

---

## Decision Matrix

| Criterion | Terraform | CDK | CloudFormation |
|-----------|-----------|-----|-----------------|
| **Multi-cloud** | ✅ Yes | ❌ No | ❌ No |
| **Type safety** | ⚠️ Limited | ✅ Yes | ❌ No |
| **State management** | ⚠️ User-managed | ✅ CloudFormation | ✅ CloudFormation |
| **Learning curve** | ⚠️ Medium | ⚠️ Medium | ✅ Steep but manual |
| **Community support** | ✅ Large | ⚠️ Growing | ✅ Large |
| **Resource coverage** | ✅ Excellent | ✅ Excellent (L1 + L2) | ✅ All resources |
| **Modularity** | ✅ Yes (modules) | ✅ Yes (constructs) | ❌ Awkward |
| **Auditability** | ✅ Plain HCL | ⚠️ Generated YAML | ✅ Plain YAML |
| **Compliance** | ✅ Yes | ✅ Yes | ✅ Yes |
| **Cost** | ✅ Free (OSS) | ✅ Free (OSS) | ✅ Free (native) |

---

## Mbank IaC Architecture

```
infra.yaml (YAML declarative)
    ↓
generator.py (Python orchestration)
    ├─ merger.py (deep merge)
    ├─ enforcer.py (regulatory locks)
    └─ validate.py (schema check)
    ↓
terraform.tfvars.json + module.tf (generated)
    ↓
terraform plan/apply (Terraform HCL execution)
    ↓
AWS Resources Deployed
```

**Key insight:** Mbank uses **Terraform as the execution engine** but **Python as the orchestration layer**. This hybrid approach provides:
- **Type safety** at orchestration layer (Python with type hints)
- **Multi-cloud portability** at execution layer (Terraform HCL)
- **Regulatory enforcement** at the validation layer (enforcer.py)
- **Platform abstraction** (app teams only write YAML)

---

## When to Use CloudFormation Wrapper

If a new AWS service is released but not yet in the Terraform provider, wrap it in CloudFormation:

```hcl
# Example: hypothetical AWS service "NewPrivacyManager"
resource "aws_cloudformation_stack" "privacy_manager" {
  name          = "payment-privacy-manager"
  template_body = file("${path.module}/privacy-manager.cfn.yaml")

  parameters = {
    DataClassification = var.data_classification
    KmsKeyArn          = aws_kms_key.app.arn
  }

  tags = local.tags
}

output "privacy_service_arn" {
  value = aws_cloudformation_stack.privacy_manager.outputs["ServiceArn"]
}
```

**When to do this:**
1. Service released in CloudFormation but not yet in Terraform provider
2. Gap expected to be temporary (<6 months)
3. Service is critical path for application

**When NOT to do this:**
- Gap is permanent (then upgrade to CDK for that resource)
- Service is rarely used (manual one-time console deployment + document)

---

## Terraform Best Practices for Mbank

### 1. State Management
- **Backend:** S3 + DynamoDB (managed by platform team)
- **Versioning:** S3 versioning enabled, MFA delete enforced
- **Access:** Read-only for app teams, read-write for CI/CD (assume role via STS)
- **Backup:** Daily snapshots to dr_region (ap-southeast-2)

### 2. Provider Configuration
```hcl
terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }

  backend "s3" {
    bucket         = "mbank-terraform-state"
    key            = "applications/payment/prod"
    region         = "ap-southeast-5"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}

provider "aws" {
  region = "ap-southeast-5"

  default_tags {
    tags = {
      Environment        = var.environment
      Team               = var.team
      CostCentre         = var.cost_centre
      DataClassification = var.data_classification
      ManagedBy          = "terraform"
    }
  }
}
```

### 3. Variable Validation
```hcl
variable "data_classification" {
  type = string
  validation {
    condition     = contains(["public", "internal", "confidential", "restricted"], var.data_classification)
    error_message = "Must be one of: public, internal, confidential, restricted."
  }
}
```

### 4. Output Exports for Discovery
```hcl
output "service_endpoint" {
  value       = aws_lb.app.dns_name
  description = "Load balancer endpoint for application"
  sensitive   = false
}

# Export to SSM Parameter Store for downstream discovery
resource "aws_ssm_parameter" "service_endpoint" {
  name  = "/services/payment-api/${var.environment}/endpoint"
  value = aws_lb.app.dns_name
  type  = "String"
}
```

### 5. Sensitive Data Handling
```hcl
variable "db_password" {
  type      = string
  sensitive = true  # ← Hide from logs
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id      = aws_secretsmanager_secret.db.id
  secret_string  = jsonencode({ password = var.db_password })
  lifecycle {
    ignore_changes = [secret_string]  # ← Prevent overwrites
  }
}
```

### 6. Drift Detection
```bash
# CLI: Detect drift in production account
terraform refresh
terraform plan -out=drift.plan

# If drift detected:
#   Option 1: terraform apply (reconcile to desired state)
#   Option 2: Investigate + manually fix + terraform refresh
#
# All changes audited in CloudTrail
```

---

## Migration Path (If Multi-Cloud Required)

If Mbank adds Azure or GCP:

1. **Reuse generator.py/enforcer.py/merger.py** (cloud-agnostic orchestration)
2. **Swap Terraform AWS provider for Azure/GCP provider** (drop-in replacement)
3. **Update platform modules** (rewrite in Terraform for new provider)
4. **Update infra.yaml schema** (add `cloud` field, e.g., `cloud: azure`)

---

## References

- [Terraform AWS Provider Docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS CDK Docs](https://docs.aws.amazon.com/cdk/)
- [AFT Documentation](https://aws-ia.github.io/terraform-aws-control_tower_account_factory/)
- [HashiCorp Terraform Best Practices](https://developer.hashicorp.com/terraform/cloud-docs/recommended-practices)
- [AWS Well-Architected Framework](https://docs.aws.amazon.com/wellarchitected/latest/userguide/workloads.html)
