#!/usr/bin/env bash
# Fetch the permissions boundary and the AWS managed policies the cluster's roles
# use into tests/rendered/. Usage: render-policies.sh [boundary.json], default live.
set -euo pipefail

out="$(dirname "$0")/rendered"
mkdir -p "$out"
account="$(aws sts get-caller-identity --query Account --output text)"

fetch() {
  local arn="$1" file="$2" version
  version="$(aws iam get-policy --policy-arn "$arn" --query Policy.DefaultVersionId --output text)"
  aws iam get-policy-version --policy-arn "$arn" --version-id "$version" --query PolicyVersion.Document --output json >"$out/$file"
}

if [ -n "${1:-}" ]; then
  cp "$1" "$out/boundary.json"
else
  fetch "arn:aws:iam::${account}:policy/openflows/openflows-permissions-boundary" boundary.json
fi
fetch "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy" cni.json
fetch "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy" ebs-csi.json
cp "$(dirname "$0")/../policies/aws-load-balancer-controller.json" "$out/aws-load-balancer-controller.json"
# The same template Terraform renders, with a stand-in zone the cases refer to.
sed 's#${zone_arn}#arn:aws:route53:::hostedzone/Z0ENVIRONMENTZONE#' "$(dirname "$0")/../policies/external-dns.json.tftpl" >"$out/external-dns.json"
echo "rendered policies into $out"
