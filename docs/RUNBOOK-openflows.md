# OpenFlows Runbook

## Common Operations

### Deploy a change

Merge to `main`. ArgoCD (`argocd/application.yaml`) tracks `charts/openflows`
on `main` and syncs automatically, no manual `helm upgrade`. Check sync
status:

```bash
kubectl get application openflows -n argocd
```

### Install the chart (bootstrap only)

Only for standing up a new cluster before ArgoCD exists there, or for a
throwaway local test. Once ArgoCD is managing the release, changes go
through `main`, not this command.

```bash
helm install openflows charts/openflows -f <values-file>
```

### Render the chart without applying

```bash
helm template openflows charts/openflows -f <values-file>
```

### Scale the controller

Only applies when `controller.enabled=true` (standalone Deployment). The
default in-workspace controller is a single process in the nexus workspace
pod and isn't horizontally scaled.

```bash
kubectl scale deployment openflows-controller --replicas=2 -n openflows
```

### Rotate the Postgres password

1. Update the `openflows-postgres` Secret.
2. Restart the Coder pod so it reconnects:
   ```bash
   kubectl rollout restart deployment openflows-coder -n openflows
   ```

### Rotate the GitHub App client secret

1. Update the `openflows` Secret key `githubClientSecret`.
2. Restart the Coder pod:
   ```bash
   kubectl rollout restart deployment openflows-coder -n openflows
   ```

### Onboard a teammate with namespace-scoped cluster access

`access/rbac/openflows-namespace-admins.yaml` binds `ClusterRole/admin`,
scoped to the `openflows` namespace only, to the certificate group
`openflows-admins`. Access is granted per person via a signed client cert,
not a shared credential.

1. Apply the RoleBinding once per cluster (already live on homelab):
   ```bash
   kubectl apply -f access/rbac/openflows-namespace-admins.yaml
   ```
2. The teammate runs, from their own machine (private key never leaves it):
   ```bash
   ./access/scripts/join-openflows.sh <username>
   ```
3. A cluster admin approves the resulting CSR:
   ```bash
   kubectl certificate approve <username>-openflows
   ```
4. The teammate verifies scope:
   ```bash
   KUBECONFIG=~/.kube/homelab-<username>.yaml kubectl auth can-i --list -n openflows
   ```

## Backup & Restore

- **Redis** holds the OpenFlows SharedStore, the single source of truth for
  durable state. Back up with `redis-cli --rdb` or a snapshot of the
  appendonly file.
- **PostgreSQL** holds Coder's database. Back up with `pg_dump`.

## Monitoring & Alerts

- Coder exposes `/api/v2/buildinfo` for health.
- The controller self-heals through its error/retry poll loop; a flow error
  never kills it.
- Harness heartbeats detect stale workers (stale after 90 seconds).

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Coder pod crash-loops | GitHub App client secret empty | Set `secrets.githubClientSecret` before install |
| Controller not receiving hooks | Hook URL/secret mismatch | Check `CODER_CHAT_HOOK_URL` and `CODER_CHAT_HOOK_SECRET` |
| Workspaces not provisioning | Provisioner RBAC missing | Confirm `coder-rbac.yaml` applied |
| Postgres password changed on upgrade | Not pinned | Set `postgres.password` or `postgres.existingSecret` |

## Rollback Procedure

```bash
helm rollback openflows <revision>
```

## Escalation

If the controller or Coder is down and the flow cannot recover, check the
controller logs first:

```bash
kubectl logs deployment/openflows-controller -n openflows
```

Then the Coder logs:

```bash
kubectl logs deployment/openflows-coder -n openflows
```
