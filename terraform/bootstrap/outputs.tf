output "state_bucket_names" {
  description = "State bucket per environment. Pass it to `terraform init -backend-config=bucket=...` in that environment's root."
  value       = { for env, bucket in aws_s3_bucket.state : env => bucket.bucket }
}

output "state_kms_key_arns" {
  description = "KMS key encrypting each environment's state."
  value       = { for env, key in aws_kms_key.state : env => key.arn }
}
