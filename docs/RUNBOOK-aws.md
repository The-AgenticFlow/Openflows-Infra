# AWS Foundation Runbook

How to operate the Terraform-managed AWS foundation. What it contains and
why is in [ARCHITECTURE-aws.md](ARCHITECTURE-aws.md).

## Common Operations

### Working in an environment by hand

The pipeline applies every environment change. Work by hand only to
investigate or repair, as `openflows-platform-admin` (see "Assuming the
OpenFlows roles"). Each environment is its own root. Initialise it against its own
state bucket, then plan with the inputs that are not committed yet:

```bash
cd terraform/envs/staging
terraform init -backend-config="bucket=openflows-tfstate-staging-<account-id>"
terraform plan -var="zone_name=<staging-domain or empty>" -out=tfplan
```

Use `terraform/envs/production` and the production bucket for production.
Never copy a plan file between environments, and never commit one: plan
files can contain secret values.

### Change control

Changes reach AWS only through [`.github/workflows/terraform.yml`](../.github/workflows/terraform.yml):

1. A pull request runs `fmt`, `validate`, trivy and the IAM cases, then plans
   staging and production with the read-only plan roles and comments a
   summary per environment (resource lines and totals only).
2. A reviewer other than the author approves and merges it.
3. The merge to `main` applies staging. The job plans, refuses any delete or
   replace, then applies that same plan. A run skips its apply when a later
   commit on `main` changes Terraform or this workflow, so an older merge
   never reverts a newer one; a later docs-only commit does not cause a skip.
4. To release to production, tag the `main` commit that staging already runs
   and push the tag: `git tag v<version> <commit>` then `git push origin v<version>`.
   Only `v*` tags can assume the production apply role, and only the highest
   `v*` tag applies; an older tag pushed later is skipped.
5. A plan that shows an unexpected destroy or replace stops the change until
   the cause is understood. A deliberate removal needs its own reviewed change
   and a manual apply as the platform admin role.

Set an environment's domain with the `ZONE_NAME_STAGING` or
`ZONE_NAME_PRODUCTION` repository variable. While it is empty, the
environment has no hosted zone or certificate.

### State ownership

| State | Bucket | Who may write it |
|---|---|---|
| Bootstrap | `openflows-tfstate-bootstrap-<account-id>` | Platform admin role (read) and break-glass principals |
| Staging | `openflows-tfstate-staging-<account-id>` | Staging plan and apply roles, platform admin role, break-glass principals |
| Production | `openflows-tfstate-production-<account-id>` | Production plan and apply roles, platform admin role, break-glass principals |

Each bucket's policy denies every other principal. The allow-list is built
from the roles in `terraform/bootstrap`, plus `state_break_glass_principal_arns`
in its `terraform.tfvars`. Keep at least one break-glass principal there, or a
bad policy can only be fixed by the account root.

### Assuming the OpenFlows roles

Human access goes through two roles, both requiring MFA:

| Role | Use it for |
|---|---|
| `openflows-readonly` | Looking around, day to day |
| `openflows-platform-admin` | Manual plans and applies, break-glass fixes |

Add a profile per role to `~/.aws/config`, with your IAM user's profile as
the source and your MFA device as `mfa_serial`. The CLI asks for the MFA code
when it assumes the role:

```ini
[profile openflows-admin]
role_arn       = arn:aws:iam::<account-id>:role/openflows/openflows-platform-admin
source_profile = <your-iam-user-profile>
mfa_serial     = arn:aws:iam::<account-id>:mfa/<your-mfa-device>
region         = eu-west-1
```

Both roles carry the permissions boundary, so they cannot touch other
projects' IAM roles, buckets or untagged resources. They also cannot change
the bootstrap's own roles, the GitHub OIDC provider or the boundary: apply
`terraform/bootstrap` as a principal without the boundary (the bootstrap
user before hand-over, an organization administrator, or the account root).

### Bootstrap (first time only)

The state buckets and the pipeline's roles have to exist before any other
root can use them, so the bootstrap is the one apply a person runs by hand.
After it, every change goes through the pipeline and the operator's
administrator rights come off.

```mermaid
flowchart LR
    U["Operator IAM user, admin, MFA session"] -->|"1. apply bootstrap"| BOOT["Buckets, boundary, OIDC provider, roles"]
    BOOT -->|"2. migrate state"| BB[("Bootstrap state bucket")]
    BOOT -->|"3. outputs to repo variables"| GH["GitHub Actions"]
    GH -->|"4. pipeline applies"| ENV["Staging, then production"]
    ENV -->|"7a. add SSO admin as break-glass"| BG["State bucket allow-lists"]
    BG -->|"7b. remove admin, deactivate key"| U2["Operator assumes roles only"]
```

1. As an IAM user with administrator rights, in an MFA session (for
   example from `aws sts get-session-token --serial-number <mfa-arn> --token-code <code>`),
   create the buckets, keys, boundary and roles. The committed backend points
   at a bucket that does not exist yet, so start on local state with a
   temporary override file (ignored by git). Review the plan and run the IAM
   cases first (see "Testing the permissions boundary"); every resource must
   be named `openflows-*`.

   ```bash
   cd terraform/bootstrap
   printf 'terraform {\n  backend "local" {}\n}\n' > backend_override.tf
   terraform init
   terraform plan -out=tfplan
   terraform apply tfplan
   ```

2. Move the state into the bootstrap bucket: remove the override, then
   migrate to the committed S3 backend. Answer the copy prompt yourself: if
   Terraform reports that the bucket already holds state, stop and compare
   the two before overwriting anything.

   ```bash
   rm backend_override.tf
   terraform init -migrate-state \
     -backend-config="bucket=openflows-tfstate-bootstrap-<account-id>"
   terraform plan    # must report: No changes
   ```

3. Check the state object is encrypted with the bootstrap KMS key
   (`aws s3api head-object --bucket openflows-tfstate-bootstrap-<account-id> --key terraform.tfstate`
   shows `aws:kms` and that key), then delete the local `terraform.tfstate`,
   `terraform.tfstate.backup` and `tfplan`: they hold the full state. Rerun
   the IAM cases against the real roles with
   `python3 tests/iam_policy_tests.py tests/staging-apply-cases.json --principal <staging-apply-role-arn>`.
4. Set the repository variables the pipeline reads (Settings, Secrets and
   variables, Actions, Variables). None of them is secret. Read each value
   with `terraform output -json <output>` in `terraform/bootstrap`:

   | Variable | Value |
   |---|---|
   | `AWS_ACCOUNT_ID` | The account ID, as in `terraform.tfvars` |
   | `AWS_REGION` | `eu-west-1` |
   | `AWS_ROLE_STAGING_PLAN`, `AWS_ROLE_PRODUCTION_PLAN` | `terraform_plan_role_arns`, per environment |
   | `AWS_ROLE_STAGING_APPLY`, `AWS_ROLE_PRODUCTION_APPLY` | `terraform_apply_role_arns`, per environment |
   | `TF_STATE_BUCKET_STAGING`, `TF_STATE_BUCKET_PRODUCTION` | `state_bucket_names`, per environment |
   | `ZONE_NAME_STAGING`, `ZONE_NAME_PRODUCTION` | Optional. The environment's domain; leave unset to skip DNS |

5. Merge to `main` to let the pipeline apply staging, then push a `v*` tag to
   apply production (see "Change control").
6. Delegate each environment's domain: add the `name_servers` output as NS
   records at the parent domain. Then set `wait_for_certificate_validation = true`
   and apply again so the certificate is issued.
7. Hand over from the bootstrap user to the roles. Add
   the account's SSO administrator role to `state_break_glass_principal_arns`
   and apply bootstrap: the buckets' explicit deny would otherwise block it
   too, leaving only the account root to recover a broken policy. Then remove
   `AdministratorAccess` from the bootstrap user and give it only this policy,
   so it can assume the OpenFlows roles with MFA:

   ```json
   {
     "Version": "2012-10-17",
     "Statement": [{
       "Effect": "Allow",
       "Action": "sts:AssumeRole",
       "Resource": [
         "arn:aws:iam::<account-id>:role/openflows/openflows-platform-admin",
         "arn:aws:iam::<account-id>:role/openflows/openflows-readonly"
       ],
       "Condition": { "Bool": { "aws:MultiFactorAuthPresent": "true" } }
     }]
   }
   ```

   Deactivate the bootstrap user's access key once the pipeline runs.

### Testing the permissions boundary

`terraform/bootstrap/tests/` holds the access cases the boundary and the
environment isolation must satisfy: what an apply role can never do (reach
into the other environment, edit its own guard rails, change or relabel other
projects' resources) and what it must still be able to do. Run them after any
change to `boundary.tf` or `roles.tf`, before opening the PR. They use AWS's
policy simulator, which evaluates the documents and changes nothing.

```bash
cd terraform/bootstrap
terraform plan -out=tfplan
tests/render-policies.sh tfplan
python3 tests/iam_policy_tests.py tests/staging-apply-cases.json
```

Every case must pass. Add a case for each new rule, both the deny it is meant
to cause and an allow that must keep working. Once the roles exist, add
`--principal <staging-apply-role-arn>` to test the live role's attached
policies and boundary instead of the rendered files.

### Break-glass access

Use break-glass access only when the normal deployer path is broken or
locked out, for example a bucket policy that denies everyone.

1. Sign in as the account's break-glass administrator. Its credentials are
   held outside this repository and are never used for routine work.
2. Fix the blocking problem with the smallest possible change. For a
   lockout, remove the `DenyPrincipalsOutsideEnvironment` statement from the
   bucket policy.
3. Restore the intended state from Terraform right away, then record what
   happened and why in an issue.

> [!WARNING]
> A break-glass session can reach both environments. Nothing done in it is
> reviewed, so keep it short and bring the change back into Terraform.

## Backup & Restore

State buckets are versioned and keep superseded versions for 90 days. To
recover from a bad state write, list the versions and restore the last good
one:

```bash
aws s3api list-object-versions \
  --bucket openflows-tfstate-staging-<account-id> \
  --prefix envs/staging/terraform.tfstate
aws s3api copy-object \
  --bucket openflows-tfstate-staging-<account-id> \
  --key envs/staging/terraform.tfstate \
  --copy-source "openflows-tfstate-staging-<account-id>/envs/staging/terraform.tfstate?versionId=<version-id>"
```

The buckets have `prevent_destroy`, so Terraform refuses to delete them.

## Monitoring & Alerts

- VPC flow logs are in CloudWatch Logs, in the log group the VPC module
  creates for each environment.
- No alerts are defined on the foundation yet.
- The nightly `Terraform` workflow run plans both environments and fails on
  drift: a red nightly run means AWS no longer matches `main`. Read its plan
  summary, then either revert the manual change or bring it into Terraform.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `AWS account ID not allowed` | Credentials for a different account | Switch credentials; `allowed_account_ids` stops the run on purpose |
| `Error acquiring the state lock` | An interrupted run left its `.tflock` object | Confirm no run is active, then `terraform force-unlock <lock-id>` |
| `AccessDenied` on the state bucket | Principal is not one of the environment's roles or a break-glass principal | Use the environment's role, or add the principal to `state_break_glass_principal_arns` and apply bootstrap |
| `AccessDenied ... explicit deny in a permissions boundary` | The action touches IAM outside `/openflows/`, a bucket not named `openflows-*`, a resource not tagged `Project=openflows`, or a bootstrap-managed role | Name and tag the resource as OpenFlows; for bootstrap changes, apply as a principal without the boundary |
| `AccessDenied ... explicit deny in an identity-based policy` from an apply role | The resource, IAM path or bucket belongs to the other environment | Tag the resource with the right `Environment`, put roles under `/openflows/<env>/`, name buckets `openflows-<env>-*` |
| GitHub Actions `Not authorized to perform sts:AssumeRoleWithWebIdentity` | The job runs from a ref the role does not trust, or sets `environment:` | Plans: pull requests or `main`. Staging apply: `main`. Production apply: a `v*` tag. Do not set `environment:` on these jobs |
| Apply hangs on `aws_acm_certificate_validation` | The parent domain does not delegate to the zone yet | Add the NS records, or set `wait_for_certificate_validation = false` |

## Rollback Procedure

Revert the PR, re-plan the affected environment and apply. If an apply left
state wrong, restore the previous state version as in "Backup & Restore",
then plan to see what the real infrastructure looks like before applying.

## Escalation

If a plan shows destroys or replacements nobody can explain, or production
is affected, stop and raise it with the platform owners before applying
anything else.
