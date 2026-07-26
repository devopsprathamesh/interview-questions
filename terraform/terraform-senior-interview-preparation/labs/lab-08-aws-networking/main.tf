module "vpc" {
  source = "../../modules/vpc"

  name               = var.name
  cidr_block         = var.cidr_block
  availability_zones = var.availability_zones
  nat_strategy       = var.nat_strategy
  enable_s3_endpoint = true
}

# Security group for a private application tier: no inbound from the internet at
# all, only from within the VPC (the ALB security group below), egress to
# anywhere (needed for package installs / API calls via NAT or endpoints).
module "app_security_group" {
  source = "../../modules/security-groups"

  name        = "${var.name}-app"
  vpc_id      = module.vpc.vpc_id
  description = "Application tier - no direct internet ingress"

  ingress_rules = {
    "http_from_alb" = {
      from_port   = 8080
      to_port     = 8080
      protocol    = "tcp"
      cidr_blocks = [module.vpc.vpc_cidr_block]
    }
  }

  egress_rules = {
    "all_outbound" = {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
}

# Security group for the public-facing ALB: the ONLY thing in this platform
# permitted to accept traffic from the whole internet, and only on 443.
module "alb_security_group" {
  source = "../../modules/security-groups"

  name        = "${var.name}-alb"
  vpc_id      = module.vpc.vpc_id
  description = "Public ALB - deliberate, reviewed internet exposure on 443 only"

  ingress_rules = {
    "https_from_internet" = {
      from_port    = 443
      to_port      = 443
      protocol     = "tcp"
      cidr_blocks  = ["0.0.0.0/0"]
      allow_public = true # deliberate, reviewed exception - this IS the public entry point
    }
  }

  egress_rules = {
    "to_app_tier" = {
      from_port   = 8080
      to_port     = 8080
      protocol    = "tcp"
      cidr_blocks = [module.vpc.vpc_cidr_block]
    }
  }
}

# Security group shared by every Interface VPC endpoint: only reachable from
# within the VPC, on 443 (every AWS service API uses HTTPS).
resource "aws_security_group" "vpc_endpoints" {
  count       = var.enable_interface_endpoints ? 1 : 0
  name        = "${var.name}-vpc-endpoints"
  description = "Allows VPC-internal HTTPS to Interface VPC endpoints"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [module.vpc.vpc_cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-vpc-endpoints"
  }
}

# Interface VPC endpoints: ECR (image pulls), CloudWatch Logs, and SSM (the
# three endpoints that together let a private-subnet instance be managed via
# Session Manager, with no bastion host and no open SSH port anywhere).
locals {
  interface_endpoint_services = var.enable_interface_endpoints ? toset([
    "ecr.api", "ecr.dkr", "logs", "ssm", "ssmmessages", "ec2messages"
  ]) : toset([])
}

resource "aws_vpc_endpoint" "interface" {
  for_each = local.interface_endpoint_services

  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = values(module.vpc.private_subnet_ids)
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = {
    Name = "${var.name}-${each.key}"
  }
}
