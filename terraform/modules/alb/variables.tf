variable "name" {
  type        = string
  description = "Name prefix for the ALB and related resources."
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "Public subnet IDs for the ALB itself (min 2 for genuine HA)."

  validation {
    condition     = length(var.public_subnet_ids) >= 2
    error_message = "At least 2 public subnets are required for a highly-available ALB."
  }
}

variable "security_group_id" {
  type        = string
  description = "Security group ID for the ALB (see modules/security-groups)."
}

variable "target_port" {
  type        = number
  description = "Port the target group forwards traffic to on registered targets."
  default     = 8080
}

variable "health_check_path" {
  type    = string
  default = "/healthz"
}

variable "certificate_arn" {
  type        = string
  description = "ACM certificate ARN for the HTTPS listener. If null, only an HTTP listener is created (fine for a lab, not for production - see README)."
  default     = null
}

variable "enable_deletion_protection" {
  type        = bool
  description = "Whether the ALB itself is protected from accidental deletion. Recommended true for production - see interview-questions/01-terraform-core.md Question 3."
  default     = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
