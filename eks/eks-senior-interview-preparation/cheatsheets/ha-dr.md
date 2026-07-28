# Cheat Sheet: High Availability and Disaster Recovery

## Control plane HA is automatic; workload placement is NOT
- EKS control plane: multi-AZ, AWS-managed, zero configuration needed.
- Workload replica distribution across AZs: **requires explicit `topologySpreadConstraint`** — the scheduler's default placement can concentrate all replicas in one AZ regardless of node-group AZ span.
```yaml
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule   # hard constraint for genuinely critical workloads
```
[Question 105](../interview-questions/12-ha-dr.md#question-105-three-replicas-one-az)

## GitOps config parity ≠ full DR readiness
GitOps reconciliation covers **configuration** only. It has zero mechanism for, and zero awareness of, actual **data**. Every stateful dependency needs its own, explicitly-designed, separately-tested data-replication mechanism. [Question 106](../interview-questions/12-ha-dr.md#question-106-the-dr-cluster-that-was-ready-except-for-the-part-that-mattered)

## The GitOps controller can't share fate with the disaster it recovers from
A DR-region cluster needs its **own** GitOps controller instance, independent of primary-region availability — not a controller that only exists in primary. [`docs/ha-dr.md`](../docs/ha-dr.md) §7

## Cold-start latency vs. cost-optimized capacity
Karpenter's scale-to-zero for a DR region's idle NodePools is cost-efficient during normal operation but can produce an unacceptable multi-minute cold-start delay during an actual failover. Size a standing-capacity floor matched to your real RTO. [Question 107](../interview-questions/12-ha-dr.md#question-107-the-failover-that-failed-over-to-nothing)

## An untested DR drill run only by its own author proves almost nothing
Two years of passing quarterly drills, always by the same engineer, only validates that person's tribal knowledge — not whether the *documentation* is genuinely sufficient. Rotate drill ownership as a standing practice. [Question 108](../interview-questions/12-ha-dr.md#question-108-the-backup-that-was-never-tested-until-it-mattered)

## Residual risk beyond your architecture's boundary is a business decision, not a technical failure
A two-region design's boundary is "both regions simultaneously affected." Document this explicitly, get business sign-off on accepting or further mitigating it — don't leave it as an unexamined assumption. [Question 109](../interview-questions/12-ha-dr.md#question-109-one-region-down-then-the-other)

## The blank-page DR design checklist
1. Actual business RTO/RPO requirements (not a default assumption)
2. Workload-level AZ resilience (topology spread constraints)
3. Configuration parity (GitOps) — explicitly scoped as config-only
4. Explicit, separate, tested data-replication per stateful dependency
5. Region-independent GitOps controller
6. Sized standing-capacity floor matched to real RTO
7. A drill matching the ACTUAL intended failover scenario, rotating ownership
8. Periodically re-measured, accurate RTO/RPO documentation
9. A documented, tested FAILBACK process (often neglected)

[Question 110](../interview-questions/12-ha-dr.md#question-110-the-capstone-question--designing-hadr-from-a-blank-page)
