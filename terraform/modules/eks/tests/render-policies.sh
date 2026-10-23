#!/usr/bin/env bash
# Fetch the live permissions boundary and the AWS managed policies the cluster's
# roles use into tests/rendered/ for iam_policy_tests.py. Needs read access to IAM.
set -euo pipefail

out="$(dirname "$0")/rendered"
mkdir -p "$out"
account="$(aws sts get-caller-identity --query Account --output text)"

fetch() {
  local arn="$1" file="$2" version
  version="$(aws iam get-policy --policy-arn "$arn" --query Policy.DefaultVersionId --output text)"
  aws iam get-policy-version --policy-arn "$arn" --version-id "$version" --query PolicyVersion.Document --output json >"$out/$file"
}

fetch "arn:aws:iam::${account}:policy/openflows/openflows-permissions-boundary" boundary.json
fetch "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy" cni.json
fetch "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy" ebs-csi.json
cp "$(dirname "$0")/../policies/aws-load-balancer-controller.json" "$out/aws-load-balancer-controller.json"
echo "rendered policies into $out"
