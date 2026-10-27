terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # secret_string_wo needs a 6.x provider.
      version = ">= 6.0"
    }
    random = {
      source = "hashicorp/random"
      # Ephemeral random_password arrived in 3.7.
      version = ">= 3.7"
    }
  }
}
