terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # The pinned VPC module needs at least 6.28.
      version = ">= 6.28"
    }
  }
}
