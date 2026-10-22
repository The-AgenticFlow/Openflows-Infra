# ADR-0004: OpenFlows runs in a shared AWS account, isolated by state, network, identity and a permissions boundary

Status: proposed

## Context

OpenFlows needs a staging and a production environment on AWS, and nothing
else. They must be isolated: production state cannot be read or changed by
the staging deployment identity, each environment has its own network, DNS
names, data services and deployer, and public traffic only enters through
approved HTTPS ingress.

The AWS account available to OpenFlows is a member account of an AWS
Organization, and it already hosts other projects: their S3 buckets, Route 53
zones and IAM roles live in the same account. AWS recommends one account per
environment, which isolates everything by default, but that needs new member
accounts and cross-account access that are not in place yet.

## Decision

Both OpenFlows environments live in the existing shared account. Isolation,
from each other and from the other projects, comes from layers Terraform owns:

- **Permissions boundary:** every OpenFlows role carries
  `openflows-permissions-boundary`. Whatever a role's own policies allow, it
  can only manage IAM under the `/openflows/` path, only use `openflows-*` S3
  buckets, and only change or read secrets of resources tagged
  `Project=openflows`. A role can only create roles that carry the same
  boundary, and cannot remove or edit it.
- **State:** one S3 state bucket and one KMS key per environment. Each bucket
  denies every principal except that environment's plan and apply roles, the
  platform admin role and a break-glass principal.
- **Identity:** GitHub Actions assumes per-environment roles through OIDC.
  Plan roles are read-only; staging applies only from `main`, production only
  from `v*` release tags. Humans assume `openflows-platform-admin` or
  `openflows-readonly`, both requiring MFA.
- **Network, DNS and TLS:** one VPC, hosted zone and certificate per
  environment, with non-overlapping CIDRs and no peering.
- **Guard rails:** every provider pins `allowed_account_ids`, and every
  resource gets `Project`, `Environment`, `ManagedBy` and `Repository` tags.

## Consequences

- Work can start in the account that exists today, with no organization
  changes.
- Isolation rests on the boundary and bucket policies being correct, not on an
  account boundary. A principal outside OpenFlows with account-wide admin
  rights can still reach OpenFlows resources, and the bootstrap itself runs
  as such a principal until the scoped roles exist.
- Account-wide settings are shared with the other projects: service quotas
  (Elastic IPs, VPCs), the GitHub OIDC provider, the default EBS encryption key
  and Route 53 limits. Some actions cannot be limited by tag, notably record
  changes in other projects' hosted zones, so plan review stays the control
  for those.
- Changing the boundary needs a principal without it, such as the bootstrap
  operator or the account root, because the boundary forbids its own edits.
- Moving to dedicated member accounts later is a migration: new state
  buckets, `terraform state` moves and new roles. The per-environment roots
  and the `aws_account_id` input keep that move mechanical.
