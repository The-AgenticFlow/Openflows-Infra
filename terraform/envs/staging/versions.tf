terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.70"
    }
  }

  # Partial config: the bucket name carries the account ID, so it is passed at
  # init time (docs/RUNBOOK-aws.md, "Working in an environment by hand").
  backend "s3" {
    key          = "envs/staging/terraform.tfstate"
    region       = "eu-west-1"
    use_lockfile = true
    # No `encrypt` flag on purpose: with it and no kms_key_id the backend sends
    # AES256, overriding the bucket's default KMS key. The bucket encrypts.
  }
}

provider "aws" {
  region              = var.region
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = {
      Project     = "openflows"
      Environment = local.environment
      ManagedBy   = "terraform"
      Repository  = "Openflows-Infra"
    }
  }
}
