terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
  # No provider block here by design - see docs/terraform-architecture.md Part A §1.
  # Consumers supply the provider configuration (default inheritance, or an
  # explicit alias for cross-account/region use) exactly like modules/vpc.
}
