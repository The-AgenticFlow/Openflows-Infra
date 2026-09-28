# Security Policy

## Supported versions

We patch security issues in the latest released chart version only. Upgrade before reporting if you are behind.

| Version | Supported |
|---|---|
| 0.1.x | Yes |
| < 0.1 | No |

## Reporting a vulnerability

**Do not open a public GitHub issue for security vulnerabilities.**

Report privately via [GitHub Security Advisories](https://github.com/The-AgenticFlow/Openflows-Infra/security/advisories/new) ("Report a vulnerability"). If you cannot use that form, contact the maintainers directly and we will set up a private channel.

Please include:

- A description of the vulnerability and its impact
- Steps to reproduce or a proof of concept
- Affected chart version(s) and values configuration
- Any suggested fix (optional)

## What to expect

- **Acknowledgement** within 48 hours
- **Triage and severity assessment** within 7 days
- **Fix and coordinated disclosure** agreed with you before any public announcement

We credit reporters in the advisory by default; tell us if you prefer to stay anonymous.

## Scope

In scope: the Helm chart in `charts/openflows/`, its default values, and the manifests it renders. Out of scope: vulnerabilities in upstream images (Redis, PostgreSQL, Coder) unless they are triggered by a misconfiguration this chart introduces; report those upstream and let us know so we can track the fix.
