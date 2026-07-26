module "vpc" {
  source = "../../modules/vpc"

  name               = var.name
  cidr_block         = var.cidr_block
  availability_zones = var.availability_zones
  nat_strategy       = "single" # cost-conscious default for this lab - see modules/vpc for the trade-off
  enable_s3_endpoint = true
}

module "eks" {
  source = "../../modules/eks"

  name                = var.name
  kubernetes_version  = var.kubernetes_version
  vpc_id              = module.vpc.vpc_id
  subnet_ids          = values(module.vpc.private_subnet_ids)
  node_instance_types = var.node_instance_types
  node_desired_size   = var.node_desired_size
  node_min_size       = 1
  node_max_size       = 3

  # Lab convenience only - see interview-questions/06-kubernetes-eks.md's
  # docs cross-reference on why production clusters should prefer
  # endpoint_public_access = false with access via a bastion/VPN/Session Manager.
  endpoint_public_access = true
  public_access_cidrs    = [var.lab_operator_cidr]
}

# --- Pod Identity example: a sample workload's IAM role, scoped to exactly
#     one namespace/service-account pair, demonstrating the pattern from
#     interview-questions/06-kubernetes-eks.md Question 54 ---
data "aws_iam_policy_document" "sample_app_pod_trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "sample_app_pod" {
  name               = "${var.name}-sample-app-pod-role"
  assume_role_policy = data.aws_iam_policy_document.sample_app_pod_trust.json
}

data "aws_iam_policy_document" "sample_app_pod_permissions" {
  statement {
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.name}-sample-app-data", "arn:aws:s3:::${var.name}-sample-app-data/*"]
  }
}

resource "aws_iam_role_policy" "sample_app_pod" {
  name   = "s3-read-only"
  role   = aws_iam_role.sample_app_pod.id
  policy = data.aws_iam_policy_document.sample_app_pod_permissions.json
}

resource "aws_eks_pod_identity_association" "sample_app" {
  cluster_name    = module.eks.cluster_name
  namespace       = "default"
  service_account = "sample-app"
  role_arn        = aws_iam_role.sample_app_pod.arn
}
