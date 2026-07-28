# Native terraform test suite for the security-groups module.
# Plan-mode only - no real AWS resources created, no cost, no real credentials
# required thanks to mock_provider (see docs/testing.md section 4).

mock_provider "aws" {}

variables {
  name   = "test-sg"
  vpc_id = "vpc-00000000000000000" # syntactically valid placeholder ID, never actually called against a real API in plan mode without a provider config touching it

  ingress_rules = {
    https_internal = {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["10.0.0.0/16"]
    }
  }
}

run "valid_internal_rule_plans_cleanly" {
  command = plan

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.this) == 1
    error_message = "Expected exactly one ingress rule resource"
  }
}

run "public_cidr_without_allow_public_is_rejected" {
  command = plan

  variables {
    ingress_rules = {
      open_to_world = {
        from_port   = 22
        to_port     = 22
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
        # allow_public deliberately omitted (defaults to false) - should be rejected
      }
    }
  }

  expect_failures = [
    var.ingress_rules,
  ]
}

run "public_cidr_with_allow_public_is_accepted" {
  command = plan

  variables {
    ingress_rules = {
      public_health_check = {
        from_port    = 80
        to_port      = 80
        protocol     = "tcp"
        cidr_blocks  = ["0.0.0.0/0"]
        allow_public = true
      }
    }
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.this) == 1
    error_message = "Expected the explicitly-allowed public rule to be accepted"
  }
}

run "no_egress_rules_means_no_egress_resources" {
  command = plan

  assert {
    condition     = length(aws_vpc_security_group_egress_rule.this) == 0
    error_message = "With no egress_rules specified, expected zero egress rule resources (no implicit allow-all)"
  }
}
