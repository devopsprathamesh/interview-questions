variable "name" {
  type        = string
  description = "Name prefix applied to every resource this module creates."

  validation {
    condition     = can(regex("^[a-z0-9-]{1,40}$", var.name))
    error_message = "name must be 1-40 characters, lowercase letters, numbers, and hyphens only."
  }
}

variable "cidr_block" {
  type        = string
  description = "IPv4 CIDR block for the VPC, e.g. 10.0.0.0/16."

  validation {
    condition     = can(cidrnetmask(var.cidr_block))
    error_message = "cidr_block must be a valid IPv4 CIDR block, e.g. 10.0.0.0/16."
  }
}

variable "availability_zones" {
  type        = list(string)
  description = "List of availability zone names to spread subnets across, e.g. [\"us-east-1a\", \"us-east-1b\"]. Order matters only for CIDR-offset assignment, not identity - identity is by AZ name via for_each."

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least 2 availability zones are required for a genuinely highly-available VPC."
  }
}

variable "nat_strategy" {
  type        = string
  description = "NAT gateway strategy: 'none' (no NAT, private subnets have no internet egress), 'single' (one shared NAT gateway - cheaper, single point of failure), or 'per_az' (one NAT gateway per AZ - higher availability, higher cost)."
  default     = "single"

  validation {
    condition     = contains(["none", "single", "per_az"], var.nat_strategy)
    error_message = "nat_strategy must be one of: none, single, per_az."
  }
}

variable "enable_s3_endpoint" {
  type        = bool
  description = "Whether to create a Gateway VPC endpoint for S3 (free, reduces NAT data-processing cost for S3-bound traffic)."
  default     = true
}

variable "tags" {
  type        = map(string)
  description = "Additional tags applied to every resource in this module."
  default     = {}
}
