# --- Read the foundation layer's outputs via SSM Parameter Store, never via
#     terraform_remote_state. This layer has no read access to and no
#     knowledge of the foundation layer's actual state backend at all. ---
data "aws_ssm_parameter" "vpc_id" {
  name = "/capstone/${var.environment}/foundation/vpc_id"
}

data "aws_ssm_parameter" "public_subnet_ids" {
  name = "/capstone/${var.environment}/foundation/public_subnet_ids"
}

data "aws_ssm_parameter" "alb_security_group_id" {
  name = "/capstone/${var.environment}/foundation/alb_security_group_id"
}

module "alb" {
  source = "../../../modules/alb"

  name               = "capstone-${var.environment}"
  vpc_id             = data.aws_ssm_parameter.vpc_id.value
  public_subnet_ids  = split(",", data.aws_ssm_parameter.public_subnet_ids.value)
  security_group_id  = data.aws_ssm_parameter.alb_security_group_id.value
  certificate_arn    = var.certificate_arn

  enable_deletion_protection = var.environment == "production"

  tags = { Environment = var.environment }
}

module "observability" {
  source = "../../../modules/observability"

  name           = "capstone-${var.environment}"
  alb_arn_suffix = replace(module.alb.alb_arn, "/^arn:aws:elasticloadbalancing:[^:]+:[^:]+:loadbalancer\\//", "")

  tags = { Environment = var.environment }
}

# --- Publish this layer's outputs for the application layer to consume ---
resource "aws_ssm_parameter" "alb_target_group_arn" {
  name  = "/capstone/${var.environment}/platform/alb_target_group_arn"
  type  = "String"
  value = module.alb.target_group_arn
}

resource "aws_ssm_parameter" "alb_dns_name" {
  name  = "/capstone/${var.environment}/platform/alb_dns_name"
  type  = "String"
  value = module.alb.alb_dns_name
}

resource "aws_ssm_parameter" "log_group_name" {
  name  = "/capstone/${var.environment}/platform/log_group_name"
  type  = "String"
  value = module.observability.log_group_name
}
