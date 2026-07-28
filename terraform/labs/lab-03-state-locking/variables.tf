variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "tf-locking-lab"
}

variable "apply_delay_seconds" {
  type        = number
  description = "Artificial delay during apply, giving you a real window to attempt a concurrent second apply before this one finishes."
  default     = 45
}

variable "run_marker" {
  type        = string
  description = "Arbitrary marker string identifying this apply run; change it between runs to force a new artificial delay window."
  default     = "1"
}
