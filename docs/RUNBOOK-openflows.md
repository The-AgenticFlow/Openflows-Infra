# OpenFlows Runbook

## Access

OpenFlows (the Coder UI, its only web interface) is reachable at
`openflows.int` through the cluster's shared `ingress-nginx` controller
(`192.168.1.200`), not a dedicated LoadBalancer IP. `.int` is used instead of
a real domain because this is enterprise-internal only, resolved purely via
`/etc/hosts`, no public DNS. Add this to `/etc/hosts` on any machine that
needs to reach it:

```
192.168.1.200  openflows.int
```

## Common Operations

### Deploy a change

Merge to `main`. ArgoCD (`argocd/application.yaml`) tracks `charts/openflows`
on `main` and syncs automatically, no manual `helm upgrade`. Check sync
status:

```bash
kubectl get application openflows -n argocd
```

ArgoCD polls every ~120 seconds. To sync immediately instead of waiting:

```bash
kubectl patch application openflows -n argocd --type merge \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
```

A ConfigMap-only change (e.g. `coder.accessUrl`) auto-restarts the Coder pod
via a `checksum/config` annotation, no manual step needed. A Secret change
(rotating `githubClientSecret`, etc.) does not auto-restart, see the rotate
procedures below.

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
- ArgoCD Application health/sync status is the deployment-level signal:
  ```bash
  kubectl get application openflows -n argocd
  ```
  `Synced`/`Healthy` is normal. `OutOfSync` persisting past one poll cycle
  (~120s) or a `ComparisonError` condition means ArgoCD can't reconcile,
  see Troubleshooting below.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Coder pod crash-loops | GitHub App client secret empty | Set `secrets.githubClientSecret` before install |
| Controller not receiving hooks | Hook URL/secret mismatch | Check `CODER_CHAT_HOOK_URL` and `CODER_CHAT_HOOK_SECRET` |
| Workspaces not provisioning | Provisioner RBAC missing | Confirm `coder-rbac.yaml` applied |
| Postgres password changed on upgrade | Not pinned | Set `postgres.password` or `postgres.existingSecret` |
| Ingress returns `308` redirect to `https://` | `ssl-redirect` not disabled, no TLS cert exists | Confirm `nginx.ingress.kubernetes.io/ssl-redirect: "false"` and `tls.enabled: false` in the Application's values |
| GitHub external auth fails (`redirect_uri mismatch`) after an `accessUrl`/hostname change | GitHub App's Callback URL still points at the old hostname | Update the Callback URL in the GitHub App settings to `{accessUrl}/external-auth/primary-github/callback` |
| ArgoCD `Application` shows `ComparisonError` / `repo-server` is `CrashLoopBackOff`, briefly, right after a cluster or network outage | Transient CNI/DNS reconvergence while the cluster settles | Wait 2-5 minutes, then hard-refresh (see Deploy a change); if it persists past that, check `kubectl logs deploy/argocd-repo-server -n argocd` for a real error |
| A workspace pod is stuck logging `error: failed to download coder agent`, retrying every 30s, after a pod restart | Its startup script has the old `coder.accessUrl` baked in from its last Coder build, see the accessUrl limitation in `ARCHITECTURE-openflows.md` | Check whether `openflows-coder-compat` (see below) is still live; if not, recreate it, or rebuild the affected workspace through Coder |

### Known issue: `openflows-coder-compat` Service

A manual, non-chart-managed `LoadBalancer` Service at the pre-ingress-migration
IP (`192.168.1.201`), created live on 2026-09-29 after a cluster network
outage caused every running workspace's pod sandbox to be recreated at once,
which exposed the `accessUrl` limitation above across the entire fleet
simultaneously. It exists purely so already-provisioned workspaces can still
reach the old agent-download URL. Not tracked by ArgoCD or this repo's chart,
by design, it's a compatibility shim, not part of the target architecture.

Remove it once every live workspace has been rebuilt through Coder at least
once (each rebuild bakes in the current `openflows.int` URL):

```bash
kubectl delete svc openflows-coder-compat -n openflows
```

## Rollback Procedure

Revert the offending commit on `main` and let ArgoCD sync the reverted
state, do not run `helm rollback`, ArgoCD's `selfHeal` will just re-apply
`main` over it.

```bash
git revert <bad-commit-sha>
git push origin main
```

Then either wait for the next poll or force it immediately (see Deploy a
change above).

## Escalation

If the controller or Coder is down and the flow cannot recover, check the
controller first. By default (`controller.enabled=false`) it's the
`openflows run` process inside the nexus workspace pod, not a Deployment:

```bash
kubectl logs -n openflows -l app.kubernetes.io/name=openflows-nexus
```

If `controller.enabled=true` (the opt-in standalone Deployment):

```bash
kubectl logs deployment/openflows-controller -n openflows
```

Then the Coder logs:

```bash
kubectl logs deployment/openflows-coder -n openflows
```
