output "state_bucket_name" {
  description = "Name of the S3 bucket to use as the backend 'bucket' argument in other configurations."
  value       = aws_s3_bucket.state.id
}

output "state_bucket_arn" {
  value = aws_s3_bucket.state.arn
}

output "lock_table_name" {
  description = "Name of the DynamoDB table to use as the backend 'dynamodb_table' argument."
  value       = aws_dynamodb_table.lock.name
}

output "kms_key_arn" {
  description = "ARN of the KMS key used to encrypt state. Reference this in downstream backend configuration if using customer-managed key encryption context."
  value       = aws_kms_key.state.arn
}
