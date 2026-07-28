# Diagram 6: Karpenter Provisioning Decision Flow

```mermaid
flowchart TD
    PENDING[Pending pod cannot be scheduled] --> KARP{Karpenter Controller}
    KARP -->|reads| NODEPOOL[NodePool: instance family/arch/purchase-option constraints]
    KARP -->|reads| NODECLASS[EC2NodeClass: AMI, subnets, security groups]
    KARP -->|computes best-fit instance type for pending pod shape| LAUNCH[Launch new EC2 instance directly - no ASG]
    LAUNCH --> NODEREADY[Node joins cluster, pod scheduled]

    UNDERUTIL[Node underutilized] --> CONSOLIDATE{Consolidation decision}
    CONSOLIDATE -->|do-not-disrupt annotation present?| SKIP[Skip - leave node alone]
    CONSOLIDATE -->|no blocking annotation| REPACK[Reschedule pods onto fewer nodes]
    REPACK --> TERMINATE[Terminate freed node]
```

## Key points
- Karpenter provisions EC2 instances directly — no pre-defined ASG or node group boundary constrains its instance-type choice; it picks the best fit for what's actually pending.
- Consolidation is a designed-in cost optimization, not a bug: nodes are actively terminated and workloads repacked when underutilized, unless a workload opts out via `karpenter.sh/do-not-disrupt`.
- This is a genuine architectural shift from Cluster Autoscaler's fixed-ASG-scaling model — see [`docs/node-management-and-autoscaling.md`](../docs/node-management-and-autoscaling.md) §2–3.
