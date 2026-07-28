variable "aws_region" {
  type        = string
  description = "AWS region to deploy the lab resources into."
  default     = "us-east-1"
}

variable "project_name" {
  type        = string
  description = "Short project name used as a naming prefix for all resources."
  default     = "tf-core-lab"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.project_name))
    error_message = "project_name must be 3-20 characters, lowercase letters, numbers, and hyphens only."
  }
}

variable "environment" {
  type        = string
  description = "Environment name, used in tags and naming."
  default     = "sandbox"

  validation {
    condition     = contains(["sandbox", "dev", "staging"], var.environment)
    error_message = "environment must be one of: sandbox, dev, staging (this lab is not intended for production use)."
  }
}

variable "enable_versioning" {
  type        = bool
  description = "Whether to enable S3 bucket versioning. Demonstrates a conditional resource via count."
  default     = true
}
