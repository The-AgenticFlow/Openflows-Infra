#!/usr/bin/env bash
# Reach a private OpenFlows EKS API from a laptop: forward localhost:<port> to the
# endpoint through the SSM-managed admin tunnel and point a kubeconfig context at it.
# Usage: scripts/kube-tunnel.sh <staging|production> [local-port]
set -euo pipefail

env="${1:?usage: kube-tunnel.sh <staging|production> [local-port]}"
port="${2:-8443}"
cluster="openflows-${env}"
region="${AWS_REGION:-eu-west-1}"

host="$(aws eks describe-cluster --name "$cluster" --region "$region" --query cluster.endpoint --output text)"
host="${host#https://}"
instance="$(aws ec2 describe-instances --region "$region" \
  --filters "Name=tag:Name,Values=${cluster}-admin-tunnel" Name=instance-state-name,Values=running \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)"
if [ "$instance" = "None" ]; then
  echo "no running ${cluster}-admin-tunnel instance" >&2
  exit 1
fi

# A separate cluster entry, so direct contexts keep the real endpoint. The API
# certificate names the real host, so kubectl verifies against it, not localhost.
account="$(aws sts get-caller-identity --query Account --output text)"
arn="arn:aws:eks:${region}:${account}:cluster/${cluster}"
aws eks update-kubeconfig --name "$cluster" --region "$region" >/dev/null
ca="$(mktemp)"
trap 'rm -f "$ca"' EXIT
aws eks describe-cluster --name "$cluster" --region "$region" --query cluster.certificateAuthority.data --output text | base64 -d >"$ca"
kubectl config set-cluster "${cluster}-tunnel" --server "https://localhost:${port}" \
  --tls-server-name "$host" --certificate-authority "$ca" --embed-certs >/dev/null
kubectl config set-context "${cluster}-tunnel" --cluster "${cluster}-tunnel" --user "$arn" >/dev/null
# update-kubeconfig switched to the direct (unreachable) context; use the tunnel instead.
kubectl config use-context "${cluster}-tunnel" >/dev/null
echo "kubectl now uses ${cluster}-tunnel -> https://localhost:${port}; keep this running"

aws ssm start-session --region "$region" --target "$instance" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "host=${host},portNumber=443,localPortNumber=${port}"
