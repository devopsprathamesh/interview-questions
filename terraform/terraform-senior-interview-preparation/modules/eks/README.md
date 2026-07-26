# Module: eks

Provisions an EKS cluster, one managed node group, the cluster and node IAM roles, an OIDC provider (for IRSA), the modern access-entries-based cluster access model, and (optionally) the EKS Pod Identity Agent add-on.

## Usage
```hcl
module "eks" {
  source = "../../modules/eks"

  name               = "my-cluster"
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = values(module.vpc.private_subnet_ids)
  kubernetes_version = "1.29"
  node_instance_types = ["t3.medium"]
  node_desired_size   = 2
}
```

## Design notes
- **No hardcoded provider block** (see [`docs/terraform-architecture.md` Part A](../../docs/terraform-architecture.md#part-a--provider-engineering)) — inherits the caller's default AWS provider.
- **`depends_on` on IAM policy attachments** for both the cluster and node group resources — a missing edge here is exactly the intermittent-failure pattern in [Question 8](../../interview-questions/01-terraform-core.md#question-8-the-intermittent-iam-race).
- **Access entries API, not the legacy `aws-auth` ConfigMap** — see [Question 56](../../interview-questions/06-kubernetes-eks.md#question-56-the-aws-auth-change-that-locked-everyone-out) for why this matters, including the assumed-role-ARN-to-IAM-role-ARN conversion this module performs for the cluster-creator access entry.
- **Pod Identity Agent installed by default** (`enable_pod_identity = true`), with the OIDC provider still created alongside it so a specific workload/add-on that hasn't yet added Pod Identity support can still use IRSA — see [Question 54](../../interview-questions/06-kubernetes-eks.md#question-54-irsa-or-pod-identity).
- **`update_config.max_unavailable_percentage`** is exposed and defaults to a conservative 25% — see [Question 55](../../interview-questions/06-kubernetes-eks.md#question-55-the-node-group-upgrade-that-evicted-everything-at-once) for why a node group upgrade without this can cause a full outage.

## Inputs
| Name | Type | Default | Description |
|---|---|---|---|
| `name` | string | — | Cluster name |
| `kubernetes_version` | string | `1.29` | Control plane version — verify current support before setting |
| `vpc_id` | string | — | VPC ID |
| `subnet_ids` | list(string) | — | Subnets for control plane + node group, min 2 |
| `node_instance_types` | list(string) | `["t3.medium"]` | Node group instance types |
| `node_desired_size` / `node_min_size` / `node_max_size` | number | 2 / 1 / 3 | Node group scaling config |
| `node_max_unavailable_percentage` | number | 25 | Concurrency cap during node group updates |
| `enable_pod_identity` | bool | true | Installs the Pod Identity Agent add-on |
| `endpoint_public_access` | bool | true | Whether the API endpoint is internet-reachable (lab convenience; prefer `false` in production) |
| `public_access_cidrs` | list(string) | `["0.0.0.0/0"]` | CIDR allowlist if public access is enabled |
| `tags` | map(string) | `{}` | Additional tags |

## Outputs
`cluster_name`, `cluster_endpoint`, `cluster_certificate_authority_data` (sensitive), `cluster_oidc_issuer_url`, `oidc_provider_arn`, `node_role_arn`, `cluster_role_arn`.

## Cost warning
An EKS cluster bills an hourly control-plane charge regardless of node count, plus standard EC2 charges for the node group's instances. **Verify current EKS and EC2 pricing before applying** — this is not a free-tier-eligible module for any meaningful duration. Destroy promptly after use (see [Lab 9](../../labs/lab-09-eks-infrastructure/)'s Cleanup section).
