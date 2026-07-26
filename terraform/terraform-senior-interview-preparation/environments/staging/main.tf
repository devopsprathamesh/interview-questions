# staging: one shared NAT gateway - cost-conscious, accepts a single point of
# failure for egress since staging isn't customer-facing.

module "vpc" {
  source = "../../modules/vpc"

  name               = "platform-staging"
  cidr_block         = var.vpc_cidr
  availability_zones = var.availability_zones
  nat_strategy       = "single"

  tags = {
    Environment = "staging"
  }
}

module "app_security_group" {
  source = "../../modules/security-groups"

  name   = "platform-staging-app"
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
    Environment = "staging"
  }
}
