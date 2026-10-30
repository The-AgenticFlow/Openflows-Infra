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
| `openflows-manager-setup` job fails with a missing operator token or secret | `coder-operator-token` (or a GitHub secret) is not in `openflows/staging/manager/` | Create it ("Deploying the Manager"), then sync the app again |
| Manager pod restarts, logs `hosted mode requires ...` | A required setting or secret reference is missing from the app's values | The message names it; add it to `gitops/staging/apps/openflows-manager.yaml` |
| `/ready` is unavailable and names Coder | Coder's version does not start with `OPENFLOWS_CODER_VERSION_BASELINE` | Set the baseline to the running Coder version, or upgrade Coder and the baseline together |
| GitHub webhook deliveries fail with a signature error | The webhook secret differs between the app's settings and Secrets Manager | Set both to the same value and restart the Manager |
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

### Deploying the Manager

The Manager runs as its own Argo CD app, `openflows-manager`
([`gitops/staging/apps/openflows-manager.yaml`](../gitops/staging/apps/openflows-manager.yaml)).
A sync runs three steps in order: a database job creates the `openflows_manager`
role and the `openflows_control_plane` database on the shared PostgreSQL, a
setup job runs `openflows-manager setup`, then the Deployment starts.

Before the first sync, these must exist in Secrets Manager (eu-west-1), all
under `openflows/staging/manager/`:

| Secret | What it is | Who creates it |
|---|---|---|
| `github-client-secret`, `github-private-key`, `github-webhook-secret` | Credentials of the `OpenFlows Manager staging` GitHub App | A person, from the app's settings page |
| `coder-operator-token` | A Coder API token of an owner account, created under Account, Tokens in Coder. Use a long lifetime and a name such as `openflows-manager` | A person |

`setup` then creates `crypto-master-key`, `coder-hook-secret` and
`coder-oauth-client-secret` itself and registers the Manager's OAuth
application in Coder. It refuses to run without the operator token, and it does
not adopt an existing Coder installation by creating an administrator for you.

Check it after a sync:

```bash
kubectl -n openflows get pods -l app.kubernetes.io/name=openflows-manager
curl -fsS https://manager.trial.openflows.dev/health
curl -sS https://manager.trial.openflows.dev/ready
kubectl -n openflows exec deploy/openflows-manager -- openflows-manager doctor
```

`/health` only says the process is up; `/ready` also checks the Manager's
dependencies and names the one that fails. `doctor` runs read-only checks and
exits non-zero if any fails. Run it inside the Deployment, as above, so it
uses the deployed settings and the Manager's AWS role; a separate pod would
check different ones. The setup job can be rerun from the Argo CD UI (sync the
app), and the database job likewise.

To rotate the Manager's database password, in this order, because the
Kubernetes Secret refreshes only hourly:

1. Increase `manager_db_version` in
   [`terraform/modules/app-secrets/variables.tf`](../terraform/modules/app-secrets/variables.tf)
   (or set it in the staging root) and merge; the pipeline writes the new
   password.
2. Refresh the Kubernetes Secret and confirm it changed:
   `kubectl -n openflows annotate externalsecret openflows-manager force-sync=$(date +%s) --overwrite`,
   then check the `openflows-manager` Secret's `password` differs from before.
3. Sync the `openflows-manager` app so the database job sets the role's
   password to the new value.
4. Restart the Manager so it reads the new URL:
   `kubectl -n openflows rollout restart deploy/openflows-manager`.

Skipping step 2 makes the job write the old password back; skipping step 4
leaves the running Manager on the old one.

To rotate a GitHub App credential, put the new value on the same secret name
(`put-secret-value`), then restart the Deployment so it reads it:
`kubectl -n openflows rollout restart deploy/openflows-manager`. Rotate the
webhook secret in the app's settings and in Secrets Manager together; one
mismatch makes every delivery fail.

### Upgrading Coder

Coder is pinned by `coder.tag` in
[`charts/openflows/values.yaml`](../charts/openflows/values.yaml); staging does
not override it, so a chart release carries the version. The tested version is
in the AWS architecture doc's Version Matrix. Coder runs its database
migrations when the new server starts, and they only go forward: putting the
old image back does not undo them. So every upgrade starts with a dump.

1. Read the release notes for every minor version between the current and the
   target tag. Prefer one minor version at a time, since bigger jumps run more
   migrations
   ([Coder upgrade best practices](https://coder.com/docs/install/operate/upgrade/best-practices)).
2. Dump the database to your machine (through the SSM tunnel):

   ```bash
   kubectl -n openflows exec openflows-postgres-0 -- \
     pg_dump -U coder -d coder -Fc > coder-$(date +%F).dump
   ```

3. Bump `coder.tag` and the chart version in a PR, update the Version Matrix,
   and merge. Argo CD rolls `openflows-coder`.
4. Watch the migration, and press Ctrl-C once the server reports it is
   listening. Then check it answers:

   ```bash
   kubectl -n openflows logs deploy/openflows-coder -f | grep -i migrat
   curl -fsS https://coder.trial.openflows.dev/healthz
   ```

   The Coder Deployment has no liveness probe, so a long migration is not
   killed halfway.
5. Sync `openflows-bootstrap` in Argo CD. It reruns `openflows bootstrap`
   against the new version; if the Job fails, roll back.

If the new server keeps restarting because of database locks, run the
migration in a single pod, as Coder's guide recommends. A manual scale does not
stick under Argo CD's `selfHeal`, so use Git: merge `replicas: 0` (see the
rollback steps below), wait until `openflows-coder` has no pods, then remove it
again.

<details>
<summary>Rolling back to the previous Coder version</summary>

Reverting the tag alone leaves the database on the newer schema, so restore
the dump from step 2 while no Coder pod runs. Argo CD's `selfHeal` undoes a
manual `kubectl scale`, so stop Coder through Git:

1. Merge one PR that reverts the upgrade commit and sets `replicas: 0` under
   `helm.valuesObject.coder` in
   [`gitops/staging/apps/openflows.yaml`](../gitops/staging/apps/openflows.yaml).
2. Once `openflows-coder` has no pods, recreate the database empty and
   restore into it. Restoring over the upgraded database would leave tables
   the newer version added, so start clean. `--exit-on-error` makes a failed
   restore stop with a non-zero exit instead of half-applying:

   ```bash
   kubectl -n openflows exec openflows-postgres-0 -- psql -U coder -d postgres \
     -c 'DROP DATABASE coder WITH (FORCE)' -c 'CREATE DATABASE coder OWNER coder'
   kubectl -n openflows exec -i openflows-postgres-0 -- \
     pg_restore -U coder -d coder --exit-on-error < coder-<date>.dump
   ```

3. Only if the restore exited 0, merge a second PR that removes
   `replicas: 0`. The old version starts on the old schema. If it failed, keep
   Coder stopped and fix the restore first.

Anything users did between the dump and the restore is lost.

</details>

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
