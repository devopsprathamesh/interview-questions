# Module: observability

A CloudWatch log group, an optional dashboard (ALB and/or RDS widgets, added conditionally based on which ARNs are supplied), and alarms for ALB 5xx errors, RDS high CPU, and RDS low free storage.

## Usage
```hcl
module "observability" {
  source = "../../modules/observability"

  name             = "my-app"
  alb_arn_suffix   = module.alb.alb_arn_suffix
  rds_instance_id  = module.rds.db_instance_id
}
```

## Design notes
- Alarms and dashboard widgets are added conditionally (`count` on a null check) based on which of `alb_arn_suffix`/`rds_instance_id` are supplied — this module works standalone for log aggregation alone, or fully wired for a complete application stack.
- If `alarm_sns_topic_arn` is left null, an SNS topic is created but has **no subscriptions** — alarms will fire but nobody will be notified until you subscribe an endpoint (email, PagerDuty integration, etc.) to it. This is deliberate: the module can't know your organization's paging tool, so it stops short of a false sense of "this is fully wired up."

## Inputs
`name`, `log_retention_days` (default 30), `alb_arn_suffix` (null skips ALB alarms/widgets), `rds_instance_id` (null skips RDS alarms/widgets), `alarm_sns_topic_arn` (null creates an unsubscribed topic), `tags`.

## Outputs
`log_group_name`, `dashboard_name`, `alarm_topic_arn`.
