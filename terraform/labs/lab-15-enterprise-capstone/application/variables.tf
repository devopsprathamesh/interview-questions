variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "environment" {
  type = string
}

variable "ami_id" {
  type        = string
  description = "AMI ID for the application instances (e.g. the latest Amazon Linux 2023 AMI for your region - look it up via: aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 --query Parameter.Value --output text)."
}

variable "instance_type" {
  type    = string
  default = "t3.small"
}

variable "desired_capacity" {
  type    = number
  default = 2
}

variable "min_size" {
  type    = number
  default = 2
}

variable "max_size" {
  type    = number
  default = 4
}

variable "db_engine" {
  type    = string
  default = "postgres"
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.small"
}

variable "db_multi_az" {
  type        = bool
  description = "true for production (genuine within-region HA - see interview-questions/11-ha-dr.md Question 103 for why this is not the same as DR)."
  default     = false
}
