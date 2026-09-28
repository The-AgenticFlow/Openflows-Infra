# OpenFlows Architecture

## Deployment Quick Reference

| Fact | Value |
|---|---|
| Namespace | `openflows` (default) |
| Chart | `charts/openflows` |
| Workload shape | 2 StatefulSets (redis, postgres), 2 Deployments (coder, controller) |
| Coder endpoint | `https://coder.example.com` (ingress) |
| Controller hook port | 3001 |
| Provisioner | kubernetes |
| Secret source | `existingSecret` or inline values |

## System Overview

```mermaid
flowchart LR
  subgraph ControlPlane
    C[Coder server]
    P[(PostgreSQL)]
    R[(Redis)]
    CT[OpenFlows controller]
  end
  subgraph Workspaces
    N[Nexus workspace]
    W[Worker workspaces]
  end
  C --> P
  C --> CT
  CT --> R
  CT --> C
  C --> N
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
| OpenFlows image | latest | `values.yaml` -> `controller.tag` | Pin to a release tag, not `latest` |

## Components

| Name | Type | Source | Purpose |
|---|---|---|---|
| Redis | StatefulSet | `redis:7-alpine` | OpenFlows SharedStore, single source of truth |
| PostgreSQL | StatefulSet | `postgres:16-alpine` | Coder database |
| Coder | Deployment | `ghcr.io/coder/coder` | Control plane: identity, model gateway, API, provisioner |
| Controller | Deployment | `ghcr.io/the-agenticflow/openflows` | Orchestration loop + hook consumer + A2A relay |

## Key Flows

```mermaid
sequenceDiagram
  participant U as User
  participant C as Coder
  participant CT as Controller
  participant R as Redis
  U->>C: GitHub issue
  C->>CT: lifecycle hook
  CT->>R: read/write SharedStore
  CT->>C: provision workspace, create chat
  C->>CT: agent progress
  CT->>C: merge PR
```

The controller polls Redis every 15 seconds, runs one flow pass, and sleeps.
It is the only component that calls the Coder API to create chats and
provision workspaces. Worker workspaces talk to Redis only through the
`openflows worker` harness.

## Key Decisions

- **Standalone controller Deployment.** The controller is lifted out of the
  nexus workspace into its own Deployment. Simpler to operate than the
  in-workspace model. Reversible via `controller.enabled=false`.
- **Kubernetes provisioner.** Coder creates workspace pods natively instead of
  mounting a docker socket. Requires the RBAC in `coder-rbac.yaml`.
- **Control plane first.** The chart covers Redis, PostgreSQL, Coder, and the
  controller. Workspace templates are pushed by `openflows bootstrap`, not
  part of the chart yet.

## Networking

- Coder: ingress on 443, HTTP bind on 7080.
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
- The Postgres password regenerates on `helm upgrade` unless pinned.
- The Coder Chats API is experimental; the chart pins a verified Coder version.

## Key File Locations

| Path | Purpose |
|---|---|
| `charts/openflows/values.yaml` | All chart configuration |
| `charts/openflows/templates/coder-deployment.yaml` | Coder server |
| `charts/openflows/templates/coder-rbac.yaml` | Kubernetes provisioner RBAC |
| `charts/openflows/templates/controller-deployment.yaml` | Controller |
| `charts/openflows/templates/secrets.yaml` | Secret rendering |
