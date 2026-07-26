# Data sources: read-only lookups against real-world/provider state.
# These have no dependency on anything this configuration creates, so they sit
# at the root of the dependency graph and can be evaluated immediately.

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_partition" "current" {}
