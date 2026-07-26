variable "name" {
  type        = string
  description = "Name prefix for the log group, dashboard, and alarms."
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "alb_arn_suffix" {
  type        = string
  description = "ALB ARN suffix (e.g. \"app/my-alb/1234567890abcdef\") for CloudWatch metrics. Null skips ALB alarms."
  default     = null
}

variable "rds_instance_id" {
  type        = string
  description = "RDS instance identifier for CloudWatch metrics. Null skips RDS alarms."
  default     = null
}

variable "alarm_sns_topic_arn" {
  type        = string
  description = "SNS topic ARN to notify on alarm. If null, an SNS topic is created but has no subscriptions - wire one up before relying on these alarms."
  default     = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
