output "adopted_bucket_name" {
  value = aws_s3_bucket.adopted.id
}

output "adopted_bucket_arn" {
  value = aws_s3_bucket.adopted.arn
}
