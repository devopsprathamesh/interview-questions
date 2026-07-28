# Bootstrap configuration - deliberately uses LOCAL state only.
# This configuration creates the S3 bucket and DynamoDB lock table that every
# OTHER configuration in this repository will use as its remote backend.
# It cannot use that backend for itself - see README.md for why, and for how
# to safely store this bootstrap state once it exists.

terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # No backend block here, intentionally. Local state only for this configuration.
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      ManagedBy = "terraform"
      Lab       = "lab-02-remote-state-bootstrap"
      Purpose   = "terraform-state-backend"
    }
  }
}
