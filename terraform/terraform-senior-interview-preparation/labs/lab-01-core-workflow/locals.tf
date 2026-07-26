locals {
  # Demonstrates local values: computed once, referenced everywhere, avoids repetition.
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
  }

  # Demonstrates a conditional/derived local built from a variable and a data source.
  bucket_name = "${local.name_prefix}-${random_id.suffix.hex}"
}
