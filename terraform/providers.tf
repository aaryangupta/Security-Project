terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Profile is pinned so a missing AWS_PROFILE cannot deploy to the wrong account.
provider "aws" {
  region  = var.aws_region
  profile = "demo"
}
