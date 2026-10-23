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

variable "github_oidc_subject_prefix" {
  description = "Repository part of the GitHub OIDC `sub` claim, as GitHub issues it for this repository. Newer repositories use the immutable form `repo:OWNER@OWNER-ID/REPO@REPO-ID`; read it with `gh api repos/<owner>/<repo>/actions/oidc/customization/sub` (field `sub_claim_prefix`)."
  type        = string

  validation {
    condition     = startswith(var.github_oidc_subject_prefix, "repo:") && !endswith(var.github_oidc_subject_prefix, ":")
    error_message = "github_oidc_subject_prefix must start with repo: and must not end with a colon."
  }
}

variable "human_principal_arns" {
  description = "IAM users or roles that may assume openflows-platform-admin and openflows-readonly (with MFA)."
  type        = list(string)

  validation {
    condition     = length(var.human_principal_arns) > 0
    error_message = "At least one human principal is needed, or nobody can assume the admin role."
  }
}

variable "state_break_glass_principal_arns" {
  description = "Principals that keep access to every state bucket besides the environment's own roles. Without one, a bad bucket policy can lock everyone but the root user out."
  type        = list(string)

  validation {
    condition     = length(var.state_break_glass_principal_arns) > 0
    error_message = "Keep at least one break-glass principal on the state buckets."
  }
}

variable "noncurrent_version_retention_days" {
  description = "How long superseded state versions are kept before S3 expires them. State history is the recovery path for a bad apply."
  type        = number
  default     = 90
}
