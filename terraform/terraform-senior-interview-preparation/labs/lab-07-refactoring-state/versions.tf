terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    key     = "lab-07/terraform.tfstate"
    encrypt = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      ManagedBy = "terraform"
      Lab       = "lab-07-refactoring-state"
    }
  }
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "environments" {
  type        = list(string)
  description = "The list of environment names this configuration manages a parameter for."
  default     = ["dev", "staging", "production"]
}
