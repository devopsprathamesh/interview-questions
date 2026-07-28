resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-subnets"
  subnet_ids = var.subnet_ids
  tags       = merge(var.tags, { Name = "${var.name}-subnets" })
}

resource "aws_kms_key" "rds" {
  description             = "Encryption key for ${var.name} RDS instance and its managed master password"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  tags                    = var.tags
}

resource "aws_security_group" "db" {
  name        = "${var.name}-db"
  description = "Allows database port access only from explicitly listed security groups"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-db" })
}

resource "aws_vpc_security_group_ingress_rule" "from_app" {
  for_each = toset(var.allowed_security_group_ids)

  security_group_id            = aws_security_group.db.id
  from_port                    = local.engine_port
  to_port                      = local.engine_port
  ip_protocol                  = "tcp"
  referenced_security_group_id = each.value
}

locals {
  engine_port = { postgres = 5432, mysql = 3306 }[var.engine]
}

resource "aws_db_instance" "this" {
  identifier     = var.name
  engine         = var.engine
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage = var.allocated_storage
  storage_encrypted = true
  kms_key_id        = aws_kms_key.rds.arn

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]

  # AWS-managed, rotated credential - never a Terraform-supplied plaintext
  # password. See docs/security.md section 1 and interview-questions/02-state-management.md
  # Question 17.
  manage_master_user_password = true

  multi_az                = var.multi_az
  publicly_accessible      = false
  deletion_protection      = var.deletion_protection
  backup_retention_period  = var.backup_retention_period
  skip_final_snapshot      = false
  final_snapshot_identifier = "${var.name}-final-snapshot"

  tags = merge(var.tags, { Name = var.name })

  lifecycle {
    precondition {
      condition     = !var.deletion_protection || var.backup_retention_period > 0
      error_message = "A protected production database should also have automated backups enabled (backup_retention_period > 0)."
    }
  }
}
