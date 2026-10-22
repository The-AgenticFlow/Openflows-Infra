# AWS Foundation Runbook

How to operate the Terraform-managed AWS foundation. What it contains and
why is in [ARCHITECTURE-aws.md](ARCHITECTURE-aws.md).

## Common Operations

### Working in an environment

Each environment is its own root. Initialise it against its own state
bucket, then plan with the inputs that are not committed yet:

```bash
cd terraform/envs/staging
terraform init -backend-config="bucket=openflows-tfstate-staging-<account-id>"
terraform plan \
  -var="aws_account_id=<account-id>" \
  -var="zone_name=<staging-domain>" \
  -out=tfplan
```

Use `terraform/envs/production` and the production bucket for production.
Never copy a plan file between environments, and never commit one: plan
files can contain secret values.

### Change control

1. Every change starts as a PR against `main` with the plan output for each
   affected environment in the description.
2. A reviewer other than the author approves the PR.
3. After merge, apply the reviewed plan to staging first, check it, then
   plan and apply production.
4. A plan that shows an unexpected destroy or replace stops the change until
   the cause is understood.

### State ownership

| State | Bucket | Who may write it |
|---|---|---|
| Bootstrap | Production state bucket, key `bootstrap/terraform.tfstate` | Platform administrators only |
| Staging | `openflows-tfstate-staging-<account-id>` | Staging deployer and administrators |
| Production | `openflows-tfstate-production-<account-id>` | Production deployer and administrators |

Once the deployer roles exist, list them per environment in
`state_admin_principal_arns` in `terraform/bootstrap` and apply it. Each
bucket then denies every principal outside its list. Always include the
break-glass role, or the list locks administrators out.

### Bootstrap (first time only)

The state buckets have to exist before any other root can use them.

1. With administrator credentials for the account, create the buckets and
   keys on local state:

   ```bash
   cd terraform/bootstrap
   terraform init
   terraform apply -var="aws_account_id=<account-id>"
   ```

2. Move the bootstrap state into the production bucket. Add this block to
   `terraform/bootstrap/versions.tf`, then migrate:

   ```hcl
   backend "s3" {
     key          = "bootstrap/terraform.tfstate"
     region       = "eu-west-1"
     encrypt      = true
     use_lockfile = true
   }
   ```

   ```bash
   terraform init -migrate-state \
     -backend-config="bucket=openflows-tfstate-production-<account-id>"
   ```

3. Delete the local `terraform.tfstate` and its backup once the migration
   succeeds, and commit the backend block.
4. Initialise and apply each environment as in "Working in an environment".
5. Delegate each environment's domain: add the `name_servers` output as NS
   records at the parent domain. Then set `wait_for_certificate_validation = true`
   and apply again so the certificate is issued.

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

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `AWS account ID not allowed` | Credentials for a different account | Switch credentials; `allowed_account_ids` stops the run on purpose |
| `Error acquiring the state lock` | An interrupted run left its `.tflock` object | Confirm no run is active, then `terraform force-unlock <lock-id>` |
| `AccessDenied` on the state bucket | Principal missing from `state_admin_principal_arns` | Add the principal and apply bootstrap, or use break-glass on a lockout |
| Apply hangs on `aws_acm_certificate_validation` | The parent domain does not delegate to the zone yet | Add the NS records, or set `wait_for_certificate_validation = false` |

## Rollback Procedure

Revert the PR, re-plan the affected environment and apply. If an apply left
state wrong, restore the previous state version as in "Backup & Restore",
then plan to see what the real infrastructure looks like before applying.

## Escalation

If a plan shows destroys or replacements nobody can explain, or production
is affected, stop and raise it with the platform owners before applying
anything else.
