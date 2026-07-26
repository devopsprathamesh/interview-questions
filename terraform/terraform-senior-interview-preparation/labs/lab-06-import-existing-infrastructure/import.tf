# Import block (Terraform >= 1.5): declares intent to adopt an existing,
# unmanaged resource into Terraform state. This is reviewable in `terraform
# plan` output before anything is written, unlike the legacy imperative
# `terraform import` command.
#
# The `to` address must match a resource block that either already exists in
# your configuration (hand-written to match the real resource's attributes),
# or is generated automatically via:
#
#   terraform plan -generate-config-out=generated_bucket.tf
#
# After running that command, review generated_bucket.tf carefully against
# the bucket's actual real-world configuration before applying - see README
# Step-by-Step Tasks for the full walkthrough.

import {
  to = aws_s3_bucket.adopted
  id = var.manually_created_bucket_name
}
