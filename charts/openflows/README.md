# openflows

Helm chart for the OpenFlows control plane and controller on Kubernetes.

## What it deploys

| Component | Kind | Notes |
|---|---|---|
| Redis | StatefulSet + Service | OpenFlows SharedStore (appendonly) |
| PostgreSQL | StatefulSet + Service | Coder database |
| Coder server | Deployment + Service + Ingress | Control plane, kubernetes provisioner |
| Coder RBAC | ServiceAccount + ClusterRole(Binding) | Lets the kubernetes provisioner create workspace pods |
| OpenFlows controller | Deployment + Service | Standalone controller + hook consumer (:3001) |

## Install

```bash
helm install openflows charts/openflows \
  --set coder.accessUrl=https://coder.example.com \
  --set coder.ingress.host=coder.example.com \
  --set coder.externalAuth.clientId=<gh-app-id> \
  --set secrets.githubClientSecret=<gh-app-secret> \
  --set secrets.coderSessionToken=<token> \
  --set secrets.coderChatHookSecret=$(openssl rand -hex 32)
```

Secrets can instead be supplied via `--set existingSecret=<name>` (a Secret
with the keys listed under `secrets` in `values.yaml`).

## Post-install

The chart stands up the control plane. After it is healthy, run the OpenFlows
operator flow to push workspace templates and add tenants:

```bash
openflows bootstrap
openflows tenant add <owner/repo> --name <team> --fleet 3
```

## Configuration

All configuration lives in `values.yaml`. Key sections:

| Section | Purpose |
|---|---|
| `redis` | SharedStore image, persistence |
| `postgres` | Coder DB image, user, persistence |
| `coder` | Coder image/tag, access URL, ingress, GitHub external auth, provisioner |
| `controller` | Controller image/tag, tenant, hook address |
| `secrets` | Inline secret values (or use `existingSecret`) |

## Known gaps

- **Workspace templates**: the kubernetes provisioner needs Coder workspace
  templates that target the `kubernetes` provider (the compose setup used the
  `docker` provider). These are pushed by `openflows bootstrap`; the templates
  themselves are not part of this chart yet.
- **Postgres password**: generated once at install. Pin `postgres.password` or
  set `postgres.existingSecret` for a stable value across `helm upgrade`.
- **Controller placement**: currently a standalone Deployment (lifted out of the
  nexus workspace). To use the original in-workspace model instead, disable the
  controller Deployment (`controller.enabled=false`) and let Coder provision it
  as a workspace.
