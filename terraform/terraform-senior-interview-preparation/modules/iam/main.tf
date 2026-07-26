data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = [var.trusted_service]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${var.name}-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  tags               = var.tags
}

# Least-privilege, additive policy statements - only created if the
# corresponding variable is non-empty. No wildcard "*" resource grants by
# default anywhere in this module.

data "aws_iam_policy_document" "secrets_access" {
  count = length(var.secrets_manager_secret_arns) > 0 ? 1 : 0

  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = var.secrets_manager_secret_arns
  }
}

resource "aws_iam_role_policy" "secrets_access" {
  count  = length(var.secrets_manager_secret_arns) > 0 ? 1 : 0
  name   = "secrets-read-only"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.secrets_access[0].json
}

data "aws_iam_policy_document" "s3_read_only" {
  count = length(var.s3_read_only_bucket_arns) > 0 ? 1 : 0

  statement {
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = flatten([for arn in var.s3_read_only_bucket_arns : [arn, "${arn}/*"]])
  }
}

resource "aws_iam_role_policy" "s3_read_only" {
  count  = length(var.s3_read_only_bucket_arns) > 0 ? 1 : 0
  name   = "s3-read-only"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.s3_read_only[0].json
}

resource "aws_iam_instance_profile" "this" {
  count = var.create_instance_profile ? 1 : 0
  name  = "${var.name}-instance-profile"
  role  = aws_iam_role.this.name
}
