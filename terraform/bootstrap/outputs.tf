output "state_bucket_names" {
  description = "State bucket per environment. Pass it to `terraform init -backend-config=bucket=...` in that environment's root."
  value       = { for env, bucket in aws_s3_bucket.state : env => bucket.bucket }
}

output "state_kms_key_arns" {
  description = "KMS key encrypting each environment's state."
  value       = { for env, key in aws_kms_key.state : env => key.arn }
}

output "github_oidc_provider_arn" {
  description = "GitHub Actions OIDC provider."
  value       = aws_iam_openid_connect_provider.github.arn
}

output "terraform_plan_role_arns" {
  description = "Role per environment that GitHub Actions assumes for plans. Set as repository variables."
  value       = { for env, role in aws_iam_role.terraform_plan : env => role.arn }
}

output "terraform_apply_role_arns" {
  description = "Role per environment that GitHub Actions assumes for applies. Set as repository variables."
  value       = { for env, role in aws_iam_role.terraform_apply : env => role.arn }
}

output "platform_admin_role_arn" {
  description = "Break-glass administrator role, MFA required."
  value       = aws_iam_role.platform_admin.arn
}

output "readonly_role_arn" {
  description = "Day-to-day read-only role, MFA required."
  value       = aws_iam_role.readonly.arn
}

output "permissions_boundary_arn" {
  description = "Boundary every OpenFlows role must carry."
  value       = aws_iam_policy.boundary.arn
}
