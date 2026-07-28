terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }

  # Reuses the SAME backend bucket/lock-table built in Lab 2's bootstrap,
  # with a distinct state key so it doesn't collide with Lab 2's own state.
  backend "s3" {
    key     = "lab-03/terraform.tfstate"
    encrypt = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      ManagedBy = "terraform"
      Lab       = "lab-03-state-locking"
    }
  }
}
