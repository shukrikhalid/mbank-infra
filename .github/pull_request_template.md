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
