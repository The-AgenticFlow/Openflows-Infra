#!/usr/bin/env bash
# Extract the boundary and staging isolation policies from a bootstrap plan file
# into tests/rendered/ for iam_policy_tests.py. Usage: render-policies.sh <planfile>
set -euo pipefail

plan="${1:?usage: render-policies.sh <planfile>}"
out="$(dirname "$0")/rendered"
mkdir -p "$out"
json="$(terraform -chdir="$(dirname "$0")/.." show -json "$plan")"

jq -r '.resource_changes[] | select(.address == "aws_iam_policy.boundary") | .change.after.policy' <<<"$json" | jq . >"$out/boundary.json"
jq -r '.resource_changes[] | select(.address == "aws_iam_role_policy.terraform_apply_environment[\"staging\"]") | .change.after.policy' <<<"$json" | jq . >"$out/staging-environment-isolation.json"
# Apply roles hold AdministratorAccess; the boundary and isolation deny do the limiting.
jq -r '.resource_changes[] | select(.address == "aws_iam_role_policy.platform_admin_secrets") | .change.after.policy' <<<"$json" | jq . >"$out/human-secrets.json"
echo '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"*","Resource":"*"}]}' | jq . >"$out/admin.json"
echo "rendered policies into $out"
