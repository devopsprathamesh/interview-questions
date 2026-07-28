# production: one NAT gateway per AZ - full HA, highest cost, deliberately
# accepted for a customer-facing, revenue-critical environment. Three AZs,
# not two, for stronger production availability.

module "vpc" {
  source = "../../modules/vpc"

  name               = "platform-production"
  cidr_block         = var.vpc_cidr
  availability_zones = var.availability_zones
  nat_strategy       = "per_az"

  tags = {
    Environment = "production"
  }
}

module "app_security_group" {
  source = "../../modules/security-groups"

  name   = "platform-production-app"
  vpc_id = module.vpc.vpc_id

  ingress_rules = {
    https_internal = {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = [var.vpc_cidr]
    }
  }

  egress_rules = {
    all_outbound = {
      from_port = 0
      to_port   = 0
      protocol  = "-1"
    }
  }

  tags = {
    Environment = "production"
  }
}
