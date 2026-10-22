terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.70"
    }
  }

  # Partial config: the bucket name carries the account ID, so it is passed at
  # init time (docs/RUNBOOK-aws.md, "Working in an environment").
  backend "s3" {
    key          = "envs/production/terraform.tfstate"
    region       = "eu-west-1"
    encrypt      = true
    use_lockfile = true
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
