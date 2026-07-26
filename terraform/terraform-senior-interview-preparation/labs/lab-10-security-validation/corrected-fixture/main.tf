# Corrected version of ../insecure-fixture/main.tf - the answer key.
# Do not peek until you've attempted the fixes yourself using scanner output
# as your guide (see the lab README's Step-by-Step Tasks).

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
  # FIX 1: no hardcoded credentials - relies on ambient credentials (an SSO
  # profile locally, OIDC federation in CI). See docs/terraform-architecture.md §5.
}

resource "aws_s3_bucket" "data" {
  bucket = "my-company-data-bucket"

  tags = {
    Environment = "dev"
    CostCenter  = "PLATFORM-001" # FIX 6: mandatory tags present
    Owner       = "platform-team"
  }
}

# FIX 2: explicit encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  bucket = aws_s3_bucket.data.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

# FIX 2 continued: versioning enabled
resource "aws_s3_bucket_versioning" "data" {
  bucket = aws_s3_bucket.data.id
  versioning_configuration {
    status = "Enabled"
  }
}

# FIX 3: public access blocked, no public bucket policy at all
resource "aws_s3_bucket_public_access_block" "data" {
  bucket                  = aws_s3_bucket.data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# FIX 4: security group scoped to the VPC CIDR, not the whole internet
resource "aws_security_group" "db" {
  name   = "database-sg"
  vpc_id = "vpc-placeholder"

  ingress {
    description = "postgres from within the VPC only"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }
}

# FIX 5: encrypted, provider-managed credentials, not publicly accessible,
# deletion protection on, right-sized for its tagged environment
resource "aws_db_instance" "app" {
  identifier                    = "app-db"
  engine                        = "postgres"
  instance_class                = "db.t3.small" # FIX 6 continued: right-sized for dev
  allocated_storage             = 20
  manage_master_user_password   = true # FIX 5a: AWS-managed credential, never plaintext
  storage_encrypted             = true # FIX 5b
  publicly_accessible           = false # FIX 5c
  deletion_protection           = true
  skip_final_snapshot           = false
  final_snapshot_identifier     = "app-db-final-snapshot"

  tags = {
    Environment = "dev"
    CostCenter  = "PLATFORM-001"
    Owner       = "platform-team"
  }
}

# FIX 7 + 8: IMDSv2 enforced, right-sized instance for a dev environment
resource "aws_instance" "app" {
  ami           = "ami-placeholder"
  instance_type = "t3.medium" # FIX 8: right-sized for tagged dev environment

  metadata_options {
    http_tokens = "required" # FIX 7: IMDSv2 only
  }

  tags = {
    Environment = "dev"
    CostCenter  = "PLATFORM-001"
    Owner       = "platform-team"
  }
}
