# OpenFlows Architecture

## Deployment Quick Reference

| Fact | Value |
|---|---|
| Namespace | `openflows` (default) |
| Chart | `charts/openflows` |
| Workload shape | 2 StatefulSets (redis, postgres), 1 Deployment (coder); controller runs inside the nexus workspace by default |
| Coder endpoint | `http://openflows.int` (ingress, plain HTTP, see [ADR-0003](ADR-0003-plain-http-internal-ingress.md)) |
| Controller hook port | 3001 |
| Provisioner | kubernetes |
| Secret source | `existingSecret` or inline values |
| Deploy mechanism | ArgoCD (`argocd/application.yaml`), tracks `charts/openflows` on `main` |

## System Overview

```mermaid
flowchart LR
  subgraph ControlPlane
    C[Coder server]
    P[(PostgreSQL)]
    R[(Redis)]
  end
  subgraph Workspaces
    N[Nexus workspace<br/>runs the controller]
    W[Worker workspaces]
  end
  C --> P
  C --> N
  N --> R
  N --> C
  C --> W
  W --> R
```

OpenFlows runs an autonomous AI development team on Coder. Coder governs where
agents run (ephemeral workspaces); OpenFlows governs how they coordinate (the
flow graph, typed state contracts, the planning gate). The control plane is
long-lived and trusted. The worker workspaces are ephemeral and governed.

## Version Matrix

| Component | Version | Pinned in | Upgrade notes |
|---|---|---|---|
| Coder | v2.37.1 | `values.yaml` -> `coder.tag` | Chats API is experimental; pin and verify |
| Redis | 7-alpine | `values.yaml` -> `redis.image` | |
| PostgreSQL | 16-alpine | `values.yaml` -> `postgres.image` | |
| Workspace image | 1.3.3 | `values.yaml` -> `workspace.image` | Runs the embedded controller (`openflows run`) by default |
| OpenFlows image | latest | `values.yaml` -> `controller.tag` | Only used when `controller.enabled=true`; pin to a release tag, not `latest` |

## Components

| Name | Type | Source | Purpose |
|---|---|---|---|
| Redis | StatefulSet | `redis:7-alpine` | OpenFlows SharedStore, single source of truth |
| PostgreSQL | StatefulSet | `postgres:16-alpine` | Coder database |
| Coder | Deployment | `ghcr.io/coder/coder` | Control plane: identity, model gateway, API, provisioner |
| Controller (default) | Process in the nexus workspace pod | Workspace image (`openflows` binary) | Orchestration loop + hook consumer + A2A relay, started by the nexus template's startup script |
| Controller (opt-in) | Deployment | `ghcr.io/the-agenticflow/openflows` | Same role, lifted out of the workspace when `controller.enabled=true` |

## Key Flows

```mermaid
sequenceDiagram
  participant U as User
  participant C as Coder
  participant N as Nexus (controller)
  participant R as Redis
  U->>C: GitHub issue
  C->>N: lifecycle hook
  N->>R: read/write SharedStore
  N->>C: provision workspace, create chat
  C->>N: agent progress
  N->>C: merge PR
```

The controller polls Redis every 15 seconds, runs one flow pass, and sleeps.
It is the only component that calls the Coder API to create chats and
provision workspaces. Worker workspaces talk to Redis only through the
`openflows worker` harness.

### Deploying a change

```mermaid
sequenceDiagram
  participant Dev as Developer
  participant GH as GitHub (main)
  participant Argo as ArgoCD
  participant K8s as Cluster
  Dev->>GH: merge PR
  loop every ~120s
    Argo->>GH: poll for new commits
  end
  Argo->>K8s: apply rendered chart (prune + selfHeal)
  K8s->>K8s: ConfigMap-only change? checksum<br/>annotation changes, pod rolls automatically
  K8s-->>Argo: report health
```

No manual `helm upgrade` or `kubectl apply` in this path. A direct
`kubectl edit` against a live resource gets reverted on the next
reconciliation, `selfHeal` treats it as drift from git.

## Key Decisions

- **In-workspace controller by default.** The controller runs as the
  `openflows run` process inside the nexus workspace pod, started by the
  nexus template's startup script. No separate Deployment to operate when
  there's already exactly one workspace running the control loop. Lift it
  into a standalone Deployment via `controller.enabled=true` to decouple its
  lifecycle from the nexus workspace.
- **Kubernetes provisioner.** Coder creates workspace pods natively instead of
  mounting a docker socket. Requires the RBAC in `coder-rbac.yaml`.
- **Control plane first.** The chart covers Redis, PostgreSQL, Coder, and the
  controller. Workspace templates are pushed by `openflows bootstrap`, not
  part of the chart yet.
- **GitOps via ArgoCD, no external secret backend.** `argocd/application.yaml`
  tracks `charts/openflows` on `main` and syncs automatically on merge.
  Secrets stay as in-cluster Secret objects referenced via `existingSecret`,
  this cluster has no External Secrets Operator or cloud secret manager.
  ArgoCD itself is installed once, out-of-band, it can't sync itself into
  existence.

## Networking

- Coder: ingress on 80 (plain HTTP, `ssl-redirect` disabled, no TLS cert for
  the internal `.int` hostname), Service HTTP bind on 7080.
- Controller: hook consumer on 3001, A2A relay on 3000 (localhost only).
- Redis: 6379, cluster-internal.
- PostgreSQL: 5432, cluster-internal.

## Secrets

Secrets are supplied via `existingSecret` (recommended) or inline values
rendered into a Secret. The GitHub App client secret, Coder session token, and
hook secret never appear in the ConfigMap. Never inline a secret value into a
manifest or Helm value.

## Known Limitations

- Workspace templates are not part of the chart. They must be pushed by
  `openflows bootstrap` after install.
- The Postgres password regenerates on install/upgrade unless pinned via
  `postgres.password` or `postgres.existingSecret` (the live deployment uses
  `existingSecret`, not affected).
- The Coder Chats API is experimental; the chart pins a verified Coder version.
- Secret changes (`existingSecret` contents, `postgres.existingSecret`) do not
  auto-restart pods, only ConfigMap changes do (see `checksum/config`
  annotation on the Coder Deployment). A secret rotation still needs a manual
  `kubectl rollout restart`.
- **Changing `coder.accessUrl` breaks reconnection for already-provisioned
  workspaces.** Coder's Kubernetes provisioner bakes the agent download URL
  (`{access_url}/bin/coder-{os}-{arch}`) into each workspace's startup
  script at the time Coder last built it via Terraform, it does not
  dynamically read the current `CODER_ACCESS_URL`. If a workspace's pod
  sandbox gets recreated (node restart, eviction, network interruption)
  after `accessUrl` changed, its startup script still points at the old
  URL and gets permanently stuck retrying the agent download. The only
  fixes are rebuilding the workspace through Coder (picks up the current
  `accessUrl`, disruptive to any in-progress agent work) or keeping a
  compatibility endpoint alive at the old URL until every live workspace
  has naturally been rebuilt at least once.

## Key File Locations

| Path | Purpose |
|---|---|
| `charts/openflows/values.yaml` | All chart configuration |
| `charts/openflows/templates/coder-deployment.yaml` | Coder server |
| `charts/openflows/templates/coder-rbac.yaml` | Kubernetes provisioner RBAC |
| `charts/openflows/templates/controller-deployment.yaml` | Controller (only rendered when `controller.enabled=true`) |
| `charts/openflows/templates/secrets.yaml` | Secret rendering |
| `argocd/application.yaml` | ArgoCD Application, GitOps sync from `main` |
| `docs/ADR-0001-gitops-via-argocd.md` | Why GitOps/ArgoCD over a self-hosted-runner push pipeline |
| `docs/ADR-0002-in-cluster-secrets.md` | Why secrets stay in-cluster, no ESO/cloud backend |
| `docs/ADR-0003-plain-http-internal-ingress.md` | Why plain HTTP and `.int`, not TLS or `.dev`/`.home` |
