#!/usr/bin/env bash
# Join the homelab cluster with namespace-scoped admin over `openflows`.
#
# The private key is generated on YOUR machine and never leaves it. The cluster
# CA is not reachable from the admin side, so you cannot self-sign: you create
# a CertificateSigningRequest, a cluster admin approves it, and the apiserver
# signs it. Access comes from the certificate group O=openflows-admins.
#
# Usage:  ./join-openflows.sh <username>
#   e.g.  ./join-openflows.sh christian
set -euo pipefail

USERNAME="${1:?usage: $0 <username>}"
GROUP="openflows-admins"
NAMESPACE="openflows"
API="https://192.168.1.251:6443"
OUT="${HOME}/.kube/homelab-${USERNAME}.yaml"

command -v openssl >/dev/null || { echo "openssl required" >&2; exit 1; }
command -v kubectl  >/dev/null || { echo "kubectl required" >&2; exit 1; }
mkdir -p "$(dirname "$OUT")"
chmod 700 "$(dirname "$OUT")"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
KEY="$WORK/${USERNAME}.key"

echo "==> Generating private key for CN=${USERNAME}, O=${GROUP}"
openssl genrsa -out "$KEY" 2048 2>/dev/null
chmod 600 "$KEY"

echo "==> Creating CertificateSigningRequest"
# CN becomes the username, each O becomes a group. Do not add extra O entries:
# access is granted purely by the openflows-admins group.
openssl req -new -key "$KEY" -out "$WORK/req.csr" \
  -subj "/CN=${USERNAME}/O=${GROUP}"

cat > "$WORK/csr.yaml" <<EOF
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: ${USERNAME}-openflows
spec:
  signerName: kubernetes.io/kube-apiserver-client
  request: $(base64 -w0 < "$WORK/req.csr")
  usages: [client auth, digital signature, key encipherment]
EOF

kubectl create -f "$WORK/csr.yaml"
CSR="${USERNAME}-openflows"

echo
echo "==> Waiting for a cluster admin to approve the request."
echo "    Admin runs:  kubectl certificate approve ${CSR}"
echo
until kubectl get csr "$CSR" -o jsonpath='{.status.conditions[?(@.type=="Approved")].status}' 2>/dev/null | grep -q True; do
  if kubectl get csr "$CSR" -o jsonpath='{.status.conditions[?(@.type=="Denied")].status}' 2>/dev/null | grep -q True; then
    echo "!! request was denied" >&2; exit 1
  fi
  sleep 3
done
echo "==> Approved. Fetching signed certificate."

kubectl get csr "$CSR" -o jsonpath='{.status.certificate}' | base64 -d > "$WORK/cert.pem"

echo "==> Verifying identity encoded in the signed certificate:"
openssl x509 -in "$WORK/cert.pem" -noout -subject

# Pull the CA from the live cluster so the kubeconfig can verify the server.
kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' \
  | base64 -d > "$WORK/ca.crt"

cat > "$OUT" <<EOF
apiVersion: v1
kind: Config
clusters:
  - name: homelab
    cluster:
      server: ${API}
      certificate-authority-data: $(base64 -w0 < "$WORK/ca.crt")
users:
  - name: ${USERNAME}
    user:
      client-certificate-data: $(base64 -w0 < "$WORK/cert.pem")
      client-key-data: $(base64 -w0 < "$KEY")
contexts:
  - name: ${USERNAME}@homelab
    context:
      cluster: homelab
      user: ${USERNAME}
      namespace: ${NAMESPACE}
current-context: ${USERNAME}@homelab
EOF

chmod 600 "$OUT"
echo
echo "==> Wrote ${OUT}"
echo "    Test with:  KUBECONFIG=${OUT} kubectl auth whoami"
echo "    Expected:   username=${USERNAME}, group=${GROUP}"
echo "    Also verify scope:  KUBECONFIG=${OUT} kubectl auth can-i --list -n ${NAMESPACE}"
