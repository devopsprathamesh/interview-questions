# High Availability and Disaster Recovery on EKS

Deep-dive reference for [`interview-questions/12-ha-dr.md`](../interview-questions/12-ha-dr.md) and [Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).

## 1. Control-plane HA is AWS's problem; data-plane/workload HA is yours

See [`docs/eks-architecture.md`](eks-architecture.md) §7 — the EKS control plane is multi-AZ and AWS-managed by default, with no configuration required. Everything below the control plane (node placement, pod placement, workload replica count and distribution) requires explicit design to actually be resilient to an AZ failure.

## 2. Making workloads genuinely multi-AZ resilient

Spreading **nodes** across AZs (via node group subnet configuration) is necessary but not sufficient — a Deployment's replicas must also actually be *scheduled* across those AZs, via:

- **Topology spread constraints** (`topologySpreadConstraints`, the modern, more flexible mechanism) — explicitly instructs the scheduler to spread replicas evenly across a topology domain (e.g., `topology.kubernetes.io/zone`).
- **Pod anti-affinity** (`podAntiAffinity`, older, more verbose) — a `preferredDuringSchedulingIgnoredDuringExecution` rule discouraging (or `required...` forbidding) co-locating replicas of the same workload.

Without either, the scheduler's default bin-packing behavior can (and, at low replica counts, often does) concentrate all replicas of a critical workload in a single AZ — which then fails entirely if that AZ has an issue, despite the cluster's nodes technically spanning multiple AZs. This is the direct Kubernetes-native analog of the companion Terraform repository's "your ASG spans 3 AZs but happened to launch every instance in one" resilience gap.

## 3. What Kubernetes' self-healing does and doesn't give you for free

Kubernetes automatically reschedules pods from a failed node onto healthy ones (assuming sufficient cluster capacity exists elsewhere) — a meaningful, built-in resilience property. It does **not** automatically give you: sufficient spare capacity to absorb an AZ's worth of rescheduled pods (capacity planning is still your responsibility), correct multi-AZ replica distribution in the first place (§2), or protection against a *data*-level failure (a corrupted database, a bad deployment that's technically "healthy" per its probes but serving wrong results) — Kubernetes' self-healing operates at the infrastructure/process level, not the data-correctness level.

## 4. Etcd backup — AWS's responsibility, but understand what it means for you

EKS's control-plane etcd is backed up and managed entirely by AWS as part of the managed control plane — you have no direct access to etcd and no need to back it up yourself. This is a genuine, meaningful difference from a self-managed Kubernetes cluster (where etcd backup/restore is a critical, self-owned operational responsibility) — a senior-level answer should name this explicitly as one of the concrete things EKS's managed control plane actually removes from your operational burden, rather than either assuming it's your job or being unable to say who owns it.

## 5. Workload/data backup: Velero and application-level backup strategies

What EKS does *not* back up for you: the actual contents of Persistent Volumes (application data), and the full set of Kubernetes resource definitions as a point-in-time recoverable snapshot (distinct from your GitOps repo, which captures *desired* state but not necessarily things like in-cluster Secrets sourced dynamically, or resources created outside the GitOps flow). **Velero** is the standard tool for both: snapshotting PV data (via cloud-provider snapshot APIs — EBS snapshots under the hood) and backing up Kubernetes resource manifests as they actually exist in the cluster, restorable to the same or a different cluster.

## 6. Multi-region DR — what genuinely changes vs. what a GitOps model already gives you

A DR-region EKS cluster, provisioned identically (same Terraform module, per the companion repository's multi-region guidance) and running the same GitOps-managed manifests, converges to the same application-level state as the primary region **automatically**, once the GitOps controller in that region points at the same Git source — there's no separate "apply the DR region's configuration" step distinct from normal operations, since the GitOps model's continuous reconciliation already handles it, as long as the DR cluster's GitOps controller is running and pointed correctly. What genuinely still needs explicit DR-specific handling: **data** (databases, PV contents — application state has no equivalent "just re-apply from Git" story; it needs real replication/backup-restore), DNS/traffic cutover (Route 53 failover or similar, routing users to the DR region), and any region-specific configuration (different VPC CIDR, different account-specific resource ARNs) the overlay structure must account for.

## 7. The "recovery tool can't share fate with what it's recovering" principle, applied to GitOps

Directly mirroring the companion Ansible repository's AWX-availability-during-DR lesson: if your GitOps controller (ArgoCD/Flux) itself runs *only* in the primary region, and the primary region is what's down, you have no way to reconcile the DR region's cluster during the exact incident you need it for. A genuinely resilient GitOps-based DR design runs (or can quickly stand up) a GitOps controller instance independent of the primary region's own availability — either a controller already running in the DR region, or a documented, tested bootstrap procedure to point a fresh controller instance at the same Git source from wherever is currently reachable.

## 8. Blast-radius containment during a cluster-wide operation

A cluster upgrade, a bad cluster-wide policy rollout, or a misconfigured admission webhook (see [`docs/security.md`](security.md) §4) can affect the *entire* cluster at once — a materially larger blast radius than a single bad Deployment. The mitigation is the same conservative, staged-rollout discipline used elsewhere in this repository (canary the change in a non-production cluster first, stage the rollout, have a tested rollback path) applied specifically to cluster-level, not just workload-level, changes.

## Common weak vs. senior answers

| Weak answer | Senior answer |
|---|---|
| "EKS control plane is multi-AZ so we're resilient" | Distinguishes AWS-managed control-plane multi-AZ from data-plane/workload placement, which needs explicit design |
| "Kubernetes reschedules pods automatically so we don't need to plan for AZ failure" | Knows self-healing needs spare capacity and correct topology spread to actually work as intended |
| "We back up etcd regularly" (on EKS) | Knows EKS's etcd backup is AWS-managed; workload/data backup (Velero, database-level) is what remains their responsibility |
| "Our GitOps repo is our DR plan" | Recognizes GitOps handles *configuration* convergence but not data replication, DNS cutover, or a GitOps-controller-availability dependency during the DR event itself |

## Related material

- [`docs/eks-architecture.md`](eks-architecture.md), [`docs/cicd-gitops.md`](cicd-gitops.md)
- [Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/)
- Companion: [Ansible HA/DR guidance](../../../ansible/ansible-senior-interview-preparation/docs/ha-dr.md), [Terraform multi-region guidance](../../../terraform/terraform-senior-interview-preparation/)
