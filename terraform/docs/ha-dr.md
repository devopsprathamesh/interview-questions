# High Availability and Disaster Recovery

HA/DR questions test whether a candidate can connect Terraform mechanics to actual business risk — RTO/RPO targets, cost trade-offs, and what "recovery" really requires beyond re-running `terraform apply`. This document backs [`interview-questions/11-ha-dr.md`](../interview-questions/11-ha-dr.md) and is exercised in [Lab 8](../labs/lab-08-aws-networking/), [Lab 9](../labs/lab-09-eks-infrastructure/), and [Lab 15](../labs/lab-15-enterprise-capstone/).

## 1. HA within a single region — Terraform's role

High availability within a region is mostly an **architecture decision expressed through Terraform**, not a Terraform feature per se: multi-AZ subnets, ASGs/node groups spread across AZs, multi-AZ RDS (synchronous standby), ALB health checks routing around unhealthy targets. Terraform's job is to make these decisions **structural and consistent** — e.g., a VPC module that takes a list of AZs and produces one subnet/NAT/route-table set per AZ via `for_each` (never `count`, given the index-shifting risk from [`terraform-internals.md` §4](terraform-internals.md#4-count-vs-for_each--and-the-index-shifting-failure-mode)) means HA isn't something an engineer has to remember to configure correctly each time — it's the module's default shape.

## 2. DR strategies and their Terraform deployment implications

| Strategy | RTO | RPO | Cost | Terraform implication |
|---|---|---|---|---|
| Backup/restore | Hours | Depends on backup frequency | Lowest | DR region has **no standing infrastructure**; recovery = `terraform apply` from scratch against the DR region's provider alias, then restore data from backups. Slowest but cheapest. |
| Pilot light | Tens of minutes | Minutes (near-continuous data replication) | Low-medium | Core data infrastructure (e.g., an RDS read replica) exists and stays synced in DR; compute layer is scaled to near-zero. Recovery = `terraform apply` to scale up compute (change instance counts/sizes) plus promote the data layer. |
| Warm standby | Minutes | Near-zero | Medium-high | Full stack running at reduced capacity in DR at all times. Recovery = traffic shift (DNS/load balancer), plus a scale-up apply. |
| Active/active (multi-site) | Near-zero | Near-zero | Highest | Full stack running at full capacity in both/all regions continuously, traffic distributed normally. "Recovery" from a regional loss is just traffic routing around it — no apply needed in the moment. |

**The deployment implication that matters for an interview:** whichever strategy is chosen, the DR region's infrastructure should be defined with the **exact same modules** used for primary, parameterized by region/account (see [Diagram 9](../diagrams/09-multi-region.md) and [`terraform-architecture.md` §12](terraform-architecture.md#12-disaster-recovery-architecture)) — never a separately hand-maintained copy that drifts out of sync with primary over time and turns out to be broken exactly when you need it during a real incident.

## 3. What Terraform does *not* solve for DR

- **Data recovery point** — Terraform manages infrastructure shape, not your data's replication/backup state. RDS snapshots, cross-region replication, S3 replication, DynamoDB global tables are configured *through* Terraform resources, but the actual RPO guarantee comes from the replication mechanism's own behavior, not from Terraform re-running.
- **DNS/traffic cutover speed** — often the actual bottleneck in a "warm standby" recovery is DNS TTL and client-side caching, not how fast Terraform can apply. Plan and test cutover time realistically, not just infrastructure-provisioning time.
- **In-flight state during the disaster** — if the primary region's Terraform state backend is *also* down (e.g., you host state in the same region you're failing over from), you can't even run `terraform plan`/`apply` against DR during the incident. **State backend placement/replication must itself be part of the DR design** — cross-region state bucket replication, or a backend architecture that isn't single-region-dependent, is a frequently-missed detail in DR planning that's an excellent thing to raise proactively in an interview.

## 4. HA/DR testing — the gap between "designed" and "proven"

A DR plan that has never actually been executed is a hypothesis, not a capability. Senior-level DR maturity includes **regular, scheduled DR drills** (failing over to the DR region on a controlled schedule, measuring actual RTO/RPO against targets, then failing back) — not just architecture diagrams. This is the same distinction as testing Terraform code (see [`testing.md`](testing.md)): untested infrastructure-as-code and untested DR procedures fail in the same way — silently, until the moment you need them.

## 5. Failback

Failback (returning to the primary region after it's restored) is a full, deliberate second exercise of the same recovery process in reverse, not an assumption that traffic reverts automatically. It requires: confirming primary infrastructure is genuinely healthy (not just "the region API is reachable again"), reconciling any data written to DR during the incident back to primary (a real data-sync problem, potentially with conflicts if writes happened in both places), and a controlled, monitored traffic shift back — see [Diagram 15](../diagrams/15-disaster-recovery.md).

## Common weak answer vs. senior answer

| Scenario | Weak answer | Senior answer |
|---|---|---|
| "How would you design DR for this platform?" | "Deploy the same Terraform to a second region" | Choose a strategy (backup/restore, pilot light, warm standby, active/active) based on actual RTO/RPO business requirements and cost tolerance, and make the deployment implication concrete — what's pre-provisioned vs. what happens at failover time |
| "Is your DR plan solid?" | "Yes, we can redeploy to another region" | DR maturity is proven by scheduled drills with measured RTO/RPO against targets, not by an untested architecture diagram |
| State backend during a regional outage | (not considered) | The state backend itself needs a DR design — if it's single-region and down, you can't even run Terraform against the DR region during the incident |

## Related material
- Interview questions: [`interview-questions/11-ha-dr.md`](../interview-questions/11-ha-dr.md)
- Hands-on: [Lab 8 — AWS Networking Platform](../labs/lab-08-aws-networking/), [Lab 9 — Amazon EKS Infrastructure](../labs/lab-09-eks-infrastructure/), [Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/)
- Diagrams: [`diagrams/09-multi-region.md`](../diagrams/09-multi-region.md), [`diagrams/15-disaster-recovery.md`](../diagrams/15-disaster-recovery.md)
