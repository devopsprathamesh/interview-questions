variable "aws_region" {
  type        = string
  description = "AWS region to create the state backend resources in."
  default     = "us-east-1"
}

variable "state_bucket_name" {
  type        = string
  description = "Globally-unique S3 bucket name for Terraform state. Must be unique across all of AWS."

  validation {
    condition     = can(regex("^[a-z0-9.-]{3,63}$", var.state_bucket_name))
    error_message = "state_bucket_name must be a valid S3 bucket name (lowercase letters, numbers, dots, hyphens, 3-63 chars)."
  }
}

variable "lock_table_name" {
  type        = string
  description = "DynamoDB table name used for Terraform state locking."
  default     = "terraform-state-lock"
}

variable "noncurrent_version_expiration_days" {
  type        = number
  description = "Days to retain noncurrent (overwritten) state versions before expiring them, balancing recovery capability against storage cost."
  default     = 90
}
