variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "environment" {
  type = string
}

variable "certificate_arn" {
  type        = string
  description = "ACM certificate ARN for the ALB's HTTPS listener. Leave null for a lab/demo run (HTTP-only fallback) - never in real production, see modules/alb/README.md."
  default     = null
}
