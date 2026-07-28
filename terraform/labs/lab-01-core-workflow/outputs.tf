output "bucket_name" {
  description = "Name of the created S3 bucket."
  value       = aws_s3_bucket.demo.id
}

output "bucket_arn" {
  description = "ARN of the created S3 bucket."
  value       = aws_s3_bucket.demo.arn
}

output "account_id" {
  description = "AWS account ID this configuration is running against (from data source)."
  value       = data.aws_caller_identity.current.account_id
}

output "region" {
  description = "AWS region this configuration is running against (from data source)."
  value       = data.aws_region.current.name
}

output "versioning_enabled" {
  description = "Whether S3 bucket versioning was enabled (demonstrates count-based conditional output)."
  value       = var.enable_versioning
}

output "summary_file_path" {
  description = "Local path to the generated summary.json file."
  value       = local_file.summary.filename
}
