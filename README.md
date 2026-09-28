# Openflows-Infra

Infra repo for the OpenFlows deployment. Owns the Helm chart and cluster
config that deploy the OpenFlows control plane and controller on Kubernetes,
the same way `talos-k8s` owns cluster config in the skyengpro group.

OpenFlows is an autonomous AI development team on Coder. It turns GitHub
issues into reviewed, production-ready pull requests. The product source lives
in the `openflows` repo; this repo owns how it runs on the cluster.

## Repo layout

| Path | Purpose |
|---|---|
| `charts/openflows/` | Helm chart for the OpenFlows control plane + controller |
| `docs/` | Architecture and runbook docs for the stack |

## Docs

- [docs/ARCHITECTURE-openflows.md](docs/ARCHITECTURE-openflows.md): what the
  stack is, its components, and how data flows through it.
- [docs/RUNBOOK-openflows.md](docs/RUNBOOK-openflows.md): how to operate the
  stack day to day.
- [charts/openflows/README.md](charts/openflows/README.md): how to install and
  configure the chart.

## Getting started

The chart deploys the control plane (Redis, PostgreSQL, Coder, and the
OpenFlows controller). Install it, then run the OpenFlows operator flow to
push workspace templates and add tenants:

```bash
helm install openflows charts/openflows -f <values-file>
openflows bootstrap
openflows tenant add <owner/repo> --name <team> --fleet 3
```

See the chart README for full install and configuration details.
