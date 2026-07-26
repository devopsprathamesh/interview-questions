variable "name" {
  type        = string
  description = "Name for the application execution role."
}

variable "trusted_service" {
  type        = string
  description = "AWS service principal allowed to assume this role (e.g. \"ec2.amazonaws.com\", \"ecs-tasks.amazonaws.com\")."
  default     = "ec2.amazonaws.com"
}

variable "secrets_manager_secret_arns" {
  type        = list(string)
  description = "ARNs of Secrets Manager secrets this role may read (e.g. an RDS master_user_secret_arn). Empty by default - grant only what's actually needed."
  default     = []
}

variable "s3_read_only_bucket_arns" {
  type        = list(string)
  description = "S3 bucket ARNs this role may read from (list access + object read, not write). Empty by default."
  default     = []
}

variable "create_instance_profile" {
  type        = bool
  description = "Whether to create an EC2 instance profile wrapping this role. Set false for a role used by ECS/EKS instead."
  default     = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
