terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Own state, own lifecycle - see docs/terraform-architecture.md §7. This
  # layer changes rarely and is the foundation everything else depends on.
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      ManagedBy = "terraform"
      Lab       = "lab-15-enterprise-capstone"
      Layer     = "foundation"
    }
  }
}
