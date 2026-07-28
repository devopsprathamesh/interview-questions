variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "name" {
  type    = string
  default = "tf-eks-lab"
}

variable "cidr_block" {
  type    = string
  default = "10.43.0.0/16"
}

variable "availability_zones" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
}

variable "kubernetes_version" {
  type    = string
  default = "1.29"
}

variable "node_instance_types" {
  type        = list(string)
  description = "Kept deliberately small/cheap for a lab. t3.medium is the minimum EKS-recommended size in practice."
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "lab_operator_cidr" {
  type        = string
  description = "Your own IP as a /32 (e.g. \"203.0.113.5/32\"), so the public API endpoint isn't reachable from the entire internet. Find yours with: curl -s ifconfig.me"
  default     = "0.0.0.0/0" # deliberately requires override - see terraform.tfvars.example
}
