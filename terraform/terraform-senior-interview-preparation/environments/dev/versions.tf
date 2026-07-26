terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Distinct backend key per environment - this is the actual isolation
  # mechanism, not a CLI workspace. See docs/terraform-architecture.md section 10.
  backend "s3" {
    key     = "environments/dev/terraform.tfstate"
    encrypt = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      ManagedBy   = "terraform"
      Environment = "dev"
    }
  }
}
