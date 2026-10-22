# AWS Foundation Architecture

The AWS landing zone that OpenFlows staging and production run on: remote
Terraform state, one network per environment, and the DNS zone and
certificate each environment's HTTPS ingress uses. EKS, IAM roles and data
services build on top of it.

## Deployment Quick Reference

| | |
|---|---|
| Environments | `staging`, `production` |
| AWS account | `686255958454`, an organization member account shared with other projects (see [ADR-0004](ADR-0004-shared-aws-account.md)) |
| Region | `eu-west-1` |
| Terraform roots | `terraform/bootstrap`, `terraform/envs/staging`, `terraform/envs/production` |
| State | One encrypted, versioned S3 bucket per environment and one for the bootstrap, S3 native locking |
| Networks | `10.20.0.0/16` staging, `10.30.0.0/16` production |
| CI identity | GitHub Actions OIDC, one plan role and one apply role per environment |
| Human access | `openflows-platform-admin` and `openflows-readonly`, both MFA only |
| Apply path | Reviewed PR, then a plan and apply per environment (see [RUNBOOK-aws.md](RUNBOOK-aws.md)) |

## System Overview

Three Terraform roots share one AWS account. `terraform/bootstrap` creates
everything the other two depend on: the state buckets, the IAM that GitHub
Actions and people use, and the permissions boundary that caps all of it.
Each environment root then owns its own network, DNS zone and certificate, and
keeps its state in its own bucket.

```mermaid
flowchart TB
    GH[GitHub Actions]
    subgraph Account["AWS account, eu-west-1, shared with other projects"]
        subgraph Boot["terraform/bootstrap"]
            IAM["GitHub OIDC provider and OpenFlows roles"]
            BND["openflows-permissions-boundary"]
            BB[("Bootstrap state bucket")]
            SB[("Staging state bucket")]
            PB[("Production state bucket")]
        end
        subgraph Stg["terraform/envs/staging"]
            SNET["VPC 10.20.0.0/16, Route 53 zone, certificate"]
        end
        subgraph Prd["terraform/envs/production"]
            PNET["VPC 10.30.0.0/16, Route 53 zone, certificate"]
        end
    end
    GH -->|"OIDC, no stored keys"| IAM
    BND -.->|caps| IAM
    IAM -->|plans and applies| Stg
    IAM -->|plans and applies| Prd
    Boot -->|state| BB
    Stg -->|state| SB
    Prd -->|state| PB
```

Each environment's network spans three availability zones:

```mermaid
flowchart LR
    Internet((Internet)) --> IGW[Internet gateway]
    IGW --> Pub[Public subnets, one /24 per AZ]
    Pub --> NAT[NAT gateways]
    Priv[Private subnets, one /20 per AZ] -->|egress| NAT
    Pub -.->|future| ALB[HTTPS load balancer]
    ALB -.-> Priv
```

## Version Matrix

| Component | Version | Pinned in | Upgrade notes |
|---|---|---|---|
| Terraform | `>= 1.11` | [`terraform/envs/staging/versions.tf`](../terraform/envs/staging/versions.tf) and the other roots | 1.11 is the first release with GA S3 native state locking (`use_lockfile`) |
| AWS provider | `~> 6.70` | [`terraform/envs/staging/versions.tf`](../terraform/envs/staging/versions.tf), [`terraform/bootstrap/versions.tf`](../terraform/bootstrap/versions.tf) | Modules require `>= 6.28`, the floor of the pinned VPC module |
| `terraform-aws-modules/vpc/aws` | `6.7.3` | [`terraform/modules/network/main.tf`](../terraform/modules/network/main.tf) | Read the module changelog before bumping; input names change across majors |

## Components

| Component | Type | Source | Purpose |
|---|---|---|---|
| State buckets | S3 | `terraform/bootstrap` | One per environment plus one for the bootstrap: versioned, KMS-only uploads, public access blocked, TLS only |
| State keys | KMS | `terraform/bootstrap` | One customer-managed key per state bucket, yearly rotation |
| VPC | VPC module | `terraform/modules/network` | Public and private subnets across three AZs, flow logs to CloudWatch |
| NAT gateways | VPC module | `terraform/modules/network` | Private subnet egress: one shared in staging, one per AZ in production |
| Hosted zone | Route 53 | `terraform/modules/dns` | Public DNS for the environment's domain |
| Certificate | ACM | `terraform/modules/dns` | Wildcard certificate for the HTTPS ingress, validated through the zone |
| Permissions boundary | IAM policy | `terraform/bootstrap` | Ceiling on every OpenFlows role: IAM under `/openflows/` only, `openflows-*` buckets only, no changes to resources not tagged `Project=openflows` |
| GitHub OIDC provider | IAM | `terraform/bootstrap` | Lets GitHub Actions assume AWS roles without stored keys |
| `openflows-<env>-terraform-plan` | IAM role | `terraform/bootstrap` | Read-only plans from pull requests and `main` |
| `openflows-<env>-terraform-apply` | IAM role | `terraform/bootstrap` | Applies: staging from `main`, production from `v*` tags; limited to its own environment's tags, IAM path and buckets |
| `openflows-platform-admin`, `openflows-readonly` | IAM roles | `terraform/bootstrap` | Human break-glass and day-to-day access, MFA required |

## Access Model

No AWS key is stored in GitHub, and nobody works as an administrator day to
day. GitHub Actions reaches AWS only through OIDC, and each role trusts a
specific kind of run. People sign in as an IAM user and assume a role with MFA.
Every one of these roles carries the permissions boundary.

```mermaid
flowchart LR
    PR["Pull request or main"] -->|OIDC| PLAN["openflows-env-terraform-plan, read-only"]
    MAIN["Push to main"] -->|OIDC| SAPPLY["openflows-staging-terraform-apply"]
    TAG["Release tag v*"] -->|OIDC| PAPPLY["openflows-production-terraform-apply"]
    USER["Operator IAM user"] -->|"assume, MFA"| ADMIN["openflows-platform-admin"]
    USER -->|"assume, MFA"| RO["openflows-readonly"]
    BND{{"openflows-permissions-boundary"}}
    BND -.-> PLAN
    BND -.-> SAPPLY
    BND -.-> PAPPLY
    BND -.-> ADMIN
    BND -.-> RO
```

## Key Flows

### A GitHub Actions job gets AWS credentials

The job never holds a long-lived key. It trades a short-lived GitHub token for
one hour of AWS credentials, and AWS only agrees if the token comes from this
repository and from the ref the role trusts.

```mermaid
sequenceDiagram
    autonumber
    participant Job as GitHub Actions job
    participant GHO as GitHub OIDC issuer
    participant STS as AWS STS
    participant Role as openflows-staging-terraform-apply
    participant State as Staging state bucket
    Job->>GHO: Request an ID token for audience sts.amazonaws.com
    GHO-->>Job: Token with sub repo:The-AgenticFlow/Openflows-Infra:ref:refs/heads/main
    Job->>STS: AssumeRoleWithWebIdentity with the token
    STS->>Role: Check the trust policy: repository and ref match
    STS-->>Job: Temporary credentials, valid one hour
    Job->>State: Read state and write the lock file
    Job->>Job: terraform plan, then apply the saved plan
```

### How an AWS call from an apply role is decided

`AdministratorAccess` grants the call, then two layers of explicit deny take
it back unless it stays inside OpenFlows and inside the role's environment.

```mermaid
flowchart TD
    CALL["AWS call from openflows-staging-terraform-apply"] --> B1{"Touches IAM outside /openflows/, a bucket not named openflows-*, or a resource not tagged Project=openflows?"}
    B1 -->|yes| DENY1["Denied by the permissions boundary"]
    B1 -->|no| B2{"Touches the bootstrap roles, the GitHub OIDC provider or the boundary?"}
    B2 -->|yes| DENY1
    B2 -->|no| E1{"Resource tagged for production, IAM outside /openflows/staging/, or a production bucket?"}
    E1 -->|yes| DENY2["Denied by the role's environment-isolation policy"]
    E1 -->|no| OK["Allowed"]
```

## Key Decisions

- **One account, isolated by state, network and identity.** See
  [ADR-0004](ADR-0004-shared-aws-account.md).
- **A permissions boundary on every role.** The account hosts other
  projects, so OpenFlows roles are capped by a boundary rather than trusted
  to have narrow policies. Apply roles hold `AdministratorAccess` inside it.
- **CI trust pinned to refs, not GitHub environments.** Private repositories
  on the current GitHub plan cannot protect environments, so the AWS trust
  policy is the gate: production apply only from `v*` tags.
- **Environments are isolated from each other, not only from other projects.**
  Each apply role can only change resources tagged with its own `Environment`,
  only write IAM under `/openflows/<env>/`, and only use `openflows-<env>-*`
  buckets and its own state bucket.
- **The bootstrap owns the shared IAM.** Its roles, the GitHub OIDC provider
  and the boundary cannot be changed by any role that carries the boundary,
  and its state lives in its own bucket that only the platform admin role and
  break-glass principals can reach.
- **One Terraform root per environment.** Each environment has its own state
  file, backend key and inputs, so a staging plan can never touch production
  resources. Shared code lives in `terraform/modules`.
- **S3 native locking, no DynamoDB table.** The backend's `dynamodb_table`
  option is deprecated in favour of `use_lockfile`.
- **Private subnets are /20s.** EKS gives every pod a VPC IP, so private
  subnets are sized for pod density, not node count.
- **Certificate validation waits are opt-in.** ACM can only validate after
  the parent domain delegates to the new zone, so `wait_for_certificate_validation`
  stays `false` until delegation is in place.

## Networking

- Public subnets hold only NAT gateways and, later, internet-facing load
  balancers. Nothing gets a public IP on launch.
- Private subnets hold EKS nodes and data services; they reach the internet
  only through NAT.
- Subnets carry the tags the AWS Load Balancer Controller uses to find them:
  `kubernetes.io/role/elb` on public, `kubernetes.io/role/internal-elb` on private.
- The default security group has every rule removed.
- VPC flow logs go to CloudWatch Logs with 90-day retention.
- The two environments' VPCs are not peered.

## Secrets

The landing zone holds no application secrets. Terraform state can contain
sensitive values, so each state bucket is encrypted with its environment's
KMS key, rejects uploads that request any other encryption, and refuses
non-TLS access. Each bucket denies access except for its environment's plan
and apply roles, the platform admin role, and
`state_break_glass_principal_arns` from the bootstrap root. The bootstrap's
own bucket admits only the platform admin role and break-glass.

## Known Limitations

- Each environment's `zone_name` is not committed yet; it is passed at plan
  time until the domains are decided.
- No CI job plans or applies these roots. Plans and applies are manual and
  follow the change-control process in the runbook.
- Staging uses one NAT gateway, so an AZ outage cuts staging egress.
- The account is shared with other projects; see the consequences in ADR-0004.
  Record changes in other projects' hosted zones cannot be blocked by tag, so
  plan review is the control there.
- Editing the permissions boundary needs a principal without it (the
  bootstrap operator or the account root).

## Key File Locations

| Path | What it holds |
|---|---|
| [`terraform/bootstrap/`](../terraform/bootstrap/) | State buckets, KMS keys, permissions boundary, GitHub OIDC and IAM roles |
| [`terraform/modules/network/`](../terraform/modules/network/) | VPC, subnets, NAT, flow logs |
| [`terraform/modules/dns/`](../terraform/modules/dns/) | Hosted zone and certificate |
| [`terraform/envs/staging/`](../terraform/envs/staging/) | Staging root and inputs |
| [`terraform/envs/production/`](../terraform/envs/production/) | Production root and inputs |
