## Summary
<!-- What does this PR change? -->

## Type of change
- [ ] `org/` layer change (platform team only)
- [ ] Platform module change (platform team only)
- [ ] `applications/<team>/infra.yaml` change
- [ ] Pipeline / schema change
- [ ] Documentation

## Checklist
- [ ] `infra.yaml` validates against schema locally (`python platform/schema/validate.py applications/<team>/infra.yaml`)
- [ ] `terraform plan` output reviewed and attached below
- [ ] No `destroy` on protected resources
- [ ] Required tags present (`Environment`, `Team`, `CostCentre`, `DataClassification`)
- [ ] Change affects estimated cost — new estimate added to PR description

## Terraform Plan Output
<!-- Paste `terraform plan` summary here -->

## Risk / Rollback
<!-- How do we roll back if this breaks? -->

## AI Assistance Declaration

- [ ] No AI assistance used in this PR
- [ ] AI assistance used (GitHub Copilot)
  - What: ________________________________
  - Scope: ________________________________
  - Human review completed: [ ] Yes

**Note:** All code must be reviewed and validated regardless of AI usage. AI is a tool only.

## Compliance Checklist

- [ ] Encryption enabled for all data (at-rest and in-transit)
- [ ] CloudTrail/audit logging configured
- [ ] Multi-AZ/backup strategy defined for production
- [ ] Data classification assigned (if applicable)
- [ ] Security groups follow principle of least privilege
- [ ] No hardcoded credentials or secrets
- [ ] All changes are infrastructure-as-code (no manual resources)
