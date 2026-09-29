# ADR-0001: GitOps deployment via ArgoCD

Status: accepted

## Context

The chart was applied to the homelab cluster by hand, 12+ manual
`helm upgrade` runs, no CI, no audit trail of what changed or why. The
cluster has no public API endpoint (LAN-only), so a GitHub-hosted Actions
runner cannot reach it directly to push changes. The two viable shapes were:

- Push-based: a self-hosted GitHub Actions runner inside the homelab LAN,
  running `helm upgrade` on merge to `main`.
- Pull-based: a GitOps controller running inside the cluster, polling the
  repo and reconciling on its own, no inbound exposure needed.

## Decision

Pull-based GitOps via ArgoCD. The `openflows` `Application`
(`argocd/application.yaml`) tracks `charts/openflows` on `main` directly,
not a pinned chart version, and syncs automatically (`prune: true,
selfHeal: true`) roughly every 120 seconds.

ArgoCD itself is installed once, directly into the cluster, out-of-band from
this repo's own PR flow, it cannot GitOps itself into existence. This is the
one deployment step in this repo's entire lifecycle that isn't
merge-triggered.

## Consequences

- No more manual `helm upgrade`. Merging to `main` is the only way changes
  reach the cluster; a direct `kubectl edit` against a resource ArgoCD
  manages gets reverted on the next reconciliation.
- The private repo needs a credential ArgoCD can use to clone it. Deploy
  keys are disabled at the org level, so this currently uses a classic
  personal access token stored as a Secret in the `argocd` namespace,
  narrower than a deploy key would have been. Worth revisiting if the org
  re-enables deploy keys or a fine-grained PAT becomes practical.
- ArgoCD's own install, upgrade, and ingress are cluster infrastructure, not
  part of this repo. This repo only owns the `Application` that points
  ArgoCD at `charts/openflows`.
