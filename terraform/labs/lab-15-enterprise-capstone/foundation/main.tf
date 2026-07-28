module "vpc" {
  source = "../../../modules/vpc"

  name               = "capstone-${var.environment}"
  cidr_block         = var.cidr_block
  availability_zones = var.availability_zones
  nat_strategy       = var.nat_strategy
  enable_s3_endpoint = true

  tags = { Environment = var.environment }
}

module "alb_security_group" {
  source = "../../../modules/security-groups"

  name        = "capstone-${var.environment}-alb"
  vpc_id      = module.vpc.vpc_id
  description = "Public ALB - deliberate internet exposure on 443/80 only"

  ingress_rules = {
    https = {
      from_port    = 443
      to_port      = 443
      protocol     = "tcp"
      cidr_blocks  = ["0.0.0.0/0"]
      allow_public = true
    }
    http = {
      from_port    = 80
      to_port      = 80
      protocol     = "tcp"
      cidr_blocks  = ["0.0.0.0/0"]
      allow_public = true
    }
  }

  egress_rules = {
    to_app = {
      from_port   = 8080
      to_port     = 8080
      protocol    = "tcp"
      cidr_blocks = [var.cidr_block]
    }
  }

  tags = { Environment = var.environment }
}

module "app_security_group" {
  source = "../../../modules/security-groups"

  name        = "capstone-${var.environment}-app"
  vpc_id      = module.vpc.vpc_id
  description = "Application tier - no direct internet ingress"

  ingress_rules = {
    http_from_alb = {
      from_port   = 8080
      to_port     = 8080
      protocol    = "tcp"
      cidr_blocks = [var.cidr_block]
    }
  }

  egress_rules = {
    all_outbound = {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  tags = { Environment = var.environment }
}

# --- Publish stable outputs via SSM Parameter Store, NOT terraform_remote_state.
#     Every other layer (platform, application) reads these instead of reaching
#     into this layer's state directly - see docs/state-management.md section 10
#     and interview-questions/02-state-management.md Question 16. ---
locals {
  param_prefix = "/capstone/${var.environment}/foundation"
}

resource "aws_ssm_parameter" "vpc_id" {
  name  = "${local.param_prefix}/vpc_id"
  type  = "String"
  value = module.vpc.vpc_id
}

resource "aws_ssm_parameter" "vpc_cidr" {
  name  = "${local.param_prefix}/vpc_cidr"
  type  = "String"
  value = module.vpc.vpc_cidr_block
}

resource "aws_ssm_parameter" "public_subnet_ids" {
  name  = "${local.param_prefix}/public_subnet_ids"
  type  = "StringList"
  value = join(",", values(module.vpc.public_subnet_ids))
}

resource "aws_ssm_parameter" "private_subnet_ids" {
  name  = "${local.param_prefix}/private_subnet_ids"
  type  = "StringList"
  value = join(",", values(module.vpc.private_subnet_ids))
}

resource "aws_ssm_parameter" "alb_security_group_id" {
  name  = "${local.param_prefix}/alb_security_group_id"
  type  = "String"
  value = module.alb_security_group.security_group_id
}

resource "aws_ssm_parameter" "app_security_group_id" {
  name  = "${local.param_prefix}/app_security_group_id"
  type  = "String"
  value = module.app_security_group.security_group_id
}
