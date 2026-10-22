# Bootstrap root: creates the remote state buckets every other root uses.
# It starts on local state and is migrated into the production state bucket
# (see docs/RUNBOOK-aws.md, "Bootstrap").

terraform {
  # 1.11 is the first release where S3 native state locking (use_lockfile) is GA.
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.70"
    }
  }
}

provider "aws" {
  region              = var.region
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = {
      Project    = "openflows"
      ManagedBy  = "terraform"
      Repository = "Openflows-Infra"
      Stack      = "bootstrap"
    }
  }
}
