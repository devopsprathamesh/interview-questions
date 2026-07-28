data "aws_caller_identity" "current" {}

locals {
  # sts:GetCallerIdentity returns an assumed-role session ARN
  # (arn:aws:sts::ACCOUNT:assumed-role/ROLE/SESSION) when running under an
  # assumed role, but EKS access entries require the underlying IAM role ARN
  # (arn:aws:iam::ACCOUNT:role/ROLE). This local converts one to the other so
  # the cluster-creator access entry below works regardless of whether you're
  # applying as an IAM user or an assumed role - a common, easy-to-miss gotcha.
  caller_arn         = data.aws_caller_identity.current.arn
  is_assumed_role    = can(regex(":assumed-role/", local.caller_arn))
  assumed_role_parts = local.is_assumed_role ? split("/", local.caller_arn) : []
  creator_principal_arn = local.is_assumed_role ? (
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.assumed_role_parts[1]}"
  ) : local.caller_arn
}

# --- Cluster IAM role ---
data "aws_iam_policy_document" "cluster_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.name}-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# --- EKS cluster ---
resource "aws_eks_cluster" "this" {
  name     = var.name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_public_access   = var.endpoint_public_access
    endpoint_private_access  = true # always on: node group traffic to the API server stays in-VPC regardless of public access setting
    public_access_cidrs      = var.public_access_cidrs
  }

  access_config {
    authentication_mode = "API" # modern access-entries API, not the legacy aws-auth ConfigMap
  }

  tags = var.tags

  # depends_on is explicit here even though the role is already referenced via
  # role_arn, because IAM policy *attachment* (a separate resource) must complete
  # before cluster creation - the attachment isn't otherwise referenced by any
  # attribute the cluster resource reads. See interview-questions/01-terraform-core.md
  # Question 8 for the general pattern this depends_on protects against.
  depends_on = [aws_iam_role_policy_attachment.cluster_policy]
}

# --- Cluster creator gets an explicit access entry (belt-and-suspenders alongside
#     the implicit creator access EKS grants - see interview-questions/06-kubernetes-eks.md
#     Question 56 on why this matters for break-glass recovery) ---
resource "aws_eks_access_entry" "creator" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = local.creator_principal_arn
}

resource "aws_eks_access_policy_association" "creator_admin" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = local.creator_principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}

# --- Node group IAM role ---
data "aws_iam_policy_document" "node_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.name}-node-role"
  assume_role_policy = data.aws_iam_policy_document.node_assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "node_worker_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr_read_only" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# --- Managed node group ---
resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.name}-nodes"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids
  instance_types  = var.node_instance_types

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable_percentage = var.node_max_unavailable_percentage
  }

  tags = var.tags

  # See interview-questions/01-terraform-core.md Question 8: node group creation
  # must not proceed until every IAM policy this node's role needs is attached,
  # or nodes intermittently fail to register with the cluster.
  depends_on = [
    aws_iam_role_policy_attachment.node_worker_policy,
    aws_iam_role_policy_attachment.node_cni_policy,
    aws_iam_role_policy_attachment.node_ecr_read_only,
  ]
}

# --- OIDC provider, for any workload still needing IRSA rather than Pod Identity ---
data "tls_certificate" "cluster_oidc" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "cluster" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.cluster_oidc.certificates[0].sha1_fingerprint]

  tags = var.tags
}

# --- Pod Identity: the modern default (see interview-questions/06-kubernetes-eks.md
#     Question 54) - installed as a cluster add-on, ready for per-workload
#     aws_eks_pod_identity_association resources at the consuming root module. ---
resource "aws_eks_addon" "pod_identity_agent" {
  count        = var.enable_pod_identity ? 1 : 0
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "eks-pod-identity-agent"

  depends_on = [aws_eks_node_group.this]
}
