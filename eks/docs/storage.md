# Storage and Stateful Workloads on EKS

Deep-dive reference for [`interview-questions/05-storage-stateful.md`](../interview-questions/05-storage-stateful.md) and [Lab 6 — Storage: EBS/EFS CSI](../labs/lab-06-storage-ebs-efs-csi/).

## 1. The CSI model — storage drivers as pluggable, self-managed add-ons

The **Container Storage Interface (CSI)** is the standard mechanism by which Kubernetes integrates with a storage backend, replacing the older, in-tree (compiled into Kubernetes itself) volume plugins. On EKS, the **EBS CSI driver** and **EFS CSI driver** are both available as EKS-managed add-ons (see [`docs/addons-and-upgrades.md`](addons-and-upgrades.md) §1) — meaning their lifecycle is more AWS-integrated than a fully self-managed Helm install, but they're still separate installable components, not automatically present on every cluster.

## 2. EBS: AZ-scoped, `ReadWriteOnce` by default — a real placement constraint

EBS volumes are **zonal** (tied to a specific AZ) — an EBS-backed `PersistentVolume` can only be attached to a node in the *same* AZ the volume was created in. This means a pod using an EBS-backed PVC can only be scheduled onto a node in that specific AZ, a genuine scheduling constraint that interacts with topology spread/anti-affinity design (see [`docs/ha-dr.md`](ha-dr.md) §2) — a common failure mode is a pod stuck `Pending` (or `ContainerCreating` failing to attach) because the scheduler placed it on a node in a different AZ than its existing PV. EBS volumes are also `ReadWriteOnce` by default (one node at a time) — a genuine limitation for any workload needing multiple pods across nodes to write to the same volume concurrently.

## 3. EFS: `ReadWriteMany`, multi-AZ, at a different performance/cost profile

EFS (NFS-based) supports `ReadWriteMany` (concurrent multi-node/multi-pod access) and spans AZs natively (no zonal-attachment constraint), directly solving EBS's cross-AZ and single-writer limitations — at the cost of generally higher per-operation latency than EBS's block-storage performance, and a different cost model (pay for actual storage used plus throughput, rather than provisioned IOPS/throughput). The senior-level choice: EBS for single-pod, high-performance block storage (databases, anything latency-sensitive); EFS for genuinely shared, multi-pod-access storage (shared config/asset directories, multi-writer workloads) where its latency profile is acceptable.

## 4. StorageClass, dynamic provisioning, and reclaim policy

A `StorageClass` defines *how* a PV gets created on demand (which CSI driver, what parameters — volume type, IOPS, encryption) when a PVC requests storage without a pre-existing matching PV — dynamic provisioning is the standard, default-recommended approach over manually pre-creating PVs. The `reclaimPolicy` (`Delete` vs. `Retain`) determines what happens to the underlying EBS volume when its PVC is deleted — `Delete` (the default for most StorageClasses) permanently destroys the volume and its data, while `Retain` leaves the underlying volume intact (orphaned, requiring manual cleanup or reattachment) for recovery scenarios. Getting this wrong in either direction is a real risk: `Delete` on a StorageClass backing genuinely important data with no separate backup strategy is a silent data-loss trap waiting for an accidental PVC deletion; `Retain` everywhere without a cleanup process accumulates orphaned, still-billed EBS volumes indefinitely.

## 5. Encryption at rest for EBS-backed volumes

EBS volumes support encryption at rest via KMS, configurable at the `StorageClass` level (`parameters.encrypted: "true"`, optionally with a specific `kmsKeyId`) — a standing security-hardening check (see [`docs/security.md`](security.md)) is confirming this is actually set on every StorageClass backing sensitive data, since an unencrypted-by-default StorageClass silently provisions unencrypted volumes with no error or warning.

## 6. StatefulSets — stable identity and storage, not just "a Deployment with volumes"

`StatefulSet` provides two things a `Deployment` does not: stable, predictable pod naming/network identity (`pod-0`, `pod-1`, ...) and a stable, dedicated PVC per replica (via `volumeClaimTemplates`) that persists across pod rescheduling — critical for workloads where identity and storage must survive a pod restart matched to the *same* replica index (databases, distributed systems with per-node state like Kafka/Elasticsearch/most self-hosted databases). Scaling a StatefulSet down does *not* delete its PVCs by default (a deliberate safety choice) — meaning storage can silently accumulate (and keep costing money) across scale-down events unless explicitly cleaned up, a genuine cost-governance consideration worth naming.

## 7. Backup for stateful workloads — Velero, and why GitOps alone doesn't cover this

See [`docs/ha-dr.md`](ha-dr.md) §5 — Velero (using the EBS CSI driver's snapshot capability under the hood) is the standard tool for actual PV data backup/restore. A GitOps repository capturing your `StatefulSet`/`PVC`/`StorageClass` manifests describes the *shape* of your storage, not the *data* inside it — restoring those manifests to a fresh cluster gives you empty, freshly-provisioned volumes, not your actual data back, a distinction worth being explicit about in any DR discussion.

## Common weak vs. senior answers

| Weak answer | Senior answer |
|---|---|
| "EBS and EFS are basically interchangeable" | Names the AZ-scoping/`ReadWriteOnce` vs. multi-AZ/`ReadWriteMany` distinction and the resulting workload-fit trade-off |
| "Our GitOps repo covers our disaster recovery for databases" | Distinguishes manifest/shape recovery (GitOps) from actual data recovery (Velero, database-level backup) |
| "Reclaim policy doesn't matter much" | Explicitly chooses `Retain` vs. `Delete` based on whether a separate backup strategy exists for that data |
| "Scaling a StatefulSet down cleans everything up" | Knows PVCs persist after scale-down by design, and tracks this as a real cost/cleanup consideration |

## Related material

- [`docs/eks-architecture.md`](eks-architecture.md), [`docs/ha-dr.md`](ha-dr.md), [`docs/security.md`](security.md)
- [Lab 6 — Storage: EBS/EFS CSI](../labs/lab-06-storage-ebs-efs-csi/)
