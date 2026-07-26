variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "name" {
  type        = string
  description = "Name prefix for all resources in this lab."
  default     = "tf-networking-lab"
}

variable "cidr_block" {
  type        = string
  description = "VPC CIDR block."
  default     = "10.42.0.0/16"
}

variable "availability_zones" {
  type        = list(string)
  description = "AZs to spread the platform across. Two is the minimum for genuine HA."
  default     = ["us-east-1a", "us-east-1b"]
}

variable "nat_strategy" {
  type        = string
  description = "NAT gateway strategy - see modules/vpc for the full trade-off. 'single' is the cost-conscious default for this lab; try 'per_az' and 'none' too."
  default     = "single"
}

variable "enable_interface_endpoints" {
  type        = bool
  description = "Whether to create Interface VPC endpoints for ECR, CloudWatch Logs, and SSM (billed hourly + per-GB, but usually cheaper than the equivalent NAT data-processing charge, and keeps this traffic off the public internet entirely). The SSM endpoints are what let instances in private subnets be reached via Session Manager with no bastion host and no open SSH port at all - see README for the trade-off versus a traditional bastion."
  default     = true
}
