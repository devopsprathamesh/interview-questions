# --- Resource 1: no dependencies, evaluated first in the graph ---
resource "random_id" "suffix" {
  byte_length = 4
}

# --- Resource 2: depends on random_id.suffix (via local.bucket_name) ---
resource "aws_s3_bucket" "demo" {
  bucket = local.bucket_name
  tags   = local.common_tags

  # Precondition: fail fast with a clear message if the computed name is ever
  # somehow invalid, rather than letting the AWS API reject it with a generic error.
  lifecycle {
    precondition {
      condition     = length(local.bucket_name) <= 63
      error_message = "Computed bucket name '${local.bucket_name}' exceeds the 63-character S3 bucket name limit."
    }
  }
}

# --- Resource 3: depends on aws_s3_bucket.demo ---
resource "aws_s3_bucket_versioning" "demo" {
  count  = var.enable_versioning ? 1 : 0 # demonstrates the count 0/1 conditional-resource idiom
  bucket = aws_s3_bucket.demo.id

  versioning_configuration {
    status = "Enabled"
  }
}

# --- Resource 4: depends on aws_s3_bucket.demo, independent of aws_s3_bucket_versioning ---
# (This resource and aws_s3_bucket_versioning.demo are in the same graph "batch" -
#  Terraform may create them in parallel since neither depends on the other.)
resource "aws_s3_bucket_public_access_block" "demo" {
  bucket = aws_s3_bucket.demo.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- Resource 5: depends on aws_s3_bucket.demo ---
resource "aws_s3_bucket_server_side_encryption_configuration" "demo" {
  bucket = aws_s3_bucket.demo.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# --- Resource 6: local_file, depends on the bucket + both data sources ---
# Demonstrates a resource whose creation has no cloud cost at all, and gives
# the lab a visible, inspectable artifact after apply.
resource "local_file" "summary" {
  filename = "${path.module}/lab-output/summary.json"

  content = jsonencode({
    account_id  = data.aws_caller_identity.current.account_id
    region      = data.aws_region.current.name
    partition   = data.aws_partition.current.partition
    bucket_name = aws_s3_bucket.demo.id
    bucket_arn  = aws_s3_bucket.demo.arn
    versioning  = var.enable_versioning
    environment = var.environment
  })
}
