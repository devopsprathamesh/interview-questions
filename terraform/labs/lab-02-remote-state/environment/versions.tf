terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Fill in bucket/dynamodb_table from the bootstrap module's outputs.
  # Deliberately left as a partial configuration - values are supplied via
  # `terraform init -backend-config=backend.hcl` (see backend.hcl.example)
  # so this file never hardcodes an environment-specific bucket name.
  backend "s3" {
    key     = "lab-02/environment/terraform.tfstate"
    encrypt = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      ManagedBy = "terraform"
      Lab       = "lab-02-remote-state-environment"
    }
  }
}
