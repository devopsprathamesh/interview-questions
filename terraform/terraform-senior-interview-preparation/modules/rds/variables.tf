variable "name" {
  type        = string
  description = "Identifier prefix for the RDS instance and related resources."
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs for the DB subnet group (min 2 for multi-AZ support)."

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "At least 2 subnets (different AZs) are required, even if multi_az is false, to support a future failover."
  }
}

variable "allowed_security_group_ids" {
  type        = list(string)
  description = "Security group IDs allowed to reach the database port (e.g. the app tier's security group). Never leave empty in a real deployment."
  default     = []
}

variable "engine" {
  type    = string
  default = "postgres"
}

variable "engine_version" {
  type    = string
  default = "16"
}

variable "instance_class" {
  type        = string
  description = "This module deliberately does not default to anything larger than db.t3.small - see interview-questions/13-governance.md Question 112 on right-sizing non-production databases."
  default     = "db.t3.small"
}

variable "allocated_storage" {
  type    = number
  default = 20
}

variable "multi_az" {
  type        = bool
  description = "Whether to run a synchronous standby in a second AZ - genuine HA within a region, NOT disaster recovery across regions. See interview-questions/11-ha-dr.md Question 103."
  default     = false
}

variable "deletion_protection" {
  type        = bool
  description = "Whether the instance is protected from accidental deletion - see interview-questions/01-terraform-core.md Question 3 for the two-step process to safely decommission a protected resource later."
  default     = true
}

variable "backup_retention_period" {
  type    = number
  default = 7
}

variable "tags" {
  type    = map(string)
  default = {}
}
