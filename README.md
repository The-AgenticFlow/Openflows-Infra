# Openflows-Infra

Infrastructure-as-code for the [OpenFlows](https://github.com/The-AgenticFlow) deployment: the Helm chart and cluster configuration that run the OpenFlows control plane and controller on Kubernetes.

OpenFlows is an autonomous AI development team on [Coder](https://coder.com): it turns GitHub issues into reviewed, production-ready pull requests. The product source lives in the `openflows` repo; this repo owns how it runs on the cluster.

## Repository

| Path | Purpose |
|---|---|
| [`charts/openflows/`](charts/openflows/) | Helm chart for the OpenFlows control plane (Redis, PostgreSQL, Coder) and controller |
| [`charts/openflows/Chart.yaml`](charts/openflows/Chart.yaml) | Chart metadata and version |
| [`charts/openflows/values.yaml`](charts/openflows/values.yaml) | Default chart values |
| [`charts/openflows/values-homelab.yaml`](charts/openflows/values-homelab.yaml) | Homelab environment values |
| [`charts/openflows/templates/`](charts/openflows/templates/) | Chart templates |
| [`charts/openflows/README.md`](charts/openflows/README.md) | Install, values, and configuration reference |
| [`docs/ARCHITECTURE-openflows.md`](docs/ARCHITECTURE-openflows.md) | What the stack is, its components, and how data flows through it |
| [`docs/RUNBOOK-openflows.md`](docs/RUNBOOK-openflows.md) | Day-to-day operations |
| [`gitops/`](gitops/) | Argo CD values and the per-environment Applications Argo CD syncs on AWS |
| [`terraform/`](terraform/) | AWS foundation for staging and production: state bootstrap, shared modules, one root per environment |
| [`docs/ARCHITECTURE-aws.md`](docs/ARCHITECTURE-aws.md) | The AWS landing zone: state, networks, DNS and certificates |
| [`docs/RUNBOOK-aws.md`](docs/RUNBOOK-aws.md) | Bootstrap, change control, state ownership and break-glass access for the AWS foundation |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Security issues: see [SECURITY.md](SECURITY.md). Please do not open public issues for vulnerabilities.

## License

[Apache License 2.0](LICENSE)
