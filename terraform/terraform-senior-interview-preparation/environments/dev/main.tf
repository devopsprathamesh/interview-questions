# dev: cheapest possible configuration - no NAT gateway at all. Private subnets
# have no internet egress; acceptable for dev workloads that don't need it.

module "vpc" {
  source = "../../modules/vpc"

  name               = "platform-dev"
  cidr_block         = var.vpc_cidr
  availability_zones = var.availability_zones
  nat_strategy       = "none"

  tags = {
    Environment = "dev"
  }
}

module "app_security_group" {
  source = "../../modules/security-groups"

  name   = "platform-dev-app"
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
    Environment = "dev"
  }
}
