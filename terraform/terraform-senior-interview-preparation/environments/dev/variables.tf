variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "vpc_cidr" {
  type    = string
  default = "10.10.0.0/16"
}

variable "availability_zones" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
}

variable "vpc_module_version" {
  type        = string
  description = "Documents which module version this environment is pinned to when consumed from a registry. Using a relative path in this teaching repo; a real deployment would set version = \"~> X.Y\" instead."
  default     = "local"
}
