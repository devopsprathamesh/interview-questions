output "log_group_name" {
  value = aws_cloudwatch_log_group.app.name
}

output "dashboard_name" {
  value = aws_cloudwatch_dashboard.this.dashboard_name
}

output "alarm_topic_arn" {
  value = local.alarm_topic_arn
}
