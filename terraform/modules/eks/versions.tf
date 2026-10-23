terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # The pinned EKS module needs at least 6.59.
      version = ">= 6.59"
    }
  }
}
