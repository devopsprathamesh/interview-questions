output "db_instance_id" {
  value = aws_db_instance.this.id
}

output "db_endpoint" {
  value = aws_db_instance.this.endpoint
}

output "db_security_group_id" {
  value = aws_security_group.db.id
}

output "master_user_secret_arn" {
  description = "Secrets Manager ARN holding the AWS-managed master credential."
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}
