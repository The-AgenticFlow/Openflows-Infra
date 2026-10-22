# ADR-0004: Staging and production share one AWS account, isolated by state, network and identity

Status: proposed

## Context

OpenFlows needs a staging and a production environment on AWS, and nothing
else. They must be isolated: production state cannot be read or changed by
the staging deployment identity, each environment has its own network, DNS
names, data services and deployer, and public traffic only enters through
approved HTTPS ingress.

AWS recommends one account per environment, where the account boundary
gives that isolation for free. That needs AWS Organizations or two
standalone accounts, plus cross-account roles for every pipeline and
operator.

## Decision

Both environments live in one AWS account. Isolation comes from layers that
Terraform owns and reviews:

- **State:** one S3 state bucket and one KMS key per environment. Each
  bucket's policy can deny every principal outside that environment's
  allow-list.
- **Network:** one VPC per environment with non-overlapping CIDRs and no
  peering between them.
- **DNS and TLS:** one public hosted zone and one wildcard certificate per
  environment.
- **Identity:** every role carries an `Environment` tag and is scoped to its
  own environment's resources. That model is built with the IAM work, not
  in this landing zone.
- **Guard rails:** every provider pins `allowed_account_ids`, and every
  resource gets `Project`, `Environment`, `ManagedBy` and `Repository` tags
  by default.

## Consequences

- One account is cheaper and simpler to bootstrap: one set of credentials,
  no cross-account trust, one bill.
- Isolation depends on IAM and bucket policies being correct, not on a hard
  account boundary. A role with account-wide permissions, including any
  administrator, can still reach both environments. Administrator use is
  limited to break-glass (see the AWS runbook).
- Service quotas and some account-wide settings, such as the default EBS
  encryption key and Route 53 limits, are shared, so heavy staging use can
  affect production.
- Moving to separate accounts later is a migration: new state buckets,
  `terraform state` moves, and new deployer roles. The per-environment roots
  and the `allowed_account_ids` guard keep that move mechanical rather than
  a redesign.
