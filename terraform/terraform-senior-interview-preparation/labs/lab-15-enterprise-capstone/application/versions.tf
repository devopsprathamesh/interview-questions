terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Own state, distinct from foundation and platform - the layer that changes
  # most frequently gets its own, fastest-to-plan state. See
  # docs/terraform-architecture.md §7.
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      ManagedBy = "terraform"
      Lab       = "lab-15-enterprise-capstone"
      Layer     = "application"
    }
  }
}
