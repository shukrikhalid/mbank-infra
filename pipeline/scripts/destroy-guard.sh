#!/usr/bin/env bash
# Task 13 — Destroy Guard
# Prevents accidental destruction of critical infrastructure resources.
# Parses Terraform plan JSON and blocks destroys of protected resource types.
#
# Usage: destroy-guard.sh <plan.tfplan.json>
# Exit codes:
#   0 = no protected resources being destroyed
#   1 = protected resources would be destroyed (plan blocked)
set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: destroy-guard.sh <plan.tfplan.json>" >&2
    exit 1
fi

PLAN_FILE="$1"

if [ ! -f "${PLAN_FILE}" ]; then
    echo "ERROR: Plan file not found: ${PLAN_FILE}" >&2
    exit 1
fi

# Protected resource types that MUST NOT be deleted
declare -a PROTECTED_RESOURCES=(
    "aws_rds_cluster"
    "aws_rds_cluster_instance"
    "aws_dynamodb_table"
    "aws_s3_bucket"
    "aws_kms_key"
    "aws_vpc"
    "aws_secretsmanager_secret"
    "aws_backup_vault"
)

# Check if jq is available
if ! command -v jq &> /dev/null; then
    echo "ERROR: jq is required but not installed" >&2
    exit 1
fi

# Convert tfplan to JSON
plan_json=$(terraform show -json "${PLAN_FILE}" 2>/dev/null || echo "{}")

if [ "${plan_json}" = "{}" ]; then
    echo "ERROR: Could not parse Terraform plan" >&2
    exit 1
fi

# Check for deletions of protected resources
errors=""

for resource_type in "${PROTECTED_RESOURCES[@]}"; do
    # Query the plan JSON for resources of this type being deleted
    delete_count=$(echo "${plan_json}" | jq --arg rt "${resource_type}" \
        '[.resource_changes[]? | select(.type == $rt and (.change.actions | index("delete") != null))] | length' \
        2>/dev/null || echo 0)
    
    if [ "${delete_count}" -gt 0 ]; then
        deleted_resources=$(echo "${plan_json}" | jq -r --arg rt "${resource_type}" \
            '[.resource_changes[]? | select(.type == $rt and (.change.actions | index("delete") != null)) | .address] | join(", ")' \
            2>/dev/null || echo "${resource_type}")
        errors="${errors}\n  ✗ ${resource_type}: ${deleted_resources} (${delete_count} resource(s))"
    fi
done

if [ -n "${errors}" ]; then
    echo "ERROR: Plan contains deletions of protected resources:" >&2
    echo -e "${errors}" >&2
    echo >&2
    echo "Protected resources cannot be destroyed without explicit approval." >&2
    echo "If this is intentional, contact the platform team." >&2
    exit 1
fi

echo "✓ destroy-guard: no protected resource deletions detected"
