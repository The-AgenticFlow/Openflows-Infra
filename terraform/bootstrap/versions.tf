# Bootstrap root: creates the state buckets, boundary and roles every other root
# uses. Its own state lives in the bootstrap state bucket it creates
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

  # Partial config: pass the bucket at init time. No `encrypt` flag: it would
  # force AES256 instead of the bucket's KMS key.
  backend "s3" {
    key          = "terraform.tfstate"
    region       = "eu-west-1"
    use_lockfile = true
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
