# --- Cross-layer reads via SSM Parameter Store only - see foundation/main.tf
#     and platform/main.tf for what's published and why. ---
data "aws_ssm_parameter" "vpc_id" {
  name = "/capstone/${var.environment}/foundation/vpc_id"
}

data "aws_ssm_parameter" "private_subnet_ids" {
  name = "/capstone/${var.environment}/foundation/private_subnet_ids"
}

data "aws_ssm_parameter" "app_security_group_id" {
  name = "/capstone/${var.environment}/foundation/app_security_group_id"
}

data "aws_ssm_parameter" "alb_target_group_arn" {
  name = "/capstone/${var.environment}/platform/alb_target_group_arn"
}

locals {
  private_subnet_ids = split(",", data.aws_ssm_parameter.private_subnet_ids.value)
}

# --- Database layer ---
module "rds" {
  source = "../../../modules/rds"

  name                       = "capstone-${var.environment}"
  vpc_id                     = data.aws_ssm_parameter.vpc_id.value
  subnet_ids                 = local.private_subnet_ids
  allowed_security_group_ids = [data.aws_ssm_parameter.app_security_group_id.value]
  engine                     = var.db_engine
  instance_class             = var.db_instance_class
  multi_az                   = var.db_multi_az
  deletion_protection        = var.environment == "production"

  tags = { Environment = var.environment }
}

# --- Application IAM role: read-only access to exactly its own DB secret,
#     nothing else. See modules/iam for the least-privilege pattern. ---
module "app_role" {
  source = "../../../modules/iam"

  name                        = "capstone-${var.environment}-app"
  trusted_service             = "ec2.amazonaws.com"
  secrets_manager_secret_arns = [module.rds.master_user_secret_arn]

  tags = { Environment = var.environment }
}

# --- Compute layer: ASG with a conservative update_config, per
#     interview-questions/06-kubernetes-eks.md Question 55's general lesson
#     applied to a plain EC2 ASG instead of an EKS node group. ---
resource "aws_launch_template" "app" {
  name_prefix   = "capstone-${var.environment}-"
  image_id      = var.ami_id
  instance_type = var.instance_type

  iam_instance_profile {
    name = module.app_role.instance_profile_name
  }

  vpc_security_group_ids = [data.aws_ssm_parameter.app_security_group_id.value]

  metadata_options {
    http_tokens = "required" # IMDSv2 only - see interview-questions/10-security-validation lab
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh.tftpl", {
    db_secret_arn = module.rds.master_user_secret_arn
    db_endpoint   = module.rds.db_endpoint
  }))

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "capstone-${var.environment}-app", Environment = var.environment }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "app" {
  name_prefix         = "capstone-${var.environment}-"
  vpc_zone_identifier = local.private_subnet_ids
  desired_capacity    = var.desired_capacity
  min_size            = var.min_size
  max_size            = var.max_size
  target_group_arns   = [data.aws_ssm_parameter.alb_target_group_arn.value]

  launch_template {
    id      = aws_launch_template.app.id
    version = aws_launch_template.app.latest_version
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 90
      checkpoint_delay       = 300
    }
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}
