# Drift Incident Runbook

**Version:** 2.0  
**Last Updated:** 2026-09-21  
**Severity:** CRITICAL (production infrastructure unauthorized changes)

---

## Overview

**Definition:** Drift = unauthorized resource changes outside of Terraform (manual AWS console edits, CLI changes, or misconfigured automation).

**Why It's Dangerous:**
- 🔴 Breaks IaC contract (desired state ≠ actual state)
- 🔴 Audit trail violation (change not tracked in Git/Terraform)
- 🔴 Compliance violation (BNM requires traceable changes)
- 🔴 Blast radius unknown (could affect customers)
- 🔴 Recurrence risk (vulnerability not locked down)

**Triggers:**
- AWS Config rule fires (drift detected, <15 min detection)
- Manual detection via `terraform plan` (weekly/monthly)
- Security audit finding
- CloudTrail log analysis (unexpected API calls)

---

## Step 1: Detect & Alert (0-5 minutes)

### Detection Methods

**Method 1: AWS Config Rules** (Automated, <5 min latency)
```bash
# Config rule checks for drift every 15 minutes
# Examples: encrypted-volumes, unrestricted-ssh, cloudtrail-enabled

# Trigger chain:
# 1. Config rule detects non-compliance
# 2. CloudWatch event fires
# 3. SNS sends alert to ops team
# 4. PagerDuty creates incident
```

**Method 2: Terraform Plan** (Manual, weekly)
```bash
cd mbank-infra/org
terraform init
terraform plan -out drift.tfplan

# If diff shows unexpected changes:
# Example:
# "# aws_route_table.prod_table will be updated in-place
#  - route {
#      destination_cidr_block = "0.0.0.0/0"  # UNEXPECTED ROUTE ADDED
#      nat_gateway_id         = "ngw-xyz"
#    }"
```

**Method 3: CloudTrail Analysis** (Manual, on-demand)
```bash
# Query CloudTrail for unexpected API calls
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=ResourceName,AttributeValue=prod-route-table \
  --max-results 50 \
  --output json | jq '.Events[] | {EventTime, Username, CloudTrailEvent}'

# Look for:
# - AuthorizeSecurityGroupIngress (open ports)
# - ModifyRouteTable (change routes)
# - ModifyDBInstance (DB config changes)
# - PutBucketPolicy (S3 access changes)
```

### Alert Acknowledgment

**On-call Engineer Actions:**
1. Receive PagerDuty alert (within 5 min)
2. Open Slack #incidents channel
3. Type: `@here Drift incident detected: [resource type] in [account]`
4. Acknowledge PagerDuty (start timer)
5. Join war room (Slack + Zoom, if critical)

---

## Step 2: Forensics - Identify Actor (5-15 minutes)

### CloudTrail Forensic Query

**Find Who Made the Change:**
```bash
# Query CloudTrail for the drift-related API call
# Example: Unauthorized route table modification

aws cloudtrail lookup-events \
  --lookup-attributes \
    AttributeKey=ResourceName,AttributeValue=rtb-12345abcde \
    AttributeKey=EventName,AttributeValue=CreateRoute \
  --max-results 10 \
  --output json > drift_events.json

# Extract key information:
jq '.Events[] | {
  EventTime,
  Username,
  CloudTrailEvent: (.CloudTrailEvent | fromjson | {
    eventSource,
    eventName,
    sourceIPAddress,
    userAgent,
    requestParameters
  })
}' drift_events.json
```

**Sample Output:**
```json
{
  "EventTime": "2026-09-21T14:32:15Z",
  "Username": "arn:aws:iam::123456789012:user/alice@paymentsteam",
  "CloudTrailEvent": {
    "eventSource": "ec2.amazonaws.com",
    "eventName": "CreateRoute",
    "sourceIPAddress": "192.0.2.10",
    "userAgent": "aws-cli/2.0.0",
    "requestParameters": {
      "routeTableId": "rtb-12345abcde",
      "destinationCidrBlock": "0.0.0.0/0",
      "gatewayId": "igw-xyz"
    }
  }
}
```

### Actor Analysis

| Field | Value | Analysis |
|-------|-------|----------|
| **Principal** | `alice@paymentsteam` | Payments team IAM user |
| **Timestamp** | 2026-09-21 14:32:15 UTC+8 (09:32 UTC) | Business hours, unexpected |
| **Source IP** | 192.0.2.10 | Office VPN address |
| **Method** | AWS CLI | Intentional (not console accident) |
| **Intent** | Open 0.0.0.0/0 route | ⚠️ SUSPICIOUS (security violation) |

### Actor Classification

```
Classify the actor's intent:

1. ACCIDENTAL (Misconfiguration)
   - Example: Alice ran wrong terraform command
   - Indicator: User has permission, made logical mistake
   - Action: Proceed to remediation (low severity)

2. UNAUTHORIZED (Policy Violation)
   - Example: Alice bypassed change approval process
   - Indicator: User has permission but violated change control
   - Action: Escalate to manager (medium severity)

3. MALICIOUS (Security Threat)
   - Example: Compromised credentials or insider threat
   - Indicator: User doesn't have permission, IP unusual, after-hours
   - Action: Security team involvement, revoke credentials (critical severity)
```

**For This Example:**
- User "alice" has `PaymentsDeveloper` IAM role (allowed prod access)
- But opened route to 0.0.0.0/0 (violates security group policy)
- Classification: **UNAUTHORIZED** (bypassed network policy)
- Severity: **MEDIUM** (misconfiguration, not malicious)

---

## Step 3: Assess Blast Radius (15-25 minutes)

### Determine Affected Resources

**AWS Config Relationship Graph:**
```bash
# Use AWS Config to find resource relationships
aws configservice describe-configuration-items \
  --configuration-item-types AWS::EC2::RouteTable \
  --output json | jq '.ConfigurationItems[] | select(.resourceId=="rtb-12345abcde")'

# Find related resources:
# - Which VPCs are connected to this route table?
# - Which subnets use this route table?
# - Which EC2 instances are in affected subnets?
# - Which network interfaces are affected?
```

**Manual Dependency Map:**
```
Drift: Modified route table rtb-12345abcde
│
├─ VPC: vpc-payment-prod (Payments production)
│  └─ Subnets affected:
│     ├─ subnet-5a (private, 10 EC2 instances)
│     ├─ subnet-5b (private, 8 EC2 instances)
│     └─ subnet-5c (private, 5 EC2 instances)
│
├─ Application Stack:
│  ├─ ECS Cluster: payment-api-prod (23 tasks running)
│  ├─ ALB: payment-api-lb (routing traffic)
│  └─ Affected microservices:
│     ├─ payment-processor (critical)
│     ├─ transaction-ledger (critical)
│     └─ fraud-detector (important)
│
└─ Customer Impact:
   ├─ Payment team: 1,500+ transactions/hour
   ├─ Customers affected: ~50,000 active users
   └─ Revenue impact: $150/min (payment processing down)
```

### Impact Assessment Table

| Factor | Assessment | Impact |
|--------|-----------|--------|
| **Scope** | Route table for prod payment VPC | High |
| **Severity** | Opened 0.0.0.0/0 to Internet (bypass firewall) | Critical |
| **Services Down** | Payment API, Fraud Detector | Critical |
| **Customer Impact** | Payment processing blocked | Critical |
| **Data Exposure** | No (routing only, not data access) | Low |
| **Estimated Revenue Loss** | ~$150/min (if not fixed) | $9,000/hour |

### Health Check Query

```bash
# Verify current health status
# 1. Are payments processing?
curl -H "Authorization: Bearer $TOKEN" \
  https://api.mbank.com/v1/health

# Response: 503 Service Unavailable (bad routing)

# 2. Check downstream dependencies
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:ap-southeast-5:...
  
# Response: unhealthy_reason: "Health checks failed with these codes: [502]"

# 3. Verify database connectivity
aws rds describe-db-instances \
  --db-instance-identifier payment-api-prod \
  --query 'DBInstances[0].DBInstanceStatus'
  
# Response: "available" (database is OK, networking is broken)

Conclusion: Networking drift broke application connectivity.
```

---

## Step 4: Contain the Incident (25-35 minutes)

### Immediate Containment

**Decision Tree:**
```
Is the drift MALICIOUS?
│
├─ YES (Compromised credentials, unauthorized access)
│  └─ → Execute Step 4a: MALICIOUS Containment
│
└─ NO (Accidental, misconfiguration)
   └─ → Execute Step 4b: ACCIDENTAL Containment
```

### Step 4a: MALICIOUS Containment

**If credentials are compromised:**

1. **Kill the IAM Session (Immediate)**
   ```bash
   # Revoke all temporary credentials for the user
   aws iam update-access-key \
     --access-key-id AKIA123456ABCDEF \
     --status Inactive \
     --user-name alice
   
   # Force sign out of all AWS sessions
   aws iam create-login-profile \
     --user-name alice \
     --password $(openssl rand -base64 32) \
     --password-reset-required
   
   # Result: alice cannot use AWS for 24 hours
   ```

2. **Isolate the Account (SCP Restriction)**
   ```bash
   # Apply restrictive SCP to payment team OUs
   # Policy: deny-all-except-break-glass
   
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Sid": "DenyAllExceptBreakGlass",
         "Effect": "Deny",
         "Action": "*",
         "Resource": "*",
         "Condition": {
           "StringNotEquals": {
             "aws:PrincipalArn": "arn:aws:iam::*:role/BreakGlassRole"
           }
         }
       }
     ]
   }
   
   # This prevents ALL access except break-glass role
   # On-call engineers must use break-glass to recover
   ```

3. **Notify Security Team (Escalation)**
   ```bash
   # Create SecurityHub finding
   aws securityhub create-findings \
     --findings '[{
       "Title": "Suspected Compromised IAM Credentials",
       "Description": "User alice made unauthorized drift changes from unusual IP",
       "Severity": { "Label": "CRITICAL" },
       "Types": ["Effects/Data Exposure/Unauthorized Access"]
     }]'
   
   # Notify via Slack
   @channel SECURITY INCIDENT: 
   Compromised IAM credentials (user: alice)
   Unauthorized route table modification detected
   Account isolated via SCP (break-glass access only)
   Credential revoked, force password reset
   ```

### Step 4b: ACCIDENTAL Containment

**If it's a misconfiguration:**

1. **Review Change (1 min)**
   ```bash
   # Confirm the drift is understood
   # Example: Route table now allows 0.0.0.0/0
   # This violates "All egress must route through Inspection VPC"
   ```

2. **Notify Team Lead (2 min)**
   ```bash
   # Slack message to alice's manager
   @payments-lead: Drift incident - alice opened prod route table to 0.0.0.0/0
   This violated security policy. Initiating remediation.
   Will reverse change in 5 minutes unless you object.
   ```

3. **Proceed to Remediation (3 min)**
   ```bash
   # Get approval to roll back
   # Since it's accidental, manager usually approves quickly
   ```

---

## Step 5: Remediate Safely (35-50 minutes)

### Pre-Recovery Validation

**Backup Current State:**
```bash
# Take a snapshot before recovery (just in case)
aws ec2 describe-route-tables --route-table-ids rtb-12345abcde \
  --output json > /tmp/route_table_backup_$(date +%s).json

# Also get Terraform state
terraform state show aws_route_table.prod_table \
  > /tmp/terraform_state_backup_$(date +%s).txt
```

**Health Check (Before Recovery):**
```bash
# Document current bad state
curl -i https://api.mbank.com/v1/health
# Response: 503 (expected, broken networking)

aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:ap-southeast-5:...
# Response: unhealthy (expected)
```

### Recovery Plan (Terraform)

**Dry-Run Plan:**
```bash
cd mbank-infra/org/network

# Initialize Terraform
terraform init

# Create recovery plan (don't apply yet)
terraform plan -out recovery.tfplan

# Show what will change
terraform show recovery.tfplan

# Expected output:
# "# aws_route_table.prod_table will be updated in-place
#  - route {
#      destination_cidr_block = "0.0.0.0/0"  ← WILL BE REMOVED
#      nat_gateway_id         = "ngw-xyz"
#    }
#  + route {
#      destination_cidr_block = "0.0.0.0/0"  ← CORRECT ROUTE
#      transit_gateway_id     = "tgw-abc"    ← TO INSPECTION VPC
#    }"
```

**Approval Gate:**
```bash
# Checklist before applying recovery:
# ☑ Drift confirmed (route to IGW instead of TGW)
# ☑ Actor identified (alice@paymentsteam)
# ☑ Blast radius assessed (23 ECS tasks, 50k users)
# ☑ Backup taken (route table state saved)
# ☑ Plan reviewed (only route table changes, no unrelated diffs)
# ☑ Manager approval (payments-lead confirmed)
# ☑ War room ready (ops team on standby)

# If all checked, proceed to apply
```

### Recovery Execution

**Apply Recovery:**
```bash
# Apply the recovery plan
terraform apply recovery.tfplan

# CloudTrail logs:
# "eventName": "ReplaceRoute",
# "userAgent": "Terraform/1.7.0",
# "sourceIPAddress": "203.0.113.0",  # CI/CD pipeline IP
# "requestParameters": {
#   "routeTableId": "rtb-12345abcde",
#   "destinationCidrBlock": "0.0.0.0/0",
#   "transitGatewayId": "tgw-abc"       # Correct route
# }

echo "✓ Recovery applied"
```

### Post-Recovery Validation (50-60 minutes)

**Health Checks (After Recovery):**
```bash
# 1. Verify networking restored
curl -H "Authorization: Bearer $TOKEN" \
  https://api.mbank.com/v1/health
# Response: 200 OK ✓

# 2. Verify ALB targets are healthy
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:ap-southeast-5:...
# Response: healthy_count = 23 ✓

# 3. Verify database connectivity
aws rds describe-db-instances \
  --db-instance-identifier payment-api-prod \
  --query 'DBInstances[0].[DBInstanceStatus, PendingModifiedValues]'
# Response: available, {} ✓

# 4. Verify payment processing
curl -X POST https://api.mbank.com/v1/payments \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"amount": 1.00, "currency": "MYR"}'
# Response: 200 (transaction successful) ✓

# 5. Data integrity checks
aws dynamodb query --table-name transactions \
  --key-condition-expression "timestamp > :start" \
  --expression-attribute-values '{":start":{"N":"1726948200"}}'
# Verify: Transaction count matches expected (no data loss) ✓

echo "✓ All recovery validations passed"
```

**Confirmation Messages:**
```bash
# Slack notification to team
@channel RECOVERY COMPLETE:
✓ Route table corrected (0.0.0.0/0 → TGW)
✓ Application health: 23/23 targets healthy
✓ Payments processing: 1,500+ transactions/hour flowing
✓ No data loss (transaction count verified)
✓ Recovery time: 35 minutes (target: 60 minutes)

War room ended. Stand down.
```

---

## Step 6: Root Cause Analysis (Post-Incident)

### Timeline Documentation

| Time | Event | Actor | Action |
|------|-------|-------|--------|
| **14:32:15** | Route table modified (add IGW route) | alice@paymentsteam | AWS Console / CLI |
| **14:32:30** | Config rule detected drift | AWS Config | Auto-alert triggered |
| **14:35:00** | PagerDuty alert received | ops-on-call | Incident #1234 created |
| **14:38:00** | CloudTrail forensics completed | ops-on-call | Actor identified: alice |
| **14:45:00** | Blast radius assessed | ops-on-call | 50k users impacted |
| **14:50:00** | Recovery plan created | ops-terraform | Terraform plan validated |
| **14:55:00** | Manager approval received | payments-lead | Go-ahead to apply |
| **15:02:00** | Recovery applied | ops-terraform | Route restored to TGW |
| **15:05:00** | Health checks passed | ops-on-call | All systems operational |

### Root Cause Analysis Template

**Why did this drift happen?**

```
INCIDENT: Unauthorized route table modification (IGW instead of TGW)

ROOT CAUSE ANALYSIS:

1. Immediate Cause
   - User alice had AWS console access to prod account
   - User modified route table directly (not via Terraform)
   - Modified routing violated policy (should use inspection VPC)

2. Underlying Causes
   - ☐ Accidental? (alice misunderstood routing policy)
     └─ Solution: Training on network policy
   - ☑ Lack of Guardrail? (no Config rule to prevent IGW routes)
     └─ Solution: Add Config rule "deny-direct-internet-routes"
   - ☑ Improper Access Control? (alice shouldn't have direct console access)
     └─ Solution: Require all changes via Terraform pull requests
   - ☐ Insufficient Logging? (drift not detected quickly enough)
     └─ Solution: Reduce Config rule check interval (already <5 min)

3. Contributing Factors
   - Alice is new to team (on-boarded 2 weeks ago)
   - No network policy training for junior developers
   - Console access not restricted by IAM policy
   - Change approval process not enforced by tooling

4. Lessons Learned
   - Manual changes to prod are too easy
   - Config rules are effective (detected in <5 min)
   - Need "shift-left" controls (prevent drift before it happens)
```

---

## Step 7: Prevention (Update Controls)

### Implement Prevention Controls

**Control 1: AWS Config Rule** (Prevent direct IGW routes)
```hcl
# New Config Rule: deny-direct-internet-routes
# File: org/security/config-aggregator.tf

resource "aws_config_config_rule" "deny_direct_internet_routes" {
  name = "deny-direct-internet-routes"

  source {
    owner             = "AWS"
    source_identifier = "RESTRICTED_INCOMING_TRAFFIC"
  }

  scope {
    compliance_resource_types = ["AWS::EC2::RouteTable"]
  }

  # Non-compliance = route has internet_gateway_id or nat_gateway_id
  # Remediation = remove non-compliant route
  depends_on = [aws_config_configuration_aggregator.organization]
}
```

**Control 2: IAM Permission Boundary** (Restrict console access to prod)
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyProdConsoleAccess",
      "Effect": "Deny",
      "Action": "console.aws.amazon.com/*",
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "aws:RequestedRegion": ["ap-southeast-5"],
          "aws:SourceAccount": ["123456789012-prod"]  # Prod accounts
        }
      }
    },
    {
      "Sid": "AllowTerraformChanges",
      "Effect": "Allow",
      "Action": "ec2:*",
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:username": "platform-ci"  # Only CI/CD pipeline
        }
      }
    }
  ]
}
```

**Control 3: Require Terraform Pull Requests**
```bash
# Update CODEOWNERS to require approval
# File: mbank-infra/CODEOWNERS

# Changes to network routing require 2 approvals
org/network/           @mbank/platform-team  @mbank/security-team
```

**Control 4: Automate Config Remediation**
```hcl
# Auto-remediate non-compliant routes (terraform apply)
resource "aws_config_remediation_configuration" "route_remediation" {
  config_rule_name = aws_config_config_rule.deny_direct_internet_routes.name

  automatic           = true
  maximum_automatic_attempts = 10
  automatic_attempts_after   = 60

  target_type       = "SSM_DOCUMENT"
  target_identifier = "AWS-PublishCloudFormationTemplate"
  target_version    = "1"

  # Auto-execute: terraform apply (defined in SSM document)
}
```

### Prevention Checklist

- [x] Add AWS Config rule for direct Internet routes (Control 1)
- [x] Update IAM permission boundary to deny prod console access (Control 2)
- [x] Update CODEOWNERS to require security approval for network changes (Control 3)
- [x] Enable Config auto-remediation (Control 4)
- [x] Update Terraform validation to reject non-compliant routes
- [x] Add network policy training to on-boarding checklist
- [x] Schedule monthly "drift detection" review (terraform plan run)
- [ ] Consider read-only mode for prod AWS console (future)

---

## Step 8: Post-Incident Communication

### Internal Communication

**1. Team Lead Notification (Within 1 hour)**
```bash
From: ops-on-call@mbank.com
To: alice, payments-lead@mbank.com

Subject: Post-Incident: Route Table Drift on 2026-09-21

Summary:
- WHAT: Unauthorized route table modification (IGW route added)
- WHEN: 2026-09-21 14:32:15 UTC+8
- WHO: alice@paymentsteam (accidental misconfiguration)
- IMPACT: Payment processing interrupted for 35 min, 50k users affected
- RESOLUTION: Corrected route table via Terraform (0.0.0.0/0 → TGW)

Root Cause:
- Alice attempted to route traffic directly to Internet
- Should have routed through Inspection VPC (security policy)
- Config rule detected drift in <5 min (alert triggered)

Prevention:
- Added Config rule to deny direct Internet routes
- Updated IAM to restrict prod console access
- Scheduled network policy training for team

Next Steps:
- Alice to attend network architecture training (Wed 2pm)
- Team to review Terraform change procedures
- Platform team to implement new Config rules (by Friday)
```

**2. Security Team Notification**
```bash
From: ops-on-call@mbank.com
To: security-team@mbank.com

Subject: [INCIDENT-1234] Route Table Drift - Security Summary

Classification: MEDIUM (Accidental Misconfiguration)
Severity: HIGH (50k users impacted)

Security Assessment:
- No data exfiltration (routing change only)
- No credential compromise (console access, not APi key)
- No intentional malice (user error, not attack)

Recommendations:
1. User training (alice to complete network policy training)
2. Control tightening (IAM boundary + Config rule)
3. Console access restriction (implement in 60 days)
```

**3. Customer Communication** (if applicable)
```bash
From: support@mbank.com
To: affected-customers@mbank.com

Subject: Service Restoration - Payment Processing

Dear Valued Customer,

We experienced a brief disruption to our payment processing system today
(2026-09-21, 14:32-15:05 UTC+8).

WHAT HAPPENED:
A network configuration was inadvertently modified, causing routing changes.

IMPACT:
- Duration: 33 minutes
- Affected: Payment submissions, not customer data
- No data loss or unauthorized access occurred

RESOLUTION:
- Our operations team identified and corrected the configuration
- Service fully restored at 15:05 UTC+8
- All pending transactions successfully processed

PREVENTION:
- Enhanced monitoring to detect changes within 5 minutes
- Tighter access controls to prevent manual changes
- Automated rollback procedures

We sincerely apologize for the disruption and appreciate your patience.

Questions? Contact support@mbank.com
```

---

## Step 9: Post-Incident Review Meeting (Next Day)

### Meeting Agenda

**Duration:** 1 hour  
**Attendees:** ops-on-call, alice, payments-lead, security-team, platform-team

**1. What Went Well? (10 min)**
- ✓ Drift detected in <5 minutes (Config rule worked)
- ✓ Root cause identified quickly (CloudTrail forensics)
- ✓ Team communication was clear (Slack war room)
- ✓ Recovery executed safely (Terraform plan validated)

**2. What Could Be Better? (15 min)**
- ⚠️ Alice didn't know network policy (training gap)
- ⚠️ No preventive Config rule for direct Internet routes (added)
- ⚠️ Manual console access shouldn't be possible in prod (fixing with IAM)
- ⚠️ 33 minutes of customer impact (acceptable, but preventable)

**3. Action Items (20 min)**
- [ ] alice: Complete network architecture training (by 2026-09-25)
- [ ] payments-lead: Review team's network knowledge (by 2026-09-26)
- [ ] platform-team: Deploy new Config rule (by 2026-09-24)
- [ ] security-team: Implement IAM console access restriction (by 2026-10-05)
- [ ] ops-team: Add monthly "terraform plan" drift check to calendar

**4. Documentation (10 min)**
- Update runbook with new Config rule procedures
- Update on-boarding guide with network policy training
- Create Confluence wiki with "Acceptable vs Unacceptable Routes" guide

**5. Follow-up (5 min)**
- Schedule 30-day check-in (verify prevention controls working)
- Archive incident logs (CloudTrail, Config snapshots)
- Close GitHub issue #XXXX

---

## Appendix: Quick Reference

### Emergency Contacts

| Role | Name | Slack | On-Call |
|------|------|-------|---------|
| Ops Lead | charlie@mbank.com | @charlie | +60-12-XXX-XXXX |
| Security | security-team@mbank.com | @security-oncall | +60-12-YYY-YYYY |
| Network Architect | bob@mbank.com | @bob | On-call rotation |

### Key Commands

```bash
# Detect drift
terraform plan

# Query CloudTrail
aws cloudtrail lookup-events --lookup-attributes AttributeKey=ResourceName,AttributeValue=rtb-12345

# Check Config status
aws configservice describe-compliance-by-config-rule

# Apply recovery
terraform apply recovery.tfplan

# Health check
curl https://api.mbank.com/v1/health
```

### Escalation Matrix

```
0-5 min: Acknowledge alert → On-call engineer
5-10 min: Assess drift → Escalate to ops lead (if unclear)
10-20 min: Remediation plan → Escalate to manager (if manual changes needed)
20-30 min: Recovery execution → Escalate to CTO (if cascading failures)
```

---

## References

- **Assessment Task 4:** Drift incident detection, actor identification, blast radius, recovery
- **Control Matrix:** Config rules, CloudTrail logging, SCP containment
- **Account Strategy:** Break-glass pattern, MFA enforcement
- **CloudTrail Docs:** API call forensics, log retention
- **AWS Config Docs:** Rule management, auto-remediation
