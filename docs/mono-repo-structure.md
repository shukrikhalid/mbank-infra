# Mono-Repo Structure — Mbank Infrastructure Platform

## Overview

This document defines the full mono-repo layout for Mbank's AWS infrastructure. The repo is split into two concerns:

- **`org/`** — Platform team owns this. Landing zone, network hub, security baselines, shared services.
- **`applications/`** — App teams contribute here. Each team/department/project adds a folder and declares their infrastructure via `infra.yaml` + `env/*.yaml`. They do not write Terraform.

The **Platform Engineering Pipeline** reads each `infra.yaml` + `env/{dev,staging,prod}.yaml`, validates against a schema, merges org-level defaults, generates Terraform variables, and applies the correct platform module. App teams get self-service infrastructure without writing a single HCL file.

---

## Full Repository Layout

```
mbank-infra/                              ← mono-repo root
│
├── README.md                               ← Overview and quick links
├── CODEOWNERS                              ← ownership rules (see below)
├── .github/
│   ├── workflows/
│   │   ├── org-plan.yml                   ← PR: plan org layer changes
│   │   ├── org-apply.yml                  ← Merge: apply org layer
│   │   ├── app-validate.yml               ← PR: validate infra.yaml schema + security
│   │   ├── app-plan.yml                   ← PR: terraform plan per changed app
│   │   └── app-apply.yml                  ← Merge: terraform apply per changed app
│   └── pull_request_template.md
│
├── org/                                    ← PLATFORM TEAM ONLY
│   ├── management/
│   │   ├── aft/                           ← Account Factory for Terraform
│   │   │   ├── main.tf                    ← AFT module bootstrap
│   │   │   ├── account-requests/          ← one .tf file per AWS account
│   │   │   │   ├── payments-dev.tf        ← NEW: Dev/staging account
│   │   │   │   ├── payments-prod.tf       ← Prod account
│   │   │   │   ├── customertech-dev.tf
│   │   │   │   ├── customertech-prod.tf
│   │   │   │   ├── finance-dev.tf
│   │   │   │   ├── finance-prod.tf
│   │   │   │   ├── public-dev.tf
│   │   │   │   └── public-prod.tf
│   │   │   └── customizations/            ← post-vend baseline (IAM, S3 logs, VPC defaults)
│   │   └── organizations/
│   │       ├── main.tf                    ← OUs, SCPs, org-level Config/CloudTrail
│   │       └── scps/                      ← SCP JSON files
│   ├── security/
│   │   ├── guardduty.tf                   ← org-level GuardDuty
│   │   ├── securityhub.tf                 ← Security Hub aggregator
│   │   ├── cloudtrail.tf                  ← org-level immutable trail
│   │   └── config-aggregator.tf           ← Config aggregator account
│   ├── network/
│   │   ├── tgw.tf                         ← Transit Gateway + route tables
│   │   ├── inspection-vpc.tf              ← Network Firewall + NAT GW
│   │   ├── firewall-rules.tf              ← stateful/stateless rule groups
│   │   └── direct-connect.tf              ← DX + VPN backup
│   └── shared-services/
│       ├── dns.tf                         ← Route 53 Resolver endpoints + PHZs
│       ├── ecr-shared.tf                  ← shared ECR registry (org-wide pull access)
│       └── kms-shared.tf                  ← shared KMS keys per classification tier
│
├── platform/                              ← PLATFORM TEAM ONLY — reusable Terraform modules
│   ├── modules/
│   │   ├── ecs-service/                   ← ECS Fargate + ALB + ECR + Auto Scaling + CW
│   │   ├── ec2-autoscaling/               ← EC2 + ASG + ALB + SSM + CW
│   │   ├── eks-workload/                  ← EKS namespace + IRSA + HPA + NetworkPolicy
│   │   ├── aurora/                        ← Aurora PostgreSQL/MySQL (Multi-AZ + backups)
│   │   ├── dynamodb/                      ← DynamoDB + autoscaling + PITR
│   │   ├── elasticache/                   ← ElastiCache Redis/Valkey (Multi-AZ)
│   │   ├── s3-bucket/                     ← Opinionated S3 (encryption, versioning, lifecycle)
│   │   ├── secrets/                       ← Secrets Manager + optional rotation Lambda
│   │   ├── waf/                           ← WAF v2 WebACL (OWASP core rule set + custom)
│   │   └── monitoring/                    ← CloudWatch dashboard + alarms + SNS + PagerDuty
│   ├── defaults/                          ← Org-wide defaults merged into every infra.yaml
│   │   ├── prod.yaml
│   │   ├── staging.yaml
│   │   └── dev.yaml
│   └── schema/
│       ├── infra-schema.json              ← JSON Schema for infra.yaml validation
│       └── validate.py                    ← validation script (runs in CI)
│
├── applications/                          ← APP TEAMS CONTRIBUTE HERE
│   ├── README.md                          ← "How to add your application" guide
│   ├── payment/
│   │   ├── infra.yaml                     ← Shared app definition (app, team, compute type, databases, features)
│   │   └── env/                           ← Environment-specific overrides
│   │       ├── dev.yaml                   ← Dev/staging config (cpu: 256, memory: 512, desired_count: 1)
│   │       ├── staging.yaml               ← Staging config (cpu: 512, memory: 1024, desired_count: 2)
│   │       └── prod.yaml                  ← Prod config (cpu: 1024, memory: 2048, desired_count: 3)
│   ├── customertech/
│   │   ├── infra.yaml
│   │   └── env/
│   │       ├── dev.yaml
│   │       ├── staging.yaml
│   │       └── prod.yaml
│   ├── finance/
│   │   ├── infra.yaml
│   │   └── env/
│   │       ├── dev.yaml
│   │       ├── staging.yaml
│   │       └── prod.yaml
│   └── public/
│       ├── infra.yaml
│       └── env/
│           ├── dev.yaml
│           ├── staging.yaml
│           └── prod.yaml
│
├── pipeline/
│   ├── generator/
│   │   ├── generator.py                   ← reads infra.yaml + env/X.yaml → produces terraform.tfvars
│   │   ├── merger.py                      ← merges org defaults + app config + env overrides
│   │   ├── enforcer.py                    ← overrides locked compliance values
│   │   └── requirements.txt
│   └── scripts/
│       ├── detect-changed-apps.sh         ← git diff to find which apps changed in PR
│       └── destroy-guard.sh               ← blocks plans with destroy on protected resources
│
├── docs/
│   ├── README.md                          ← Documentation index
│   ├── IMPLEMENTATION_SUMMARY.md          ← Project completion status and overview
│   ├── NAVIGATION_GUIDE.md                ← Master index with clickable links to all files
│   ├── getting-started.md                 ← App team onboarding guide
│   ├── account-strategy.md                ← 2-account model per team, audit controls
│   ├── infra-yaml-reference.md            ← Full attribute reference for infra.yaml + env/*.yaml
│   ├── platform-modules.md                ← Available modules + what each provisions + pricing
│   ├── iac-strategy.md                    ← Terraform vs CDK decision + trade-offs
│   ├── mono-repo-structure.md             ← This file
│   ├── diagrams/
│   │   └── (Mermaid diagrams embedded in diagrams.md)
│   └── runbooks/
│       └── drift-incident.md              ← Incident response for unauthorized changes
│
└── cfn-extensions/                        ← CFN templates for TF provider gaps (rare)
    └── *.yaml
```

---

## CODEOWNERS

```
# Entire org/ layer — platform team approval required
/org/                    @mbank/platform-team

# Platform modules — platform team approval required
/platform/               @mbank/platform-team

# Schema and pipeline — platform team approval required
/pipeline/               @mbank/platform-team
/platform/schema/        @mbank/platform-team

# App team folders — each team approves their own changes
# Platform team co-reviews all app changes (security gate)
/applications/payment/          @mbank/payments-team @mbank/platform-team
/applications/customertech/     @mbank/customertech-team @mbank/platform-team
/applications/finance/          @mbank/finance-team @mbank/platform-team
/applications/public/           @mbank/public-team @mbank/platform-team
```

**Rules:**
- `org/` and `platform/` changes require 2 approvals from `@mbank/platform-team`.
- `applications/<team>/` changes require 1 approval from the owning team + 1 from `@mbank/platform-team`.
- `infra.yaml` schema changes (in `platform/schema/`) require a platform team RFC before PR.

---

## Application Configuration: infra.yaml vs env/*.yaml

Each application is split into **shared configuration** (infra.yaml) and **environment-specific overrides** (env/{dev,staging,prod}.yaml).

### infra.yaml (Shared — define once, use in all environments)

```yaml
# applications/payment/infra.yaml
app: payment-api
team: payments
cost_centre: CC-PAY-001

git_repo: https://github.com/mbank/payment-api
contact_email: payments-team@mbank.com
slo_availability: 99.9
slo_latency_p99_ms: 500

compute:
  type: ecs
  # cpu, memory, desired_count → env/*.yaml (varies by environment)
  container_port: 8080
  health_check_path: /health

databases:
  - name: payment-db
    engine: aurora-postgresql
    storage_encrypted: true
    # instance_class, num_instances → env/*.yaml

features:
  waf: true
  xray: true
  rds_proxy: true
```

### env/dev.yaml (Development overrides)

```yaml
# applications/payment/env/dev.yaml
environment: dev
data_classification: public  # Dummy data

compute:
  cpu: 256
  memory: 512
  desired_count: 1

databases:
  - name: payment-db
    instance_class: db.t3.small
    num_instances: 1

monitoring:
  alarm_cpu_threshold: 95
  alarm_error_rate_threshold: 50

tags:
  Environment: dev
  Team: payments
```

### env/staging.yaml (Staging overrides)

```yaml
environment: staging
data_classification: confidential  # Realistic data

compute:
  cpu: 512
  memory: 1024
  desired_count: 2

databases:
  - name: payment-db
    instance_class: db.r6g.medium
    num_instances: 2

monitoring:
  alarm_cpu_threshold: 80
  alarm_error_rate_threshold: 5

tags:
  Environment: staging
```

### env/prod.yaml (Production overrides)

```yaml
environment: prod
data_classification: confidential  # 🔒 Locked by enforcer

compute:
  cpu: 1024
  memory: 2048
  desired_count: 3

databases:
  - name: payment-db
    instance_class: db.r6g.large
    num_instances: 3

monitoring:
  alarm_cpu_threshold: 70
  alarm_error_rate_threshold: 0.1
  pagerduty_service_key_secret: /mbank/payment/pagerduty-key

tags:
  Environment: prod
  Team: payments
  CostCentre: CC-PAY-001
```

---

## Pipeline Flow

```
Developer commits to feature branch
         ↓
PR triggers: app-validate.yml
  ├─ git diff → detect changed apps (detect-changed-apps.sh)
  ├─ For each changed app:
  │  ├─ schema validate (infra.yaml + env/X.yaml)
  │  ├─ enforcer dry-run (check locked fields)
  │  └─ checkov security scan
  ├─ comment on PR: "✓ Payment validation passed"
         ↓
PR triggers: app-plan.yml
  ├─ For each changed app/env:
  │  ├─ generator.py: merger + enforcer + validate
  │  ├─ terraform plan
  │  └─ upload plan artifact
  ├─ comment on PR: "terraform plan ready for review"
         ↓
Developer/reviewers approve + merge
         ↓
Push to main triggers: app-apply.yml
  ├─ detect changed apps
  ├─ destroy-guard.sh: block if destroying protected resources
  ├─ terraform apply (sequential, per app)
  ├─ smoke-test: curl ALB health endpoint
  └─ result: "✓ payment-api deployed to prod"
```

---

## Key Principles

1. **Application teams don't write Terraform.** They write YAML.
2. **Shared vs. Environment-specific.** infra.yaml is immutable across envs; env/*.yaml overrides resource sizing.
3. **Platform team controls the platform.** org/, platform/, and pipeline/ are platform-team-only.
4. **Validation first.** Every infra.yaml + env/*.yaml must pass schema validation + Checkov before PR merge.
5. **Defaults + Enforcement.** Platform defaults are merged in, regulatory enforcer locks critical fields.
6. **2-account model.** Dev account holds dev+staging, Prod account holds production. Clear audit separation.
7. **Immutable CI/CD.** All changes go through git + PR. No manual console changes in prod.
8. **Audit trail.** CloudTrail logs every terraform apply with who, what, when, where.

---

## References

- [Getting Started](getting-started.md) — Onboarding new applications
- [Account Strategy](account-strategy.md) — 2-account model, audit controls, break-glass access
- [infra-yaml-reference.md](infra-yaml-reference.md) — Complete field reference
- [Platform Modules](platform-modules.md) — Available infrastructure modules
- [IaC Strategy](iac-strategy.md) — Terraform vs CDK decision
- [Architecture Diagrams](diagrams/) — Visual reference
