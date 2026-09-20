# infra.yaml Reference Guide

Complete attribute reference for application infrastructure configuration files (`applications/*/infra.yaml`).

## Overview

The `infra.yaml` file defines the infrastructure requirements for a Mbank application. It is merged with environment-specific platform defaults, validated against the JSON schema, and processed by the pipeline to generate Terraform configurations.

**Important:** Fields marked with 🔒 **LOCKED** cannot be overridden by application teams—they are enforced by the regulatory enforcer for compliance.

---

## Required Fields

### `app`
- **Type:** `string`
- **Constraints:** Pattern `^[a-z0-9-]+$`, max 40 characters
- **Description:** Application identifier (lowercase alphanumeric with hyphens)
- **Example:** `payment-api`, `crm-api`, `finance-api`, `public-web`
- **Notes:** Must be globally unique within Mbank

### `team`
- **Type:** `string`
- **Enum:** `payments`, `customertech`, `finance`, `public`
- **Description:** Team responsible for the application
- **Example:** `payments`
- **Notes:** Used for RBAC and cost allocation

### `environment`
- **Type:** `string`
- **Enum:** `prod`, `staging`, `dev`
- **Description:** Deployment environment
- **Example:** `prod`
- **Notes:** Determines which platform defaults are applied

### `cost_centre`
- **Type:** `string`
- **Constraints:** Pattern `^CC-[A-Z]+-[0-9]+$`
- **Description:** Cost centre for billing and chargeback
- **Example:** `CC-PAY-001` (payments), `CC-CRM-001` (customertech)
- **Notes:** Required for financial tracking and compliance

### `data_classification`
- **Type:** `string`
- **Enum:** `public`, `internal`, `confidential`, `restricted`
- **Description:** Data classification level (determines encryption key, access controls)
- **Mapping:**
  - `public` → uses `kms-public` key, no access restrictions
  - `internal` → uses `kms-internal` key, Mbank-internal access
  - `confidential` → uses `kms-confidential` key, PCI DSS scope (payment data)
  - `restricted` → uses `kms-restricted` key, executive/financial data
- **Example:** `confidential` (payment systems), `restricted` (finance systems)

### `compute`
- **Type:** `object`
- **Required sub-fields:**
  - **`type`** `(string)`: Compute service type
    - **Enum:** `ecs`, `ec2`, `eks`
    - Example: `type: ecs`
- **Optional sub-fields:**
  - **`cpu`** `(number)`: CPU units (128-4096)
    - Default: varies by platform defaults
    - Example: `cpu: 1024`
  - **`memory`** `(number)`: Memory in MB (256-30720)
    - Example: `memory: 2048`
  - **`desired_count`** `(integer)`: Number of instances/tasks (1-100)
    - Default: 2
    - Example: `desired_count: 3`
  - **`container_port`** `(integer)`: Container port (1-65535)
    - Default: 8080
    - Example: `container_port: 8080`
  - **`health_check_path`** `(string)`: HTTP endpoint for health checks
    - Default: `/health`
    - Example: `health_check_path: /actuator/health`
  - **`instance_type`** `(string)`: EC2 instance type (ec2 only)
    - Example: `instance_type: t3.medium`
  - **`min_size`** `(integer)`: Minimum ASG size (EC2 only)
    - Example: `min_size: 2`
  - **`max_size`** `(integer)`: Maximum ASG size (EC2 only)
    - Example: `max_size: 10`

### `git_repo`
- **Type:** `string`
- **Format:** Valid Git repository URL (HTTPS or SSH)
- **Description:** Source code repository for the application
- **Example:** `git_repo: https://github.com/mbank/payment-api`
- **Notes:** Used for linking to source, CI/CD triggers, and audit trail

### `contact_email`
- **Type:** `string`
- **Format:** Valid email address
- **Description:** Team lead or platform contact for the application
- **Example:** `contact_email: payments-team@mbank.com`
- **Notes:** Used for notifications, access requests, incident escalation

### `slo_availability`
- **Type:** `number`
- **Constraints:** 95.0-99.99 (percentage)
- **Description:** Service Level Objective for availability (uptime percentage)
- **Example:** `slo_availability: 99.9` (four nines = ~45 minutes downtime/month)
- **Notes:** Affects alert thresholds and escalation policies
- **Mapping:**
  - 95.0 = 3.6 hrs downtime/month (non-critical services)
  - 99.0 = 7.2 min downtime/month (standard)
  - 99.5 = 3.6 min downtime/month (high)
  - 99.9 = 43 sec downtime/month (critical)
  - 99.99 = 4.3 sec downtime/month (payment systems)

### `slo_latency_p99_ms`
- **Type:** `number`
- **Constraints:** 10-10000 (milliseconds)
- **Description:** 99th percentile response time latency objective
- **Example:** `slo_latency_p99_ms: 500` (P99 must be ≤ 500ms)
- **Notes:** Used for CloudWatch alarm thresholds and capacity planning
- **Examples by SLO:**
  - Dev: 2000ms (relaxed, testing focus)
  - Staging: 1000ms (realistic)
  - Prod (payment): 500ms (strict, compliance-critical)
  - Prod (public): 1500ms (relaxed, external-facing)

### `tags`
- **Type:** `object`
- **Required sub-fields:**
  - **`Environment`** `(string)`: Must match top-level `environment` field
  - **`Team`** `(string)`: Must match top-level `team` field
  - **`CostCentre`** `(string)`: Must match top-level `cost_centre` field
  - **`DataClassification`** `(string)`: Must match top-level `data_classification`
- **Optional sub-fields:** Any additional custom tags
- **Example:**
  ```yaml
  tags:
    Environment: prod
    Team: payments
    CostCentre: CC-PAY-001
    DataClassification: confidential
    Application: payment-processor
  ```

---

## Optional Fields

### `public_facing`
- **Type:** `boolean`
- **Default:** `false`
- **Description:** Whether the application is internet-facing (requires ALB + WAF)
- **Example:** `public_facing: true`

### `domain`
- **Type:** `string`
- **Format:** Valid hostname
- **Description:** Custom domain name or FQDN
- **Example:** `domain: www.mbank.com` or `domain: payment-api.internal.mbank.com`

### `databases`
- **Type:** `array` of objects
- **Description:** Database configurations (RDS Aurora, DynamoDB, ElastiCache)
- **Array item fields:**
  - **`name`** (required): Database name
  - **`engine`** (required): Database engine type
    - **Enum:** `aurora-postgresql`, `aurora-mysql`, `dynamodb`, `redis`
  - **`instance_class`** (RDS): DB instance type (e.g., `db.r6g.large`)
  - **`node_type`** (ElastiCache): Cache node type (e.g., `cache.t3.medium`)
  - **`num_instances`** (optional): Number of nodes/replicas (1-15)
  - **`storage_encrypted`** 🔒: Must be `true` (enforced by regulatory lockdown)
- **Example:**
  ```yaml
  databases:
    - name: payment-db
      engine: aurora-postgresql
      instance_class: db.r6g.large
      num_instances: 3
      storage_encrypted: true
    - name: payment-cache
      engine: redis
      node_type: cache.t3.medium
      num_cache_nodes: 2
  ```

### `features`
- **Type:** `object`
- **Optional boolean flags:**
  - **`waf`** (default: `false`): Enable AWS WAF v2
  - **`cdn`** (default: `false`): Enable CloudFront CDN
  - **`xray`** (default: `false`): Enable AWS X-Ray tracing
  - **`rds_proxy`** (default: `false`): Enable RDS Proxy for connection pooling
- **Example:**
  ```yaml
  features:
    waf: true
    cdn: true
    xray: false
    rds_proxy: true
  ```

### `monitoring`
- **Type:** `object`
- **Optional fields:**
  - **`alarm_cpu_threshold`** (integer, 1-100): CPU alarm threshold percentage
    - Default: from environment defaults (prod: 80, staging: 90, dev: 95)
  - **`alarm_error_rate_threshold`** (number, 0-100): Error rate threshold %
  - **`pagerduty_service_key_secret`** (string): Secrets Manager secret name for PagerDuty integration
    - Example: `/mbank/payment/pagerduty-key`
- **Example:**
  ```yaml
  monitoring:
    alarm_cpu_threshold: 70
    alarm_error_rate_threshold: 0.1
    pagerduty_service_key_secret: /mbank/payment/pagerduty-key
  ```

### `secrets`
- **Type:** `array` of strings
- **Description:** List of Secrets Manager secret names used by the application
- **Example:**
  ```yaml
  secrets:
    - /mbank/payment/db-password
    - /mbank/payment/stripe-api-key
    - /mbank/payment/encryption-key
  ```
- **Notes:** Application can access these secrets via IAM role

---

## Locked Fields (Enforcer Override)

These fields **cannot** be overridden by application teams—they are enforced by the regulatory enforcer:

### Global Locks (All Environments)
- **`encryption.at_rest: true`** — Always enabled 🔒
- **`encryption.in_transit: true`** — Always enabled 🔒
- **`logging.cloudtrail: enabled`** — Always enabled 🔒

### Production-Only Locks
- **`databases[*].deletion_protection: true`** 🔒 (prod only)
- **`databases[*].multi_az: true`** 🔒 (prod only)
- **`databases[*].backup_retention_days: max(35, provided_value)`** 🔒 (prod only, minimum 35 days for BNM compliance)

---

## Environment-Specific Defaults

Values in platform defaults files are merged with infra.yaml. Teams can override defaults except for locked fields.

### Production Defaults (`prod.yaml`)
- Multi-AZ: **required** for all resources
- Backup retention: **minimum 35 days** (BNM: 7-year audit trail)
- Audit logs: **2555 days** (7 years)
- Encryption: **mandatory at rest and in transit**
- Deletion protection: **mandatory for databases**
- Monitoring: **dashboards enabled, alarms strict**

### Staging Defaults (`staging.yaml`)
- Multi-AZ: **optional** (cost saving)
- Backup retention: **7 days** (reduced from prod)
- Encryption: **still mandatory**
- Deletion protection: **optional**
- Monitoring: **relaxed thresholds**

### Dev Defaults (`dev.yaml`)
- Multi-AZ: **disabled** (cost saving)
- Backups: **disabled** (no backup)
- Encryption: **still mandatory**
- Monitoring: **very relaxed**
- CloudTrail/GuardDuty: **disabled** (cost saving)

---

## Complete Examples

### Example 1: Minimal ECS Service (Development)

```yaml
# applications/demo/infra.yaml
app: demo-api
team: public
environment: dev
cost_centre: CC-PUB-001
data_classification: public

compute:
  type: ecs
  cpu: 256
  memory: 512
  desired_count: 1
  container_port: 8080

tags:
  Environment: dev
  Team: public
  CostCentre: CC-PUB-001
  DataClassification: public
```

### Example 2: Full Payment ECS Service (Production)

```yaml
# applications/payment/infra.yaml
app: payment-api
team: payments
environment: prod
cost_centre: CC-PAY-001
data_classification: confidential

compute:
  type: ecs
  cpu: 1024
  memory: 2048
  desired_count: 3
  container_port: 8080
  health_check_path: /health

public_facing: false
domain: payment-api.internal.mbank.com

databases:
  - name: payment-db
    engine: aurora-postgresql
    instance_class: db.r6g.large
    num_instances: 3
    storage_encrypted: true

features:
  waf: true
  cdn: false
  xray: true
  rds_proxy: true

monitoring:
  alarm_cpu_threshold: 70
  alarm_error_rate_threshold: 0.1
  pagerduty_service_key_secret: /mbank/payment/pagerduty-key

secrets:
  - /mbank/payment/db-password
  - /mbank/payment/stripe-api-key
  - /mbank/payment/encryption-key

tags:
  Environment: prod
  Team: payments
  CostCentre: CC-PAY-001
  DataClassification: confidential
```

### Example 3: Finance ECS with Restricted Data (Production)

```yaml
# applications/finance/infra.yaml
app: finance-api
team: finance
environment: prod
cost_centre: CC-FIN-001
data_classification: restricted

compute:
  type: ecs
  cpu: 1024
  memory: 2048
  desired_count: 3
  container_port: 8443
  health_check_path: /actuator/health

public_facing: false
domain: finance-api.internal.mbank.com

databases:
  - name: finance-db
    engine: aurora-postgresql
    instance_class: db.r6g.xlarge
    num_instances: 3
    storage_encrypted: true

features:
  waf: true
  cdn: false
  xray: true
  rds_proxy: true

monitoring:
  alarm_cpu_threshold: 60
  alarm_error_rate_threshold: 0.5
  pagerduty_service_key_secret: /mbank/finance/pagerduty-key

secrets:
  - /mbank/finance/db-password
  - /mbank/finance/reporting-key
  - /mbank/finance/audit-signing-key
  - /mbank/finance/encryption-key

tags:
  Environment: prod
  Team: finance
  CostCentre: CC-FIN-001
  DataClassification: restricted
```

### Example 4: Public-Facing Portal with CDN and WAF

```yaml
# applications/public/infra.yaml
app: public-web
team: public
environment: prod
cost_centre: CC-PUB-001
data_classification: public

compute:
  type: ecs
  cpu: 512
  memory: 1024
  desired_count: 2
  container_port: 3000
  health_check_path: /

public_facing: true
domain: www.mbank.com

features:
  waf: true
  cdn: true
  xray: false
  rds_proxy: false

monitoring:
  alarm_cpu_threshold: 80
  alarm_error_rate_threshold: 2

secrets:
  - /mbank/public/cms-api-key
  - /mbank/public/cloudflare-token

tags:
  Environment: prod
  Team: public
  CostCentre: CC-PUB-001
  DataClassification: public
```

---

## Validation & Processing

### Schema Validation
Every infra.yaml is validated against `platform/schema/infra-schema.json` using:
```bash
python platform/schema/validate.py applications/*/infra.yaml
```

### Pipeline Processing
The generator pipeline processes each infra.yaml as follows:
1. **Load** application-specific infra.yaml
2. **Merge** with environment defaults (deep merge, dicts recurse)
3. **Enforce** regulatory locks (encryption, MFA, backup retention)
4. **Validate** against JSON schema
5. **Generate** `terraform.tfvars.json` and `module.tf`

### Regulatory Compliance
- **BNM** (Bank Negara Malaysia): 7-year audit retention, data residency ap-southeast-5
- **PCI DSS**: Payment data classified `confidential` requires encryption, MFA, monitoring
- **PDPA**: Personal data classified `internal` requires encryption, access logs
