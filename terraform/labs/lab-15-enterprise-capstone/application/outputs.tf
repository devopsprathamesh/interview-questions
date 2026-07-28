output "asg_name" {
  value = aws_autoscaling_group.app.name
}

output "db_endpoint" {
  value = module.rds.db_endpoint
}

output "app_role_arn" {
  value = module.app_role.role_arn
}
