# Native terraform test suite for the vpc module.
# Uses mock_provider so these tests run with ZERO AWS cost and ZERO AWS
# credentials required - see docs/testing.md section 4 on mock providers.
# Verify mock_provider support for your installed Terraform version (>= 1.7,
# with mocking capabilities that were refined in later 1.x releases).

mock_provider "aws" {
  mock_data "aws_region" {
    defaults = {
      name = "us-east-1"
    }
  }
}

variables {
  name               = "test-vpc"
  cidr_block         = "10.0.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b"]
}

run "valid_configuration_plans_cleanly" {
  command = plan

  assert {
    condition     = aws_vpc.this.cidr_block == "10.0.0.0/16"
    error_message = "VPC CIDR block should match the input variable"
  }

  assert {
    condition     = length(aws_subnet.public) == 2
    error_message = "Expected one public subnet per AZ (2 AZs supplied)"
  }

  assert {
    condition     = length(aws_subnet.private) == 2
    error_message = "Expected one private subnet per AZ (2 AZs supplied)"
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 1
    error_message = "nat_strategy defaults to 'single', expected exactly 1 NAT gateway"
  }
}

run "per_az_nat_creates_one_gateway_per_az" {
  command = plan

  variables {
    nat_strategy = "per_az"
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 2
    error_message = "nat_strategy = per_az with 2 AZs should create 2 NAT gateways"
  }
}

run "none_nat_creates_no_gateways_and_no_default_route" {
  command = plan

  variables {
    nat_strategy = "none"
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 0
    error_message = "nat_strategy = none should create zero NAT gateways"
  }

  assert {
    condition     = length(aws_route.private_nat) == 0
    error_message = "nat_strategy = none should create zero private default routes"
  }
}

run "invalid_cidr_is_rejected" {
  command = plan

  variables {
    cidr_block = "not-a-cidr"
  }

  expect_failures = [
    var.cidr_block,
  ]
}

run "single_az_is_rejected" {
  command = plan

  variables {
    availability_zones = ["us-east-1a"]
  }

  expect_failures = [
    var.availability_zones,
  ]
}

run "invalid_nat_strategy_is_rejected" {
  command = plan

  variables {
    nat_strategy = "everywhere"
  }

  expect_failures = [
    var.nat_strategy,
  ]
}
