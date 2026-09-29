# ADR-0002: Secrets stay as in-cluster Secret objects, no external backend

Status: accepted

## Context

This cluster has no External Secrets Operator and no cloud secret manager
(no AWS account tied to it). Every other production-affecting repo in this
organization's wider ecosystem routes secrets through
`AWS Secrets Manager -> External Secrets Operator -> Kubernetes Secret`,
but that chain doesn't exist here, and standing it up (an AWS account, ESO
install, IAM wiring) is out of scope for getting this deployment onto
GitOps.

Separately, the chart's `existingSecret` / `postgres.existingSecret`
override was found to be broken, every consumer hardcoded the chart-default
Secret name instead of respecting the override, so setting it broke the
deployment. See the chart's git history for the fix.

## Decision

Secrets are plain Kubernetes `Secret` objects living in the `openflows`
namespace, created once, referenced by the ArgoCD `Application`'s Helm
values via `existingSecret: openflows` / `postgres.existingSecret:
openflows-postgres`. No secret value is ever committed to git, the
`Application` manifest only contains the Secret's name, not its contents.

## Consequences

- No automatic rotation, expiry, or audit trail beyond what `kubectl`
  access logging provides. Rotating a secret is a manual `kubectl` edit
  followed by a manual pod restart (Secret changes don't trigger the
  `checksum/config` auto-restart, that only watches the ConfigMap).
- Anyone with `get secret` permission in the `openflows` namespace (see
  `access/rbac/openflows-namespace-admins.yaml`) can read every secret
  value in plaintext. Namespace-scoped RBAC is the only boundary.
- If this cluster ever gets an External Secrets Operator and a cloud secret
  backend, this decision should be revisited, `existingSecret` already
  points at a Secret by name, so migrating the Secret's source (an
  `ExternalSecret` producing it instead of a one-time `kubectl create`)
  wouldn't require a chart change.
