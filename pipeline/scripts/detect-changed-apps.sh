#!/usr/bin/env bash
# Task 13 — Application Change Detector
# Detects which applications have changed their infra.yaml in this branch.
# Usage: detect-changed-apps.sh [base_branch]
#
# Outputs newline-separated list of app names (payment, customertech, etc.)
# Exit code 0 if changes detected, 1 if no changes.
# Safe for use in GitHub Actions matrix strategy.
set -euo pipefail

BASE_BRANCH="${1:-origin/main}"

# Find all changed files in applications/*/infra.yaml
changed_apps=$(git diff --name-only "${BASE_BRANCH}...HEAD" 2>/dev/null || echo "")

if [ -z "${changed_apps}" ]; then
    echo "INFO: No changes detected" >&2
    exit 1
fi

# Extract unique app names
echo "${changed_apps}" \
  | grep -E '^applications/[a-z-]+/infra\.yaml$' \
  | awk -F'/' '{print $2}' \
  | sort -u

exit 0
