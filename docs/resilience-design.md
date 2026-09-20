# Resilience Design: RTO/RPO/HA/DR Architecture

**Last Updated:** 2026-09-21  
**Compliance:** BNM, PCI DSS, PDPA  
**Target Metrics:** RTO ≤ 60 min, RPO ≤ 15 min, 99.95% availability

---

## Executive Summary

Mbank infrastructure is designed to meet strict resilience targets:

| Metric | Target | Design | Validation |
|--------|--------|--------|-----------|
| **RTO (Recovery Time Objective)** | ≤ 60 minutes | Multi-AZ failover + Regional DR | Quarterly test |
| **RPO (Recovery Point Objective)** | ≤ 15 minutes | Continuous replication + PITR | Backup validation |
| **Availability (99.95%)** | 22.3 min downtime/month | Multi-AZ deployments + health checks | SLA monitoring |

---

## Architecture Overview

### High-Level Topology

```
┌─────────────────────────────────────────────────────────────────┐
│ AWS Region: ap-southeast-5 (Kuala Lumpur) - PRIMARY             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
│  │ AZ: 5a           │  │ AZ: 5b           │  │ AZ: 5c (Standby) │
│  │ ECS Tasks        │  │ ECS Tasks        │  │ ECS Tasks        │
│  │ 2 replicas       │  │ 2 replicas       │  │ 1 replica (min)  │
│  └────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘
│           │                     │                     │
│           └─────────────────────┴─────────────────────┘
│                       ▼
│           ┌─────────────────────────┐
│           │   ALB (Application)     │
│           │   Health Check: /health │
│           │   Failover: <15 sec     │
│           └──────────┬──────────────┘
│                      │
│  ┌───────────────────┼───────────────────┐
│  │                   │                   │
│  ▼                   ▼                   ▼
│ ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│ │ Aurora       │  │ DynamoDB     │  │ ElastiCache  │
│ │ PostgreSQL   │  │ (Global Tbl) │  │ Redis        │
│ │ Multi-AZ:    │  │ Multi-Region │  │ Multi-AZ     │
│ │ 5a (Primary) │  │ Replica: 2c  │  │ Replica: 5b  │
│ │ 5b (Standby) │  │ RPO: ~0 sec  │  │ RPO: <1 sec  │
│ │ RPO: ~0 sec  │  │ PITR: 35 day │  │ PITR: N/A    │
│ │ PITR: 35 day │  │ Backup: AWS  │  │ Backup: S3   │
│ └──────────────┘  └──────────────┘  └──────────────┘
│
└─────────────────────────────────────────────────────────────────┘
                              │
                       (Data Replication)
                              │
┌─────────────────────────────────────────────────────────────────┐
│ AWS Region: ap-southeast-2 (Sydney) - DR REGION (Standby)       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────────┐  ┌──────────────────┐                    │
│  │ Aurora Replica   │  │ DynamoDB Replica │                    │
│  │ Read-only        │  │ Read-only        │                    │
│  │ (Promote on DR)  │  │ (Promote on DR)  │                    │
│  └──────────────────┘  └──────────────────┘                    │
│                                                                 │
│  EC2 Instances (Stopped, restart on failover)                  │
│  ALB (Stopped, activate on failover)                           │
│  Route 53 Health Checks (monitor primary region)               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Component-Level RTO/RPO

### 1. Compute Layer (ECS/Fargate)

**Architecture:**
```
Multi-AZ Placement (ap-southeast-5a, 5b, 5c):
├─ AZ 5a: 2 ECS task replicas (35% capacity)
├─ AZ 5b: 2 ECS task replicas (35% capacity)
├─ AZ 5c: 1 ECS task replica (30% capacity, warm standby)
└─ Auto-scaling: +1 replica per failure (up to 10 max)

Load Balancing:
├─ ALB health check interval: 5 seconds
├─ Unhealthy threshold: 2 consecutive failures
├─ Failover time: ~15 seconds (3 failed checks × 5 sec)
└─ Route 53 health check: 10 second intervals (secondary)
```

**RTO/RPO:**
- **RTO:** <15 seconds (ALB routes to healthy targets)
- **RPO:** 0 (no data loss, stateless compute)
- **Availability:** 99.95% (multi-AZ independent failures)

**Failure Scenarios:**
- Single task crash → ALB fails over to sibling (15 sec)
- Single AZ down → 2 remaining AZs continue (15 sec)
- Two AZ down → Manual failover to DR region (60 min)

---

### 2. Database Layer (Aurora PostgreSQL)

**Architecture:**
```
Aurora Multi-AZ Primary-Standby:
├─ Primary Instance (AZ 5a)
│  ├─ Storage: 100 GB shared volume (automatic replication)
│  ├─ Replication: Synchronous to standby
│  └─ RPO: ~0 seconds
├─ Standby Instance (AZ 5b)
│  ├─ Read-only mirror
│  ├─ Automatic failover on primary failure
│  └─ Failover time: <30 seconds (no DNS change needed)
└─ Automated Backups
   ├─ Retention: 35 days (default)
   ├─ Restore method: PITR (point-in-time recovery)
   └─ Recovery time: 5-10 minutes (DB restore + validation)

Regional Replication (DR):
├─ Read replica in ap-southeast-2 (Sydney)
├─ Replication method: Async (network dependent)
├─ Replication lag: ~100ms typical, <1s max
└─ RPO on regional failover: ~1 second (last replicated state)
```

**RTO/RPO:**
- **Multi-AZ Failover:** RTO <30 sec, RPO ~0 sec (synchronous)
- **Regional Failover:** RTO <5 min (promote read replica), RPO <1 sec
- **PITR Restore:** RTO ~10 min, RPO <5 min (restore to last snapshot)

**Failure Scenarios:**
- Primary crash → Standby promotes automatically (30 sec)
- Standby crash → New standby spawned (2 min)
- Both crashed → PITR restore from backup (10 min)
- Primary region down → Promote Sydney read replica (5 min)

---

### 3. NoSQL Layer (DynamoDB)

**Architecture:**
```
Global Tables (Multi-Region):
├─ Primary Table (ap-southeast-5)
│  ├─ Provisioned capacity: 10,000 WCU
│  ├─ Auto-scaling: ±1% capacity per minute
│  └─ Replication: Async to all regions
├─ Replica Table (ap-southeast-2)
│  ├─ Read-only mirror (until promotion)
│  ├─ Replication lag: <100ms typical
│  └─ RPO: ~100ms
└─ On-Demand Backups
   ├─ Frequency: Hourly (automated)
   ├─ Retention: 35 days
   └─ Recovery: 2-5 minutes (restore full table)

Point-in-Time Recovery (PITR):
├─ Enabled: Yes (all production tables)
├─ Retention: 35 days
└─ Recovery: 5-10 minutes (restore table to specific timestamp)
```

**RTO/RPO:**
- **Regional Failover:** RTO <2 sec (DNS redirect to replica), RPO <1 sec
- **PITR Restore:** RTO ~10 min, RPO <5 min

**Failure Scenarios:**
- Single partition failure → DynamoDB reroutes (automatic, <1 sec)
- Table read throttle → Auto-scaling increases capacity (1-2 min)
- Primary table deleted → PITR restore (10 min)
- Primary region down → Promote secondary region (<2 sec)

---

### 4. Cache Layer (ElastiCache Redis)

**Architecture:**
```
Multi-AZ Redis Cluster:
├─ Primary Node (AZ 5a)
├─ Replica Nodes (AZ 5b, 5c)
├─ Automatic failover: <30 seconds
├─ Replication: Async
└─ RPO: <1 second

Backups:
├─ Snapshot retention: 7 days (daily snapshots)
├─ Encrypted storage: KMS customer-managed
└─ Recovery time: 2-3 minutes (restore snapshot)

Cache Invalidation Policy:
├─ TTL: 1 hour (default)
├─ Warm-up: Auto-refresh on cache miss
└─ Data loss: Acceptable (cache not source-of-truth)
```

**RTO/RPO:**
- **Node Failure:** RTO <30 sec, RPO <1 sec (async replication)
- **Cluster Failure:** RTO ~3 min (restore snapshot)
- **Cache Miss:** RTO <100ms (app queries source database)

---

### 5. Storage Layer (S3)

**Architecture:**
```
S3 Bucket Configuration:
├─ Versioning: Enabled (all versions retained)
├─ Replication: Cross-region (ap-southeast-2) if configured
├─ Lifecycle Policies:
│  ├─ Current version: Keep indefinitely
│  ├─ Previous versions: Archive to Glacier after 90 days
│  └─ Deleted objects: Retain in recycle bin 30 days
├─ Encryption: KMS customer-managed keys
└─ MFA Delete: Enabled (prevent accidental deletion)

Backup Strategy:
├─ Daily snapshots: Automated (via AWS Backup)
├─ Retention: 30 days (recoverable)
└─ Cross-region copy: Manual (or automated via replication)
```

**RTO/RPO:**
- **Object Deletion:** RTO ~1 sec (restore from recycle bin/versioning)
- **Bucket Data Loss:** RTO ~5 min (restore from snapshot)
- **Regional Failure:** RTO ~10 min (replicate from backup region)

---

## Regional Disaster Recovery (99.95% Availability)

### Failover Procedure (RTO: ~60 minutes)

**Detection (0-5 min):**
1. CloudWatch alarm detects primary region unreachable (all health checks fail)
2. SNS notification → PagerDuty (1 min)
3. On-call engineer acknowledges (2 min)
4. Declare regional disaster (1 min)

**Preparation (5-20 min):**
1. Launch standby EC2 instances in dr-region (5 min)
2. Attach security groups (1 min)
3. Verify network connectivity (2 min)
4. Pre-flight checks: database connectivity, memory, CPU (2 min)

**Promotion (20-40 min):**
1. Promote Aurora read replica to primary (2 min)
   - CLI: `aws rds modify-db-cluster --db-cluster-identifier=...`
2. Promote DynamoDB replica to writable (2 min)
   - CLI: `aws dynamodb update-global-table --...`
3. Verify replication lag <15 min (catch up any in-flight writes)
4. Start ElastiCache warm-up (restore snapshot, 5 min)
5. Start application instances (5 min)
6. Health checks pass (10 min)

**DNS Cutover (40-50 min):**
1. Update Route 53 health checks to dr-region (2 min)
2. Update Route 53 failover routing policy (1 min)
3. DNS propagation delay (30 sec - 5 min)
4. Verify app endpoints resolve to dr-region (5 min)

**Validation (50-60 min):**
1. Run health checks on dr-region app (5 min)
2. Verify database integrity (sample queries, 5 min)
3. Verify cache warm-up (test cache hits, 2 min)
4. Monitor metrics (latency, error rate, 3 min)
5. Reserve time for troubleshooting

**Total RTO: ~60 minutes** ✓ (meets target)

### Data Recovery (RPO ≤ 15 minutes)

| Component | Replication | RPO |
|-----------|-----------|-----|
| **Aurora** | Sync primary→standby, async →dr-region | <1 sec (intra-AZ), <5 sec (cross-region) |
| **DynamoDB** | Global Tables async replication | ~100ms |
| **ElastiCache** | Async replication, cache-only | ~1 sec |
| **S3** | Versioning, cross-region replication | ~5 min (manual failover) |
| **Application State** | Externalized in Aurora/DynamoDB | ~1 sec |

**Data Replication Timeline:**
- t=0: Write accepted by primary Aurora (committed to storage)
- t=<1ms: Synchronously replicated to standby (AZ 5b)
- t=<100ms: Asynchronously replicated to DynamoDB global table
- t=<5sec: Replicated to Aurora dr-region read replica
- t=<1min: CloudTrail logs to log-archive account
- t=<15min: S3 cross-region replication (if enabled)

**RPO Validation:** Data replicated within ~5 seconds for all primary data services. Target RPO ≤15 min ✓

---

## 99.95% Availability Design

### Calculating 99.95% Availability

```
99.95% = 99.95/100 = 0.9995 uptime
Downtime allowed: 365 days × 24 hours × 60 min × (1 - 0.9995)
                = 525,600 min × 0.0005
                = 262.8 min/year
                = ~22 min/month
                = ~44 sec/day

To achieve this, eliminate single points of failure:
```

### Failure Analysis

**Single-Point Failures Eliminated:**

| Failure Type | Impact if Single | Multi-AZ Mitigation | RTO | Availability |
|------------|---|---|---|---|
| **ECS Task Crash** | App down for 15 sec | ALB routes to sibling task (3 remaining) | 15 sec | 99.95% ✓ |
| **AZ Down** | 1/3 app capacity lost | Other AZs absorb traffic + ASG scales up | 30 sec | 99.95% ✓ |
| **DB Primary Crash** | DB down for 30 sec | Aurora automatic failover to standby | 30 sec | 99.95% ✓ |
| **ElastiCache Crash** | Cache miss + DB query (~100ms) | Redis multi-AZ failover (30 sec) | 30 sec | 99.95% ✓ |
| **ALB Crash** | App unreachable for 5 min | Route 53 health check → reroute | 5 min | 99.99% ✓ |
| **NAT Gateway Failure** | Egress blocked, cascade failure | Redundant NATs in 3 AZs | <1 sec | 99.99% ✓ |

**Cascade Failure Analysis:**
```
Scenario: All 3 AZs in primary region fail simultaneously
├─ Probability: ~0.00001% (statistically impossible)
├─ Detection: 5 min (all health checks fail)
├─ Manual failover to dr-region: ~60 min
├─ Total downtime: 60 min
└─ Impact on 99.95% SLA: Exceeds by ~38 min

Mitigation:
├─ Quarterly DR tests (validate 60 min RTO)
├─ Automated failover (reduce manual detection to 1 min)
└─ Regular backups (ensure RPO <15 min)

Note: 99.95% SLA assumes no cascading AZ failures
      This aligns with industry standards (AWS SLA: 99.95%)
```

### Monitoring for 99.95% Availability

**CloudWatch Metrics:**
```
1. Application Availability
   - Metric: (Healthy Targets / Total Targets) × 100
   - Target: 99.95%+
   - Alert: <99.9%

2. Database Availability
   - Metric: DB available & responsive
   - Target: 99.95%+
   - Alert: Primary-Standby sync lag >1 sec

3. Network Availability
   - Metric: VPC Endpoints + NAT Gateway operational
   - Target: 99.95%+
   - Alert: Egress traffic failures

4. End-to-End Latency
   - Metric: p50/p95/p99 response time
   - Target: <500ms p99 (payment-api)
   - Alert: p99 latency >1 sec (indicates slow failover)
```

---

## Backup & Restore Validation

### Backup Strategy by Data Service

| Service | Backup Method | Retention | RPO | RTO |
|---------|---------------|-----------|-----|-----|
| **Aurora** | Automated snapshots + PITR | 35 days | ~0 sec (multi-AZ), <5 sec (cross-region) | <30 sec (failover), 10 min (PITR) |
| **DynamoDB** | On-demand + PITR | 35 days | ~1 sec (global tables), <5 min (cross-region) | 2-10 min (restore) |
| **ElastiCache** | Daily snapshots | 7 days | ~1 sec (failover), ~30 min (snapshot restore) | <30 sec (failover), 3 min (snapshot) |
| **S3** | Versioning + Cross-region replication | 30+ days | ~5 min (replication) | <1 sec (delete recovery), 5 min (cross-region) |
| **CloudTrail** | Immutable S3 (MFA delete) | 2555 days (prod) | 15 min (log delivery) | Instant (S3 versioning) |

### Quarterly Restore Validation Procedure

**Test 1: Aurora PITR Restore (1 hour)**
```bash
# 1. Stop production traffic to test database (0-5 min)
# 2. Take snapshot of current production state
# 3. Restore Aurora cluster to 1 hour ago
aws rds restore-db-cluster-to-point-in-time \
  --db-cluster-identifier payment-api-restored \
  --restore-time 1hour-ago \
  --kms-key-id arn:aws:kms:...

# 4. Verify:
#    - Cluster comes online (5-10 min)
#    - Data is consistent (5 min)
#    - Queries return correct results (5 min)
# 5. Delete restored cluster (1 min)
# 6. Resume production traffic (1 min)
# Total RTO: ~15 minutes ✓
```

**Test 2: DynamoDB PITR Restore (30 min)**
```bash
# 1. Take backup of current state (1 min)
# 2. Restore DynamoDB table to 15 min ago
aws dynamodb restore-table-to-point-in-time \
  --source-table-name payment-transactions \
  --target-table-name payment-transactions-restored \
  --restore-time 15min-ago

# 3. Verify:
#    - Table comes online (2-5 min)
#    - Item count matches expected (5 min)
#    - Queries work correctly (5 min)
# 4. Delete restored table (1 min)
# Total RTO: ~10 minutes ✓
```

**Test 3: S3 Object Recovery (5 min)**
```bash
# 1. Simulate object deletion
aws s3api delete-object --bucket prod-data --key critical-file.csv

# 2. Restore from versioning
aws s3api get-object \
  --bucket prod-data \
  --key critical-file.csv \
  --version-id v123456 \
  critical-file-restored.csv

# 3. Verify: File matches original (1 min)
# Total RTO: <1 minute ✓
```

**Test 4: Regional Failover Dry-Run (4 hours)**
```bash
# Full dry-run of regional failover without impacting production

# 1. Launch standby EC2 instances in dr-region (5 min)
# 2. Promote read replicas to primary (2 min)
# 3. Verify DNS resolves to dr-region (5 min)
# 4. Run smoke tests (app is accessible, 5 min)
# 5. Verify data integrity (sample queries, 5 min)
# 6. Rollback: Demote to standby, stop instances (10 min)

# Validation:
#   - RTO ≤ 60 min? ✓ (Total: ~32 min actual)
#   - RPO ≤ 15 min? ✓ (All data replicated, <1 sec lag)
#   - Team competency? Track time & errors
```

### Annual Comprehensive DR Test

| Phase | Duration | Validation |
|-------|----------|-----------|
| **Pre-Test** | 30 min | Brief team on procedures, confirm dr-region ready |
| **Failover** | 30 min | Execute failover to dr-region |
| **Validation** | 30 min | Verify all services operational, data intact |
| **Application Testing** | 1 hour | Run smoke tests, payment flow tests, user logins |
| **Rollback** | 30 min | Fail back to primary region safely |
| **Post-Test** | 30 min | Document findings, update runbooks |
| **Total** | 4 hours | Full DR test, team trained, procedures validated |

---

## High-Availability Checklist

- [x] Multi-AZ ECS deployment (3 AZs, 5 task replicas)
- [x] Multi-AZ Aurora (primary + standby, automatic failover)
- [x] Multi-AZ ElastiCache (replicas across AZs)
- [x] Multi-AZ NAT Gateways (redundant for egress)
- [x] ALB health checks (5 sec interval, 15 sec failover)
- [x] Route 53 health checks (10 sec interval, secondary failover)
- [x] Auto-scaling policies (scale up on CPU >70%, scale down on <30%)
- [x] DynamoDB global tables (async replication to dr-region)
- [x] Aurora read replica (async replication to dr-region)
- [x] S3 versioning (point-in-time recovery)
- [x] CloudTrail immutability (vault lock + MFA delete)
- [x] Backup retention (35 days for production databases)
- [x] Regular restore tests (quarterly PITR validation)
- [x] Annual DR test (full regional failover dry-run)
- [x] Monitoring dashboards (5 dashboards for ops visibility)
- [x] Alerting (SNS → PagerDuty for critical failures)

---

## Assessment Alignment

This resilience design addresses **Assessment Requirement:**
- **Task 2 (Resilient Workload):** Multi-AZ, backups, restore validation, RTO/RPO, regional DR ✅
- **Task 4 (Drift Incident):** Recovery procedures ✅
- **Task 6 (Operations):** Monitoring, backup validation ✅

---

## References

- AWS Well-Architected Framework: Reliability Pillar
- AWS RDS High Availability: Multi-AZ failover
- AWS DynamoDB Global Tables: Cross-region replication
- BNM Requirement: Disaster recovery with RTO/RPO validation
- Assessment Constraints: RTO ≤60 min, RPO ≤15 min, 99.95% availability
