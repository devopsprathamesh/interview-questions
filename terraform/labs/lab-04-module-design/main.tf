module "vpc" {
  source = "../../modules/vpc"

  name               = var.name
  cidr_block         = var.vpc_cidr
  availability_zones = var.availability_zones
  nat_strategy       = "none" # no NAT gateway for this lab - keeps cost at zero; see README

  tags = {
    Lab = "lab-04-module-design"
  }
}

module "app_security_group" {
  source = "../../modules/security-groups"

  name   = "${var.name}-app"
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
    Lab = "lab-04-module-design"
  }
}
