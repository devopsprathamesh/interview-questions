# EKS Interview Cheat Sheet

Master topic index. Use this as your final-day review before an interview.

## Topic → Doc → Questions → Lab index

| Topic | Doc | Question range | Lab |
|---|---|---|---|
| Control plane/data plane split, endpoint access, add-on model | [`eks-architecture.md`](eks-architecture.md) | 1–10 | [Lab 1](../labs/lab-01-cluster-bootstrap/) |
| VPC CNI, ENI/IP allocation, prefix delegation, target types, NetworkPolicy enforcement | [`networking.md`](networking.md) | 11–22 | [Lab 2](../labs/lab-02-networking-vpc-cni/), [Lab 7](../labs/lab-07-ingress-and-load-balancing/) |
| IRSA trust chain, Pod Identity, RBAC, Access Entries | [`iam-irsa.md`](iam-irsa.md) | 23–34 | [Lab 3](../labs/lab-03-irsa-and-iam/) |
| Managed node groups, Karpenter, Fargate, Spot, HPA/VPA | [`node-management-and-autoscaling.md`](node-management-and-autoscaling.md) | 35–60 | [Lab 4](../labs/lab-04-managed-node-groups/), [Lab 5](../labs/lab-05-karpenter-autoscaling/) |
| EBS/EFS CSI, StatefulSets, reclaim policy, encryption | [`storage.md`](storage.md) | 43–52 | [Lab 6](../labs/lab-06-storage-ebs-efs-csi/) |
| Pod Security Standards, NetworkPolicy, secrets, image supply chain | [`security.md`](security.md) | 61–68 | [Lab 8](../labs/lab-08-security-hardening/) |
| Add-on ownership, upgrade sequencing, Helm versioning | [`addons-and-upgrades.md`](addons-and-upgrades.md) | 69–78 | [Lab 4](../labs/lab-04-managed-node-groups/) |
| Logs/metrics/traces, Container Insights vs. Prometheus | [`observability.md`](observability.md) | 79–86 | [Lab 9](../labs/lab-09-observability-stack/) |
| GitOps reconciliation, progressive delivery, secrets in Git | [`cicd-gitops.md`](cicd-gitops.md) | 87–98 | [Lab 10](../labs/lab-10-gitops-argocd/), [Lab 11](../labs/lab-11-progressive-delivery/), [Lab 12](../labs/lab-12-cicd-pipeline/) |
| Pending/CrashLoop/OOMKilled/NotReady runbook | [`troubleshooting.md`](troubleshooting.md) | 99–104 | [Lab 14](../labs/lab-14-troubleshooting-and-recovery/) |
| Multi-AZ workload placement, Velero, multi-region DR | [`ha-dr.md`](ha-dr.md) | 105–110 | [Lab 15](../labs/lab-15-enterprise-capstone/) |
| Scale, multi-tenancy, cost | (covered in category file directly) | 111–114 | [Lab 15](../labs/lab-15-enterprise-capstone/) |
| OPA/Gatekeeper, Kyverno, policy testing | [`governance-policy.md`](governance-policy.md) | 115–117 | [Lab 13](../labs/lab-13-policy-as-code-opa/) |
| Migration, adoption, platform leadership | (covered in category file directly) | 118–120 | [Lab 15](../labs/lab-15-enterprise-capstone/) |

## The Interview Response Framework (memorize this)

1. Clarify blast radius
2. Protect production
3. Gather evidence
4. Inspect actual state (desired vs. live cluster vs. AWS-side)
5. Root cause, not symptom
6. Safest remediation path
7. Validate the fix
8. Rollback plan
9. Preventive controls
10. Document and communicate

## Five questions that separate Senior from Staff

1. Can you draw the full IRSA trust chain from memory, including exactly which fields the trust policy condition must check to prevent any-ServiceAccount-can-assume-this-role?
2. Can you explain why a `NetworkPolicy` object might do absolutely nothing, and how you'd verify enforcement is actually active before trusting it?
3. Can you articulate the correct cluster upgrade sequencing (control plane → EKS add-ons → self-managed add-ons → node groups) and why doing it out of order causes incidents?
4. Can you explain what GitOps's continuous reconciliation gives you that a traditional CI/CD push-based pipeline doesn't, and what it still doesn't solve (data, DNS cutover, controller availability during a regional incident)?
5. Can you distinguish what EKS's managed control plane genuinely removes from your operational burden (etcd backup, control-plane HA) from what remains entirely your responsibility (workload placement, node/pod HA design, data backup)?

## Common trap answers to avoid

- "EKS is just managed Kubernetes, AWS handles everything" — always name the specific control-plane/data-plane split.
- "NetworkPolicy/PSP/PodSecurityPolicy" used interchangeably or without knowing PSP was removed in 1.25.
- Treating `instance` and `ip` ALB target-group modes as equivalent — `ip` is the modern default for VPC-CNI clusters.
- Assuming multi-AZ nodes automatically means multi-AZ-resilient workloads — placement (topology spread/anti-affinity) is a separate, required design step.
- Confusing IAM cluster access (can you talk to the API server) with Kubernetes RBAC (what can you do once you're talking to it) — two separate authorization layers.
