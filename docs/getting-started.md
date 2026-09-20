# Getting Started — App Team Onboarding

## Pre-requisites
- Access to the `mbank-infra` repo
- Your team folder already exists under `applications/<team>/`
- Platform team has provisioned your AWS account via AFT

## Steps

1. **Clone the repo**
   ```bash
   git clone git@github.com:mbank/mbank-infra.git
   cd mbank-infra
   ```

2. **Create a branch**
   ```bash
   git checkout -b feat/add-<app-name>-infra
   ```

3. **Edit `applications/<team>/infra.yaml`**
   See [infra-yaml-reference.md](infra-yaml-reference.md) for all available fields.

4. **Validate locally**
   ```bash
   python platform/schema/validate.py applications/<team>/infra.yaml
   ```

5. **Open a PR** — CI validates schema, runs `terraform plan`, and posts the diff.

6. **Get approvals**: your team lead + platform team (@mbank/platform-team).

7. **Merge** — infrastructure is applied automatically.
