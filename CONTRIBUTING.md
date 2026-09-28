# Contributing to Openflows-Infra

Thanks for your interest in contributing. This repo is small and focused: it owns the Helm chart and cluster configuration for OpenFlows. Keep changes scoped to that.

## How to contribute

1. **Open an issue first** for anything non-trivial (new chart feature, values change with breaking potential, doc restructuring) so we can agree on the approach.
2. **Fork and branch** from `main`. Use a descriptive branch name: `feat/autoscaling-controller`, `fix/postgres-probe`, `docs/runbook-update`.
3. **Make your change.** Keep commits in conventional format:
   `<type>(<scope>): <imperative description>`, e.g. `fix(chart): correct postgres readiness probe path`. Types: `feat fix chore docs refactor test perf ci style`.
4. **Validate before opening a PR:**

   ```bash
   helm lint charts/openflows
   helm template openflows charts/openflows -f charts/openflows/values-homelab.yaml > /dev/null
   ```

5. **Open a pull request** against `main`. Describe what changed and why, and link the issue if there is one.

## Rules

- **Never commit secrets.** Reference secrets via `ExternalSecret` or Kubernetes Secret references. If a secret lands in git history, treat it as compromised and rotate it.
- **No direct pushes to `main`.** All changes go through PRs.
- **No co-authored-by trailers** in commits.
- **Chart changes need a version bump** in `charts/openflows/Chart.yaml` (patch for fixes, minor for features, major for breaking values changes) and an update to the chart README if values change.
- **Docs stay current.** If your change alters behavior described in `docs/` or the chart README, update them in the same PR.

## Reporting security issues

Do not open public issues for security vulnerabilities. Follow the process in [SECURITY.md](SECURITY.md).

## Questions

Open a discussion or issue and we will respond.
