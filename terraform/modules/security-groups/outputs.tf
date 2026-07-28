output "security_group_id" {
  description = "ID of the created security group."
  value       = aws_security_group.this.id
}

output "security_group_arn" {
  value = aws_security_group.this.arn
}
