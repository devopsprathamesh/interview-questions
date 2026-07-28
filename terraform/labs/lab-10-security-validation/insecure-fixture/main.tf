# INTENTIONALLY INSECURE - this file exists for Lab 10's "find and fix" exercise.
# Never apply this configuration against real infrastructure. Every finding
# below is deliberate and documented in the lab README's answer key.

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

  # FINDING 1: hardcoded credentials in provider configuration.
  # See interview-questions/04-providers.md Question 40.
  access_key = "AKIAIOSFODNN7EXAMPLE"
  secret_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
}

# FINDING 2: S3 bucket with no encryption, no versioning, no public access block.
resource "aws_s3_bucket" "data" {
  bucket = "my-company-data-bucket"
}

# FINDING 3: bucket policy granting public read access.
resource "aws_s3_bucket_policy" "data" {
  bucket = aws_s3_bucket.data.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.data.arn}/*"
    }]
  })
}

# FINDING 4: security group open to the entire internet on a database port.
resource "aws_security_group" "db" {
  name   = "database-sg"
  vpc_id = "vpc-placeholder"

  ingress {
    description = "postgres from anywhere"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# FINDING 5: RDS instance with no encryption, a hardcoded password, and no
# deletion protection.
resource "aws_db_instance" "app" {
  identifier        = "app-db"
  engine            = "postgres"
  instance_class    = "db.t3.medium" # FINDING 6: oversized for a "dev" database - see below
  allocated_storage = 20
  username          = "postgres"
  password          = "SuperSecret123!" # FINDING 5a: hardcoded plaintext password
  storage_encrypted = false             # FINDING 5b: no encryption at rest
  publicly_accessible = true            # FINDING 5c: publicly accessible
  skip_final_snapshot = true

  tags = {
    Environment = "dev"
    # FINDING 6 continued: no CostCenter or Owner tag - missing mandatory tags
  }
}

# FINDING 7: an EC2 instance with IMDSv1 allowed (should require IMDSv2 tokens).
resource "aws_instance" "app" {
  ami           = "ami-placeholder"
  instance_type = "m5.24xlarge" # FINDING 8: wildly oversized for tagged dev environment

  tags = {
    Environment = "dev"
  }
}
