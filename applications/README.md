# Adding Your Application

1. Create folder `applications/<your-app-name>/`
2. Create `infra.yaml` — see [infra-yaml-reference.md](../docs/infra-yaml-reference.md) for all options
3. Open a PR — CI validates schema and runs `terraform plan`
4. Review the plan diff posted to your PR
5. Get approval from your team lead + platform team
6. Merge → infrastructure is provisioned automatically

**Expected time from PR to live infrastructure: same day** (standard configs).

## Minimal infra.yaml template

```yaml
app: my-app
team: my-team
environment: prod
cost_centre: CC-1234
data_classification: internal

compute:
  type: ecs        # ecs | ec2 | eks
  cpu: 512
  memory: 1024
  desired_count: 2

tags:
  Environment: prod
  Team: my-team
  CostCentre: CC-1234
  DataClassification: internal
```
