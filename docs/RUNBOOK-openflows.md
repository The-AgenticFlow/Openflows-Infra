# OpenFlows Runbook

## Common Operations

### Install the chart

```bash
helm install openflows charts/openflows -f <values-file>
```

### Upgrade the chart

```bash
helm upgrade openflows charts/openflows -f <values-file>
```

### Render the chart without applying

```bash
helm template openflows charts/openflows -f <values-file>
```

### Scale the controller

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
