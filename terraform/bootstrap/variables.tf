variable "aws_account_id" {
  description = "AWS account that hosts both environments. Applying against any other account fails."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be a 12-digit AWS account ID."
  }
}

variable "region" {
  description = "AWS region for the state buckets and keys."
  type        = string
  default     = "eu-west-1"
}

variable "environments" {
  description = "Environments that get their own state bucket and KMS key. Staging and production are the only environments in scope."
  type        = set(string)
  default     = ["staging", "production"]
}

variable "state_admin_principal_arns" {
  description = "Per environment, the IAM principal ARNs allowed to read and write that environment's state, beyond the account's own administrators. Deployer roles are added here once they exist."
  type        = map(list(string))
  default     = {}
}

variable "noncurrent_version_retention_days" {
  description = "How long superseded state versions are kept before S3 expires them. State history is the recovery path for a bad apply."
  type        = number
  default     = 90
}
