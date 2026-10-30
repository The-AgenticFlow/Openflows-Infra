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
| State | One encrypted, versioned S3 bucket per environment and one for the bootstrap, S3 native locking |
| Networks | `10.20.0.0/16` staging, `10.30.0.0/16` production |
| Domains | `trial.openflows.dev` staging, `app.openflows.dev` production |
| Kubernetes | EKS cluster `openflows-staging`, private API endpoint; production not built yet |
| CI identity | GitHub Actions OIDC, one plan role and one apply role per environment |
| Human access | `openflows-platform-admin` and `openflows-readonly`, both MFA only |
| Apply path | GitHub Actions: plan on pull requests, staging on `main`, production on `v*` tags |

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
            SNET["VPC 10.20.0.0/16, Route 53 zone, certificate, EKS"]
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
    Pub --> NAT[NAT: gateway in production, t4g.micro instance in staging]
    Priv[Private subnets, one /20 per AZ] -->|egress| NAT
    Pub -.->|future| ALB[HTTPS load balancer]
    ALB -.-> Priv
```

Inside the staging VPC, the EKS control plane is reachable only from the
private subnets. Nodes run in one private subnet. The VPC CNI uses the node
role (`AmazonEKS_CNI_Policy`); every other add-on that calls AWS gets its own
role through Pod Identity:

```mermaid
flowchart LR
    CS["CloudShell VPC environment"] -->|"cluster-admin SG, access entry"| API["EKS API, private endpoint"]
    LAP["Laptop"] -->|"SSM port forward"| TUN["admin-tunnel instance"]
    TUN -->|"cluster-admin SG"| API
    TF["Apply role"] -->|"EKS APIs only"| API
    API --> NG["Managed node group, Spot, one AZ"]
    NG --> CNI["VPC CNI"]
    CNI -->|node role| NR["openflows-staging-node"]
    NG --> EBS["EBS CSI driver"]
    NG --> DNS["ExternalDNS"]
    EBS -->|Pod Identity| EBSR["openflows-staging-ebs-csi"]
    DNS -->|Pod Identity| DNSR["openflows-staging-external-dns"]
    DNSR --> ZONE[("Route 53 zone")]
```

## Version Matrix

| Component | Version | Pinned in | Upgrade notes |
|---|---|---|---|
| Terraform | `>= 1.11` | [`terraform/envs/staging/versions.tf`](../terraform/envs/staging/versions.tf) and the other roots | 1.11 is the first release with GA S3 native state locking (`use_lockfile`) |
| AWS provider | `~> 6.70` | [`terraform/envs/staging/versions.tf`](../terraform/envs/staging/versions.tf), [`terraform/bootstrap/versions.tf`](../terraform/bootstrap/versions.tf) | Modules require `>= 6.59`, the floor of the pinned EKS module |
| Terraform CLI in CI | `1.15.8` | [`.github/workflows/terraform.yml`](../.github/workflows/terraform.yml) | Keep at or above the `required_version` floor |
| Trivy in CI | `0.76.1` | [`.github/workflows/terraform.yml`](../.github/workflows/terraform.yml) | Release tarball verified against its checksums file |
| `actions/checkout`, `hashicorp/setup-terraform`, `aws-actions/configure-aws-credentials` | `v7.0.1`, `v4.0.1`, `v6.3.0` | [`.github/workflows/terraform.yml`](../.github/workflows/terraform.yml) | Pinned by commit SHA; check inputs in the new version's `action.yml` before bumping |
| `terraform-aws-modules/vpc/aws` | `6.7.3` | [`terraform/modules/network/main.tf`](../terraform/modules/network/main.tf) | Read the module changelog before bumping; input names change across majors |
| `terraform-aws-modules/eks/aws` | `21.29.0` | [`terraform/modules/eks/main.tf`](../terraform/modules/eks/main.tf) | Recheck what it creates against the boundary before bumping (IAM paths, tags, log group name) |
| Node AMI (EKS optimized AL2023) | `1.37.1-20261023` | [`terraform/envs/staging/terraform.tfvars`](../terraform/envs/staging/terraform.tfvars) | Bumping it rolls the nodes; latest is `aws ssm get-parameter --name /aws/service/eks/optimized-ami/1.37/amazon-linux-2023/x86_64/standard/recommended/release_version` |
| Kubernetes (EKS) | `1.37` | [`terraform/envs/staging/terraform.tfvars`](../terraform/envs/staging/terraform.tfvars) | Standard support ends 2027-12-01; bump the add-on versions in the same change |
| EKS add-ons | `vpc-cni` `v1.22.4-eksbuild.3`, `coredns` `v1.14.7-eksbuild.11`, `kube-proxy` `v1.37.0-eksbuild.22`, `eks-pod-identity-agent` `v1.3.10-eksbuild.3`, `aws-ebs-csi-driver` `v1.67.1-eksbuild.1`, `metrics-server` `v0.9.0-eksbuild.13`, `external-dns` `v0.23.0-eksbuild.2` | [`terraform/modules/eks/main.tf`](../terraform/modules/eks/main.tf) | Each is the default for the Kubernetes version; list with `aws eks describe-addon-versions --kubernetes-version <v>` |
| Argo CD (Helm chart `argo-cd`) | `10.11.1` (Argo CD `v3.5.6`) | [`docs/RUNBOOK-aws.md`](RUNBOOK-aws.md) "Bootstrapping Argo CD", values in [`gitops/argocd/values-staging.yaml`](../gitops/argocd/values-staging.yaml) | Installed by hand; upgrade with the same `helm upgrade` command and the new version |
| AWS Load Balancer Controller chart | `3.6.1` | [`gitops/staging/apps/aws-load-balancer-controller.yaml`](../gitops/staging/apps/aws-load-balancer-controller.yaml) | Bump together with its IAM policy below |
| External Secrets chart | `2.13.0` | [`gitops/staging/apps/external-secrets.yaml`](../gitops/staging/apps/external-secrets.yaml) | Serves `external-secrets.io/v1`; check the CRD version before a major bump |
| OpenFlows workspace image (bootstrap Job) | `1.3.3`, pinned by digest | [`gitops/staging/openflows-bootstrap/bootstrap.yaml`](../gitops/staging/openflows-bootstrap/bootstrap.yaml) | Carries the `openflows` binary and the templates it pushes; bump with the chart's `workspace.image` |
| OpenFlows Manager chart | `0.1.0` | [`charts/openflows-manager/Chart.yaml`](../charts/openflows-manager/Chart.yaml), values in [`gitops/staging/apps/openflows-manager.yaml`](../gitops/staging/apps/openflows-manager.yaml) | Deployed as its own Argo CD app |
| OpenFlows Manager image | `develop-ce95142`, pinned by digest | [`gitops/staging/apps/openflows-manager.yaml`](../gitops/staging/apps/openflows-manager.yaml) | Published by the `Docker Publish Manager` workflow in the `openflows` repository; deploy by digest, bump tag and digest together |
| Coder version the Manager expects | `v2.37.1` (the Manager's own default is `v2.37.3`) | `OPENFLOWS_CODER_VERSION_BASELINE` in the same file | Must match the Coder that runs; raise both when Coder is upgraded |
| OpenFlows chart | `0.1.4` (Coder `v2.37.1`, Postgres `16-alpine`, Redis `7-alpine`) | [`charts/openflows/Chart.yaml`](../charts/openflows/Chart.yaml), [`charts/openflows/values.yaml`](../charts/openflows/values.yaml) | Staging values in [`gitops/staging/apps/openflows.yaml`](../gitops/staging/apps/openflows.yaml) |
| AWS Load Balancer Controller IAM policy | `v3.6.1`, without Shield and WAF writes | [`terraform/modules/eks/policies/aws-load-balancer-controller.json`](../terraform/modules/eks/policies/aws-load-balancer-controller.json) | Must match the controller chart version Argo CD installs; re-apply the removal of `shield:*Protection` and `wafv2`/`waf-regional` `*WebACL` writes when bumping |

## Components

| Component | Type | Source | Purpose |
|---|---|---|---|
| State buckets | S3 | `terraform/bootstrap` | One per environment plus one for the bootstrap: versioned, KMS-only uploads, public access blocked, TLS only |
| State keys | KMS | `terraform/bootstrap` | One customer-managed key per state bucket, yearly rotation |
| VPC | VPC module | `terraform/modules/network` | Public and private subnets across three AZs with their own route tables, flow logs to CloudWatch |
| Manager pod role | `openflows-<env>-manager`, Pod Identity | [`terraform/modules/app-secrets/policies/manager.json.tftpl`](../terraform/modules/app-secrets/policies/manager.json.tftpl) | Create, describe, read, write and delete secrets named `openflows/<env>/manager/*`, nothing else. The role's cases are in `terraform/modules/eks/tests/manager-cases.json` |
| NAT | VPC module, `nat-instance.tf` | `terraform/modules/network` | Private subnet egress. Production: one NAT gateway per AZ. Staging (`nat_mode = "instance"`): one self-patching `t4g.micro` (dnf runs out of memory on a nano) with an Elastic IP on its own ENI, no instance role |
| Off-hours node schedule | EventBridge Scheduler, `openflows-<env>-node-schedule` role | `terraform/modules/eks/schedule.tf` | Staging only: sets the node group's desired size to 0 at 20:00 and back at 07:00 on weekdays (Africa/Douala) |
| Hosted zone | Route 53 | `terraform/modules/dns` | Public DNS for the environment's domain |
| Certificate | ACM | `terraform/modules/dns` | Wildcard certificate for the HTTPS ingress, validated through the zone |
| Permissions boundary | IAM policy | `terraform/bootstrap` | Ceiling on every OpenFlows role: IAM under `/openflows/` only, `openflows-*` buckets only, no changes to resources not tagged `Project=openflows`, secrets only by name (`openflows/<env>/...`) |
| GitHub OIDC provider | IAM | `terraform/bootstrap` | Lets GitHub Actions assume AWS roles without stored keys |
| `openflows-<env>-terraform-plan` | IAM role | `terraform/bootstrap` | Read-only plans from pull requests and `main` |
| `openflows-<env>-terraform-apply` | IAM role | `terraform/bootstrap` | Applies: staging from `main`, production from `v*` tags; limited to its own environment's tags, IAM path and buckets |
| `openflows-platform-admin`, `openflows-readonly` | IAM roles | `terraform/bootstrap` | Human break-glass and day-to-day access, MFA required |
| EKS cluster | EKS module | `terraform/modules/eks` | Private API endpoint, access entries only (cluster-admin for platform admin, view for read-only), control plane audit and authenticator logs |
| Node group | EKS managed node group | `terraform/modules/eks` | x86 nodes on AL2023 with IMDSv2, hop limit 1, encrypted gp3 root volumes; launch template tags instances, volumes and ENIs |
| Add-ons | EKS add-ons | `terraform/modules/eks` | VPC CNI, CoreDNS, kube-proxy, Pod Identity agent, EBS CSI driver (default StorageClass), metrics-server, ExternalDNS |
| `openflows-<env>-cluster-admin`, `openflows-<env>-admin-tunnel` | Security group, EC2 instance | `terraform/modules/eks` | The only non-node path to the private API: CloudShell VPC environments and an SSM-managed `t4g.nano` that forwards a laptop port, no inbound ports |
| `openflows-<env>-ebs-csi`, `-external-dns`, `-aws-load-balancer-controller` | IAM roles | `terraform/modules/eks` | Pod Identity roles; ExternalDNS may only change the environment's zone |

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

### Role catalogue

Every role is per environment, carries the permissions boundary, lives under
`/openflows/<env>/` (bootstrap roles under `/openflows/`) and is tagged with
its `Environment`, which the boundary holds it to. Workloads get roles through
EKS Pod Identity, one service account per role; no workload role may hold
administrator rights, and CI checks that.

| Role | Assumed by | Scope | Status |
|---|---|---|---|
| `openflows-<env>-terraform-plan` | GitHub Actions: pull requests and `main` | Read-only, its state bucket | Live |
| `openflows-<env>-terraform-apply` (deployer) | GitHub Actions: `main` (staging), `v*` tags (production) | Its own environment's tags, IAM path and buckets | Live |
| `openflows-platform-admin`, `openflows-readonly` | Named humans with MFA (`human_principal_arns`) | Both environments; cluster-admin or view access entry | Live |
| `openflows-<env>-aws-load-balancer-controller` (ingress) | Pod `kube-system/aws-load-balancer-controller` | ALBs, target groups and security groups tagged ours | Live |
| `openflows-<env>-external-dns` (DNS) | Pod `external-dns/external-dns` | Records in the environment's zone only | Live |
| `openflows-<env>-ebs-csi` | Pod `kube-system/ebs-csi-controller-sa` | EBS volumes tagged ours | Live |
| `openflows-<env>-node`, cluster role, `-admin-tunnel`, `-vpc-flow-logs` | EC2, EKS, VPC Flow Logs | Node, control plane, SSM and log delivery duties | Live |
| `openflows-<env>-manager` | Manager pods | Its own secrets and data | With the Manager chart |
| `openflows-<env>-coder` | Coder pods | Its own secrets and data | With the Coder chart |
| `openflows-<env>-provisioner` | Provisioner pods | Workspace resources tagged with `Environment`, tenant ID and managed-by | With the AWS provisioner |
| `openflows-<env>-tenant-runtime` | Tenant workspaces | Its tenant's resources only | With tenant isolation |
| `openflows-<env>-external-secrets` | Pod `external-secrets/external-secrets` | Read `openflows/<env>/*` secrets only | Live (staging) |
| `openflows-<env>-observability` | Metrics and log agents | Write metrics and logs | With observability |
| `openflows-<env>-recovery` | Restore runs | Backup restore in its environment | With backup and restore |

The roles marked "With ..." are added through `workload_roles` in
[`terraform/modules/eks/workloads.tf`](../terraform/modules/eks/workloads.tf)
by the change that brings their workload, with the permissions that workload
proves it needs. Kubernetes RBAC is separate: humans get cluster-admin or view
through access entries; Coder gets a Role in the `openflows` namespace only
(`coder.rbac.namespaced`), so a compromised Coder cannot read other
namespaces' Secrets.

## Key Flows

### A GitHub Actions job gets AWS credentials

The job never holds a long-lived key. It trades a short-lived GitHub token for
one hour of AWS credentials, and AWS only agrees if the token comes from this
repository and from the ref the role trusts. The repository issues GitHub's
immutable subject format, which carries the owner and repository IDs, so a
renamed or recreated repository cannot reuse the trust.

```mermaid
sequenceDiagram
    autonumber
    participant Job as GitHub Actions job
    participant GHO as GitHub OIDC issuer
    participant STS as AWS STS
    participant Role as openflows-staging-terraform-apply
    participant State as Staging state bucket
    Job->>GHO: Request an ID token for audience sts.amazonaws.com
    GHO-->>Job: Token with sub repo:The-AgenticFlow@270928091/Openflows-Infra@1385687794:ref:refs/heads/main
    Job->>STS: AssumeRoleWithWebIdentity with the token
    STS->>Role: Check the trust policy: repository and ref match
    STS-->>Job: Temporary credentials, valid one hour
    Job->>State: Read state and write the lock file
    Job->>Job: terraform plan, then apply the saved plan
```

### A change goes from pull request to production

Every change reaches AWS the same way, and production only moves when someone
tags a release from `main`. Each apply plans and applies in one job, and stops
if the plan would delete or replace anything.

```mermaid
sequenceDiagram
    autonumber
    participant Dev as Engineer
    participant PR as Pull request
    participant CI as GitHub Actions
    participant S as Staging
    participant P as Production
    Dev->>PR: Open pull request
    PR->>CI: Checks, IAM cases, plan both environments (read-only roles)
    CI-->>PR: Plan summary per environment as a comment
    PR->>CI: Merge to main
    CI->>S: Plan, refuse destroys, apply with the staging apply role
    Dev->>CI: Push a v* release tag
    CI->>P: Plan, refuse destroys, apply with the production apply role
    CI->>S: Nightly plan of both environments flags drift
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
- **Secrets are protected by name, not by tag.** A role with an `Environment`
  tag can use only secrets named `openflows/<its environment>/...`, whatever
  their tags, so the Manager can create and manage its own untagged secrets
  under `openflows/<env>/manager/`. The two human roles have no `Environment`
  tag and carry the same limit across environments as an inline policy
  (`terraform/bootstrap/roles.tf`) that also forces them to tag every role they
  create, so no child role escapes the rule. CI fails a bootstrap change that
  adds any other untagged role. `ListSecrets`, `GetRandomPassword` and `DescribeSecret`
  stay open; `BatchGetSecretValue` needs `GetSecretValue` on every secret it
  returns ([AWS](https://docs.aws.amazon.com/secretsmanager/latest/apireference/API_BatchGetSecretValue.html)).
- **CI trust pinned to refs, not GitHub environments.** Private repositories
  on the current GitHub plan cannot protect environments, so the AWS trust
  policy is the gate: production apply only from `v*` tags.
- **Environments are isolated from each other, not only from other projects.**
  Each apply role can only change resources tagged with its own `Environment`,
  only change log groups under `/openflows/<env>/` or `/aws/eks/openflows-<env>/`, only write IAM under `/openflows/<env>/`, and only use `openflows-<env>-*`
  buckets and its own state bucket. Every other role an environment root
  creates (pod, node, cluster, flow-log roles) is tagged with its
  `Environment` and held to it by the boundary, which compares the
  resource's `Environment` tag with the caller's.
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
- **The cluster API is private.** Terraform needs only EKS APIs (cluster,
  access entries, add-ons, Pod Identity); people use the SSM tunnel or
  CloudShell's VPC environment; in-cluster changes go through Argo CD, whose
  UI is the day-to-day view. A public endpoint was tried: the shared account's
  organization refuses `eks:UpdateClusterConfig` for our apply role even
  though our IAM policy and boundary allow it, so the endpoint stays private.
- **Argo CD signs in through GitHub, limited to one team.** Its UI is on the
  shared ALB at `argocd.<zone>`. Dex admits only members of the org team
  `platform-admins` (the Coder owners) and maps them to Argo CD admin; there is
  no local admin and the default role grants nothing. No extra load balancer,
  no VPN.
- **Managed node groups, not Auto Mode.** Auto Mode launches and deletes
  instances and load balancers through our cluster role, which carries the
  boundary, and tags them only `eks:*`. Managed node groups act through an
  AWS service-linked role.
- **Everything the cluster creates is tagged at creation.** The boundary
  decides by `Project` and `Environment` tags, so the launch template, the VPC
  CNI (`ADDITIONAL_ENI_TAGS`), the EBS CSI driver (`extraVolumeTags`) and the
  Load Balancer Controller (`defaultTags`) all set them in the create call.
- **Pod Identity, not IRSA.** Associations are EKS API objects and need no
  per-cluster OIDC provider.
- **No customer KMS key for the cluster.** EKS envelope-encrypts all API data
  with an AWS-owned key on 1.28 and later.
- **One load balancer per environment.** Every Ingress joins the
  `openflows-<env>` IngressGroup, so all hosts share one ALB instead of
  paying for one each. The controller picks the ACM certificate matching the
  Ingress's TLS host and ExternalDNS writes the record.
- **Staging nodes are Spot, in one AZ.** Spot cuts node cost; one AZ keeps EBS
  volumes attachable when a node is replaced. Several instance types improve
  Spot availability; burstable types are avoided because unlimited CPU credits
  bill extra.
- **Staging runs only in working hours, behind a NAT instance.** The node
  group scales to zero on weekday evenings and weekends, a `t4g.micro` NAT
  instance replaces the NAT gateway, and ALBs span two AZs instead of three.
  Together these cut the staging run rate from about $245 to about $163 a month
  (eu-west-1 list prices, 2026-10). EventBridge Scheduler changes the node group
  through the EKS API rather than scheduled actions on its Auto Scaling group,
  because EKS leaves that group untagged and the boundary would block deleting
  them. Production keeps NAT gateways, three AZs and always-on nodes.

## Networking

- Public subnets hold only NAT (gateways or the staging NAT instance) and
  internet-facing load balancers. Nothing gets a public IP on launch; the NAT
  instance's Elastic IP is attached to its ENI explicitly.
- Private subnets hold EKS nodes and data services; they reach the internet
  only through NAT.
- Subnets carry the tags the AWS Load Balancer Controller uses to find them:
  `kubernetes.io/role/elb` on public, `kubernetes.io/role/internal-elb` on private.
  Only the first `alb_az_count` AZs' public subnets get the `elb` tag, since
  every AZ an ALB spans costs a public IPv4 address. The controller keeps an existing
  ALB's subnets, so the shared staging ALB is also pinned by the
  `alb.ingress.kubernetes.io/subnets` annotation on Coder's Ingress.
- Kubernetes NetworkPolicy is **not enforced** on the cluster. The VPC CNI can
  enforce it with the `enableNetworkPolicy` add-on setting, but the shared
  account's organization refuses `eks:UpdateAddon` (the same unexplained
  AccessDenied as for the API endpoint, for the pipeline role and for
  platform-admin), so the setting cannot be applied. The chart still renders a
  Postgres policy that admits only Coder on 5432 (`postgres.networkPolicy.enabled`);
  it takes effect once enforcement is available.
- The VPC's default security group, network ACL and route table are left as
  AWS creates them and are not used: workloads get their own security groups
  and subnets their own route tables.
- VPC flow logs go to CloudWatch Logs with 90-day retention.
- The two environments' VPCs are not peered.

## Secrets

Application secrets live in AWS Secrets Manager, encrypted with the account's
AWS-managed Secrets Manager key, and reach the cluster through External
Secrets, which reads them with the read-only `openflows-<env>-external-secrets`
Pod Identity role. No secret value is in Git, Helm values or Terraform state.

| Secrets Manager secret | Keys | Set by | Becomes Kubernetes Secret |
|---|---|---|---|
| `openflows/<env>/generated` | `postgresPassword`, `chatHookSecret` | Terraform, write-only (never in state) | `openflows-postgres`, `openflows-chat-hook` |
| `openflows/<env>/provided` | `githubClientSecret`, `coderSessionToken`, `argocdGithubClientSecret` | A person ("Setting the provided secrets" in the runbook) | `openflows`, `openflows-bootstrap`, `argocd-github` (in `argocd`) |
| `openflows/<env>/manager-db` | `password` | Terraform, write-only (never in state) | `openflows-manager` (with the database URL built from it) |
| `openflows/<env>/manager/*` | `github-client-secret`, `github-private-key`, `github-webhook-secret`, `coder-operator-token` by a person; `crypto-master-key`, `coder-hook-secret`, `coder-oauth-client-secret` by the Manager's `setup` | The Manager's own role reads them at runtime ("Deploying the Manager" in the OpenFlows runbook) | none: the Manager reads them from AWS, not through External Secrets |

Two secrets instead of one per value keep the cost near $0.80 a month per
environment. External Secrets refreshes them hourly. The AI gateway key is
entered in Coder's UI for now and is not stored in Secrets Manager.

Terraform state can contain
sensitive values, so each state bucket is encrypted with its environment's
KMS key, rejects uploads that request any other encryption, and refuses
non-TLS access. Each bucket denies access except for its environment's plan
and apply roles, the platform admin role, and
`state_break_glass_principal_arns` from the bootstrap root. The bootstrap's
own bucket admits only the platform admin role and break-glass.

## Known Limitations

- Coder runs with the `oauth2` experiment enabled (`coder.experiments` in the staging values), which the
  Manager needs to register its OAuth application. Coder marks experiments as not ready for production.
- The Manager runs against a Coder two patch versions older than the one it is
  tested with, and the Manager's hosted tenants need Coder organizations, which
  the free Coder edition lacks. Until Coder Premium or a different provisioning
  design is decided, the Manager runs but cannot create tenants.
- No runtime relay is deployed, so lifecycle hooks cannot reach tenant
  workspaces; the Manager's relay setting points at a service that does not exist.
- The Manager's database lives on the same single PostgreSQL instance as
  Coder's: one volume, one restore, no separate backup.

- Each environment's zone only works once the parent `openflows.dev` zone
  delegates to it with NS records. That parent zone lives in the Cloudflare
  account that registered the domain, outside this repository.
- The org's GitHub plan cannot protect environments or branches on this private
  repository, so production is gated by the release tag and the AWS trust
  policy, not by a required reviewer.
- NetworkPolicy objects are not enforced (see Networking), so pods can reach
  each other freely until enforcement is enabled or another policy engine is
  installed. Tenant isolation depends on this.
- Staging egress is one NAT instance with no failover: if it or its AZ fails,
  staging loses internet access until EC2 auto-recovery or a replacement
  brings it back.
- The default security group keeps AWS's default rules (traffic between its
  members). AWS creates it untagged, so the permissions boundary stops
  OpenFlows roles from adopting it, and it cannot be locked down from
  Terraform. Nothing is attached to it.
- The account is shared with other projects; see the consequences in ADR-0004.
  Record changes in other projects' hosted zones cannot be blocked by tag, so
  plan review is the control there.
- Editing the permissions boundary needs a principal without it (the
  bootstrap operator or the account root).
- The boundary is close to IAM's 6,144-character limit for managed policies
  (about 6,020, so about 120 characters of room). A role has one boundary, so
  a rule that does not fit needs the boundary split, for example into one per
  environment. Statement ids are kept short for this reason.
- Secrets outside `openflows/<env>/` are out of reach for OpenFlows roles, so a
  secret AWS creates for us under another name, such as an RDS-managed master
  password (`rds!...`), cannot be read by them. Choose another way to supply
  such a credential, or extend the name rule in the boundary, before relying on it.
- Staging runs one Spot node in one AZ: a Spot reclaim or AZ outage takes
  staging down until a replacement node starts. No cluster autoscaler runs, so
  the node count is whatever `node_desired_size` says.
- Staging is off on weekday evenings and weekends: Coder, workspaces and the
  Argo CD UI are down until the morning start or a manual start (runbook,
  "Off-hours node schedule").
- Argo CD itself is installed by hand once per cluster; everything it runs is
  GitOps from `gitops/<env>/`. Changes to its own values need a manual
  `helm upgrade`.

## Key File Locations

| Path | What it holds |
|---|---|
| [`terraform/bootstrap/`](../terraform/bootstrap/) | State buckets, KMS keys, permissions boundary, GitHub OIDC and IAM roles |
| [`terraform/modules/network/`](../terraform/modules/network/) | VPC, subnets, NAT, flow logs |
| [`terraform/modules/dns/`](../terraform/modules/dns/) | Hosted zone and certificate |
| [`gitops/staging/`](../gitops/staging/) | Argo CD Applications for staging: Load Balancer Controller, External Secrets, OpenFlows |
| [`gitops/argocd/`](../gitops/argocd/) | Argo CD Helm values |
| [`gitops/staging/openflows-secrets/`](../gitops/staging/openflows-secrets/) | Secret store and ExternalSecrets for OpenFlows |
| [`terraform/modules/app-secrets/`](../terraform/modules/app-secrets/) | Secrets Manager secrets, generated values write-only |
| [`terraform/modules/eks/`](../terraform/modules/eks/) | EKS cluster, node group, add-ons, Pod Identity roles, and the IAM cases for the in-cluster roles |
| [`terraform/envs/staging/`](../terraform/envs/staging/) | Staging root and inputs |
| [`terraform/envs/production/`](../terraform/envs/production/) | Production root and inputs |
