variable "name" {
  type        = string
  description = "Name for the security group."
}

variable "vpc_id" {
  type        = string
  description = "VPC ID the security group belongs to."
}

variable "description" {
  type        = string
  description = "Description for the security group."
  default     = "Managed by Terraform"
}

variable "ingress_rules" {
  type = map(object({
    from_port    = number
    to_port      = number
    protocol     = string
    cidr_blocks  = optional(list(string), [])
    allow_public = optional(bool, false)
  }))
  description = "Map of ingress rules, keyed by a descriptive rule name (e.g. \"https_from_alb\"). Any rule using 0.0.0.0/0 MUST set allow_public = true - a deliberate, reviewable escape hatch, never a silent default."
  default     = {}

  validation {
    condition = alltrue([
      for k, r in var.ingress_rules :
      r.allow_public || !contains(r.cidr_blocks, "0.0.0.0/0")
    ])
    error_message = "One or more ingress rules use cidr_blocks containing 0.0.0.0/0 without setting allow_public = true. This is a deliberate guard against accidental public exposure - see interview-questions/01-terraform-core.md Question 2."
  }
}

variable "egress_rules" {
  type = map(object({
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = optional(list(string), ["0.0.0.0/0"])
  }))
  description = "Map of egress rules, keyed by a descriptive rule name. Defaults to no egress rules at all if left empty - explicit opt-in, not an implicit allow-all."
  default     = {}
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags."
}
