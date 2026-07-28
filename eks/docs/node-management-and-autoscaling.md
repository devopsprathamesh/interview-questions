# Node Management and Autoscaling

Deep-dive reference for [`interview-questions/04-node-management.md`](../interview-questions/04-node-management.md), [`interview-questions/06-autoscaling-scheduling.md`](../interview-questions/06-autoscaling-scheduling.md), [Lab 4 — Managed Node Groups](../labs/lab-04-managed-node-groups/), and [Lab 5 — Karpenter Autoscaling](../labs/lab-05-karpenter-autoscaling/).

## 1. Three ways to run compute on EKS

- **Managed Node Groups (MNG):** AWS-managed EC2 Auto Scaling Groups with lifecycle integration (draining, launch-template versioning) handled by the EKS API — you choose instance types/AMI/scaling config, AWS handles the ASG mechanics and node registration.
- **Self-managed node groups:** you own the ASG/launch-template directly (via Terraform, typically) — more flexibility (any AMI, any bootstrap customization), more operational ownership.
- **Fargate:** serverless, per-pod compute with no node to manage at all — AWS provisions right-sized compute per pod automatically; trade-offs include no DaemonSet support, no host networking, and generally higher per-vCPU cost than EC2 at steady, predictable utilization.

## 2. Cluster Autoscaler vs. Karpenter — a real architectural shift, not just a version bump

**Cluster Autoscaler** scales existing, pre-defined Auto Scaling Groups up/down based on pending-pod demand — it can only choose among instance types you've already configured into specific node groups, and scaling decisions are constrained by ASG boundaries.

**Karpenter** provisions nodes directly (no ASG intermediary) using flexible `NodePool`/`EC2NodeClass` constraints (instance families, architectures, purchase options), making just-in-time, workload-shape-aware provisioning decisions (choosing the actual best-fit instance type for currently-pending pods, not just scaling a pre-defined group) and actively **consolidating** underutilized nodes (bin-packing workloads onto fewer nodes and terminating the freed ones) — a capability Cluster Autoscaler doesn't have in the same proactive form. The senior-level framing: Karpenter is generally the more modern, more cost-efficient default recommendation for new clusters, with Cluster Autoscaler remaining common in older/more conservative environments valuing the predictability of fixed, pre-defined node groups.

## 3. Karpenter's consolidation — a genuine trade-off to name explicitly

Karpenter's consolidation actively terminates and replaces underutilized nodes to reduce cost — this means node churn is a designed-in, expected behavior (not a sign of instability), but it also means workloads must tolerate being rescheduled relatively often unless explicitly configured otherwise (via `karpenter.sh/do-not-disrupt` annotations or a `NodePool`'s disruption budget) — a genuinely different operational posture from a static, rarely-churning fixed node group, worth naming as a deliberate cost/stability trade-off rather than an accident.

## 4. Spot instances — cost savings with a real interruption contract

Both Karpenter and Cluster Autoscaler (via mixed-instance-policy ASGs) support Spot instances at significant cost savings, at the cost of a 2-minute interruption notice before AWS reclaims the instance. Handling this correctly requires: the AWS Node Termination Handler (or Karpenter's built-in interruption handling) to cordon/drain gracefully on the interruption notice, and workload-level tolerance (sufficient replica count elsewhere, `PodDisruptionBudget`-aware draining) so a Spot reclaim doesn't cause a user-facing outage — the same "expected, tolerable failure mode for cost-optimized fleets" framing as the companion Ansible repository's ASG-scale-in-during-a-patch-run guidance ([Question 44](../../ansible/interview-questions/05-aws-cloud-integration.md#question-44-the-patch-that-raced-the-auto-scaler)).

## 5. Horizontal Pod Autoscaler (HPA), Vertical Pod Autoscaler (VPA), and node autoscaling are three separate, complementary layers

- **HPA** scales the *number of pod replicas* based on observed metrics (CPU/memory by default via `metrics-server`, or custom/external metrics via the Prometheus Adapter or KEDA for event-driven scaling).
- **VPA** adjusts a pod's own resource requests/limits based on observed usage (either recommending or automatically applying — automatic mode requires pod restarts to take effect, a real operational consideration).
- **Karpenter/Cluster Autoscaler** scales the *number of nodes* based on aggregate pending-pod demand.

Running HPA and VPA on the *same* workload's *same* resource dimension (e.g., both adjusting CPU) without careful coordination causes a fighting/oscillation failure mode — HPA adds replicas because CPU-per-pod is high, VPA simultaneously tries to raise the per-pod CPU limit, and the two adjustments can interact in confusing, hard-to-predict ways. The standard mitigation: use HPA on CPU/custom metrics and VPA only in recommendation mode (not auto-apply) for the same workload, or scope VPA to a different resource dimension (e.g., memory) than HPA's (CPU).

## 6. Pod scheduling constraints as a first-class design decision, not an afterthought

Taints/tolerations (dedicating nodes to specific workloads, e.g., GPU nodes tainted so only GPU-requesting pods schedule there), node affinity/anti-affinity, and topology spread constraints (see [`docs/ha-dr.md`](ha-dr.md) §2) together determine actual workload placement — a senior-level design explicitly reasons about these for any workload with real availability or resource-isolation requirements, rather than accepting the scheduler's unconstrained default bin-packing behavior.

## 7. Bootstrap and node configuration — where it overlaps with the companion Ansible repository

A node's bootstrap process (kubelet configuration, container runtime setup, any pre-baked AMI content) is conceptually the same golden-AMI-baking problem discussed in the companion Ansible repository's [Lab 8 (Packer and Ansible AMI Baking)](../../ansible/labs/lab-08-packer-ami-baking/) — EKS-optimized AMIs are themselves built via a Packer-equivalent process (the `amazon-eks-ami` build scripts), and a custom AMI (for compliance baseline requirements, pre-installed agents, etc.) follows the identical bake-then-launch pattern, just with an EKS-specific bootstrap script (`/etc/eks/bootstrap.sh`) wiring the node into the cluster on boot.

## Common weak vs. senior answers

| Weak answer | Senior answer |
|---|---|
| "Karpenter and Cluster Autoscaler do the same thing" | Explains Karpenter's direct, flexible, consolidation-capable provisioning vs. Cluster Autoscaler's fixed-ASG-boundary scaling |
| "Just enable both HPA and VPA on every workload" | Recognizes the fighting/oscillation risk when both scale the same resource dimension, and scopes them deliberately |
| "Spot interruptions are a problem to avoid" | Treats Spot interruption as an expected, designed-for failure mode with proper draining and replica-count tolerance |
| "Fargate is always better since there's no node to manage" | Weighs Fargate's per-pod cost and feature limitations (no DaemonSets, no host networking) against its operational simplicity |

## Related material

- [`docs/eks-architecture.md`](eks-architecture.md), [`docs/ha-dr.md`](ha-dr.md)
- [Lab 4 — Managed Node Groups](../labs/lab-04-managed-node-groups/), [Lab 5 — Karpenter Autoscaling](../labs/lab-05-karpenter-autoscaling/)
- Companion: [Ansible Lab 8 — Packer and Ansible AMI Baking](../../ansible/labs/lab-08-packer-ami-baking/)
