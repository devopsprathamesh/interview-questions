variable "name" {
  type        = string
  description = "Name for the EKS cluster and prefix for related resources."

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{0,37}$", var.name))
    error_message = "name must start with a letter and be 1-38 characters (EKS's own naming limit)."
  }
}

variable "kubernetes_version" {
  type        = string
  description = "EKS control plane Kubernetes version. Verify current supported versions before setting - EKS deprecates old versions on a published schedule and does not support downgrading."
  default     = "1.29"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID to deploy the cluster and node group into."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for the control plane ENIs and node group. Private subnets are strongly recommended for the node group."

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "At least 2 subnets (in different AZs) are required for a genuinely available EKS control plane."
  }
}

variable "cluster_security_group_additional_rules" {
  type        = bool
  description = "Reserved for future use - EKS manages its own cluster security group by default (see docs/terraform-architecture.md and interview-questions/06-kubernetes-eks.md Question 57)."
  default     = false
}

variable "node_instance_types" {
  type        = list(string)
  description = "Instance types for the managed node group, in preference order."
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 3
}

variable "node_max_unavailable_percentage" {
  type        = number
  description = "Cap on concurrent node replacement during a managed node group update - see interview-questions/06-kubernetes-eks.md Question 55 for why this matters."
  default     = 25
}

variable "enable_pod_identity" {
  type        = bool
  description = "Whether to install the EKS Pod Identity Agent add-on - see interview-questions/06-kubernetes-eks.md Question 54 for the IRSA-vs-Pod-Identity decision."
  default     = true
}

variable "endpoint_public_access" {
  type        = bool
  description = "Whether the cluster API endpoint is reachable from the public internet. false is strongly preferred for production; true (with public_access_cidrs restricted) is more convenient for a lab."
  default     = true
}

variable "public_access_cidrs" {
  type        = list(string)
  description = "CIDR ranges allowed to reach the public API endpoint, if enabled. Never leave as 0.0.0.0/0 outside a throwaway lab."
  default     = ["0.0.0.0/0"]
}

variable "tags" {
  type    = map(string)
  default = {}
}
