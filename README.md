# Openflows-Infra

Infrastructure-as-code for the [OpenFlows](https://github.com/The-AgenticFlow) deployment: the Helm chart and cluster configuration that run the OpenFlows control plane and controller on Kubernetes.

OpenFlows is an autonomous AI development team on [Coder](https://coder.com): it turns GitHub issues into reviewed, production-ready pull requests. The product source lives in the `openflows` repo; this repo owns how it runs on the cluster.

## Layout

| Path | Purpose |
|---|---|
| `charts/openflows/` | Helm chart for the OpenFlows control plane (Redis, PostgreSQL, Coder) and controller |
| `docs/` | Architecture and runbook docs for the stack |

## Documentation

| Doc | Contents |
|---|---|
| [Architecture](docs/ARCHITECTURE-openflows.md) | What the stack is, its components, and how data flows through it |
| [Runbook](docs/RUNBOOK-openflows.md) | Day-to-day operations |
| [Chart README](charts/openflows/README.md) | Install, values, and configuration reference |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Security issues: see [SECURITY.md](SECURITY.md). Please do not open public issues for vulnerabilities.

## License

[Apache License 2.0](LICENSE)
