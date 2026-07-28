# Category 11: High Availability and Disaster Recovery

Questions 99–104 of 120. Category weight: 6 questions. Deep-dive reference: [`docs/ha-dr.md`](../docs/ha-dr.md).

---

## Question 99: Picking a DR strategy before picking a DR budget

### Scenario
A business stakeholder tells you a customer-facing checkout service needs "as little downtime as possible" during a regional AWS outage, but the engineering budget for DR infrastructure is limited, and nobody has actually stated a concrete RTO/RPO number.

### Interview Question
How do you turn "as little downtime as possible" into an actual DR architecture decision?

### Strong Senior-Level Answer
**Initial assessment:** "as little as possible" is not an engineering requirement — it's an unbounded aspiration that, taken literally, always justifies the most expensive option (active/active); the actual job here is translating vague stakeholder language into concrete RTO/RPO numbers the business is genuinely willing to pay for, since every DR strategy tier has a real cost/recovery-speed trade-off (see [`ha-dr.md` §2](../docs/ha-dr.md#2-dr-strategies-and-their-terraform-deployment-implications)).

**Technical reasoning:** the right approach is presenting the stakeholder with concrete options and their costs, not silently picking one on their behalf — e.g., "backup/restore gets you running again in hours for $X/month; pilot light gets you running in tens of minutes for $Y/month; warm standby gets you running in minutes for $Z/month; active/active gets you near-zero downtime for $W/month" — and letting the actual business impact of checkout downtime (revenue lost per minute of outage) inform which tier is actually justified.

**Investigation process:** quantify the real cost of downtime for this specific service (revenue per minute during peak/average traffic) to give the stakeholder a comparable number against each DR tier's cost — this reframes "as little downtime as possible" into "how much are we willing to pay to reduce downtime from X to Y," a decision the business can actually make with real numbers.

**Recommended solution:** present the tiered options with concrete RTO/RPO and cost estimates (using rough, clearly-caveated pricing that the stakeholder can verify), and let the business make an informed choice — likely landing on warm standby or pilot light for a revenue-critical checkout service, given "as little as possible" combined with "limited budget" suggests something less than active/active but more resilient than backup/restore.

**Risk controls:** whatever tier is chosen, get the RTO/RPO numbers explicitly documented and signed off on, so there's a concrete, agreed target to design against and later validate via drills (see [Question 100](#question-100-the-drill-that-told-an-uncomfortable-truth)) — not an ambiguous, retrospectively-argued-about expectation.

**Validation steps:** once built, the chosen tier's actual achieved RTO/RPO must be validated via a real drill, not assumed from the architecture diagram alone.

**Rollback or recovery strategy:** not applicable to this decision-making step itself; the chosen DR architecture's own recovery/failback process is designed per the tier selected.

**Long-term prevention:** establish RTO/RPO as a mandatory, explicit, numeric part of any service's requirements documentation going forward, so "as little downtime as possible" never has to be translated after the fact — it's captured as a concrete number from the start of any new service's design.

### Step-by-Step Implementation
```markdown
<!-- Stakeholder-facing options framing -->
| Tier | RTO | RPO | Est. monthly cost | 
|---|---|---|---|
| Backup/restore | Hours | Minutes-hours (backup frequency) | $ (lowest) |
| Pilot light | ~30-60 min | Near-zero (continuous data replication) | $$ |
| Warm standby | Minutes | Near-zero | $$$ |
| Active/active | Near-zero | Near-zero | $$$$ (highest) |

Revenue impact estimate: $[X] per minute of checkout downtime during peak traffic.
Recommendation: [tier], balancing revenue-loss avoidance against infrastructure cost.
```

### Under-the-Hood Explanation
This is fundamentally a business/cost-modeling exercise translated into an infrastructure decision — the Terraform-architecture implication (per [`ha-dr.md` §2](../docs/ha-dr.md#2-dr-strategies-and-their-terraform-deployment-implications)) follows directly from whichever tier is chosen: backup/restore needs no standing DR-region infrastructure at all (just a documented, tested "deploy from scratch" runbook); pilot light needs a minimal, scaled-down standing deployment with continuously-replicating data; warm standby needs a full-capacity standing deployment; active/active needs full production traffic actually flowing to both regions continuously. The Terraform work is comparatively straightforward once the tier is chosen — the hard part, and the actual senior-level skill being tested, is the business conversation that determines which tier is justified.

### Common Weak Answer
"Build active/active across two regions to guarantee the least downtime."

### Why the Weak Answer Fails
This ignores the explicitly-stated budget constraint and jumps to the most expensive tier without quantifying whether the actual business impact of downtime justifies that cost — a senior engineer's job includes right-sizing the solution to the actual, quantified business need, not defaulting to the technically-most-resilient option regardless of cost.

### Follow-Up Questions
1. How would you handle a stakeholder who, after seeing the cost breakdown, still insists on "as little downtime as possible" without committing to a specific tier's cost?
2. How would you revisit this decision if the service's revenue/criticality changes significantly over time?
3. What's the risk of choosing a DR tier based on cost alone without validating it can actually be built and drilled successfully?

### Key Interview Signals
Confirms the candidate can translate vague business language into a concrete, cost-aware technical decision framework, rather than either picking arbitrarily or deferring the decision back to the business without providing the information needed to make it.

### Hands-On Connection
[Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).

---

## Question 100: The drill that told an uncomfortable truth

### Scenario
Your organization's first-ever full DR drill (failing production traffic over to the warm-standby secondary region) reveals an actual RTO of 47 minutes, against a documented target of 5 minutes that leadership has been citing in customer-facing SLAs.

### Interview Question
What do you investigate first, and how do you handle the gap between the documented and actual RTO?

### Strong Senior-Level Answer
**Initial assessment:** a nearly 10x gap between documented and actual RTO means either the architecture doesn't actually deliver what "warm standby" is supposed to provide, or the failover *process* itself (not the infrastructure) has bottlenecks nobody accounted for — likely a combination, and the drill's specific value is exposing exactly where the real time went, rather than confirming an assumption.

**Technical reasoning:** break down the 47 minutes into its actual phases (detection/decision time, DNS/traffic-shift propagation, application startup/health-check time, data-layer promotion/consistency confirmation) — RTO is rarely dominated by a single cause, and the fix depends entirely on which phase actually consumed the most time.

**Investigation process:** review the drill's own timeline logs in detail — how long did it take to *decide* to fail over (often a significant, underestimated human/process component), how long did DNS changes actually take to propagate (frequently longer than assumed due to client-side caching/TTL, not just Route 53's own propagation), how long did the application take to become healthy in the secondary region (cold-start time if "warm standby" was actually running at reduced capacity requiring a scale-up), and how long did any data-layer promotion step take.

**Recommended solution:** address each bottleneck found: if DNS TTL was the dominant factor, reduce it well in advance of any future incident (DNS TTLs need to be low *before* an incident, not adjusted during one); if application cold-start dominated, increase the standby capacity closer to genuine "warm" (already running at production-ready scale, not needing a scale-up during failover); if decision-time dominated, establish clear, pre-authorized failover criteria and a designated decision-maker so the org isn't debating whether to fail over during the incident itself.

**Risk controls:** update the documented RTO to reflect reality immediately (47 minutes, not 5) while the architecture/process fixes are implemented — continuing to cite an unvalidated 5-minute RTO in customer SLAs after a drill has disproven it is a genuine business/compliance risk that needs escalating, not quietly working around.

**Validation steps:** after implementing the identified fixes, run a second drill and measure the new actual RTO against the target — only update the "achieved and validated" RTO figure based on an actual repeated drill result, not a theoretical estimate of how much the fixes should help.

**Rollback or recovery strategy:** not applicable to the drill itself; ensure the drill's own failback process (returning to primary) is equally measured and validated, not just the failover direction.

**Long-term prevention:** run DR drills on a regular, scheduled cadence (not just once) so RTO/RPO figures stay validated as the architecture and traffic patterns evolve — an architecture that achieved 5 minutes a year ago, if never re-drilled, provides no assurance it still does today.

### Step-by-Step Implementation
```text
Drill timeline breakdown (illustrative):
  00:00 - Incident declared
  00:00-00:12 - Decision-making: is this a genuine failover-worthy event? (12 min - largest single component)
  00:12-00:12 - Failover triggered (DNS record update applied)
  00:12-00:35 - DNS propagation across client caches (23 min - TTL was 3600s, not reduced beforehand)
  00:35-00:44 - Secondary region application scale-up from reduced standby capacity (9 min)
  00:44-00:47 - Health checks confirm full traffic serving (3 min)
  Total: 47 minutes
```
```hcl
# Fix: lower DNS TTL well in advance, and increase standby capacity to genuine "warm"
resource "aws_route53_record" "app" {
  ttl = 60   # reduced from 3600, well before any incident, not adjusted during one
}

resource "aws_autoscaling_group" "app_secondary" {
  min_size         = 4   # raised from 1 - genuinely "warm," not requiring cold scale-up
  desired_capacity = 4
}
```

### Under-the-Hood Explanation
RTO is the sum of every sequential phase in the actual failover process — detection/decision time (organizational, not infrastructural), DNS/traffic-shift propagation time (bounded by TTL and client-side caching behavior, which must be configured correctly *before* an incident since changing TTL during the incident doesn't retroactively affect already-cached client resolutions), infrastructure readiness time (how "warm" the standby genuinely is), and data-layer promotion time — Terraform's role is provisioning the infrastructure correctly for whichever tier is chosen, but it has no visibility into or control over the organizational/DNS-caching components of RTO, which is exactly why a real drill (not an architecture review) is the only way to discover the true, holistic RTO.

### Common Weak Answer
"Just tell customers the drill was a one-time issue and the real RTO is still 5 minutes."

### Why the Weak Answer Fails
This ignores concrete, measured evidence in favor of a previously-unvalidated assumption — citing an SLA figure that a real drill has just disproven is a genuine business and potentially compliance/contractual risk; the correct response is updating the documented figure to reality and fixing the actual bottlenecks, not dismissing inconvenient drill results.

### Follow-Up Questions
1. How would you prioritize which of the identified bottlenecks (decision time, DNS propagation, cold-start) to fix first, given each has a different cost/complexity to address?
2. How often should DR drills run, and how would you justify that cadence against the operational disruption of running them?
3. How would you handle a drill revealing that the *data layer* promotion (not infrastructure) was the dominant bottleneck, and what does that imply about your chosen replication mechanism?

### Key Interview Signals
Confirms the candidate treats a drill's uncomfortable result as valuable, actionable data (not something to explain away) and can decompose RTO into its actual constituent phases to target the real bottleneck rather than making an undifferentiated "improve DR" recommendation.

### Hands-On Connection
[Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).

---

## Question 101: The DR plan that needed Terraform, which needed the thing that just went down

### Scenario
During an actual regional AWS outage affecting `us-east-1`, your team attempts to execute the documented DR runbook — applying Terraform to scale up the secondary region's pilot-light infrastructure — only to discover the Terraform state backend (an S3 bucket in `us-east-1`) is itself unreachable due to the same regional outage.

### Interview Question
How did this gap get missed, and how do you fix the architecture to prevent it?

### Strong Senior-Level Answer
**Initial assessment:** this is a specific, well-known but frequently-missed DR planning gap — the DR architecture correctly addressed the *application* infrastructure's regional dependency but overlooked that the tool used to *execute* the DR runbook (Terraform, via its state backend) had exactly the same single-region dependency it was trying to design around.

**Technical reasoning:** the state backend needs its own DR consideration, independent of and prior to the application-layer DR design — if Terraform itself can't run during the exact kind of event the DR plan exists for, the entire runbook is unexecutable precisely when needed most.

**Investigation process:** confirm this gap doesn't also exist for any other tooling the DR runbook depends on (a CI/CD platform region, a secrets manager, a monitoring system) — state backend unavailability is the most direct Terraform-specific instance of a broader "does our incident-response tooling share fate with the thing it's supposed to help us recover from" question.

**Recommended solution:** enable cross-region replication on the state bucket (S3 Cross-Region Replication to a bucket in the secondary region), and update the DR runbook to explicitly document falling back to the replicated bucket's region (via a backend configuration override, or a documented `-backend-config` override at apply time) if the primary region's state backend is unreachable during an actual DR event. Test this fallback explicitly as part of your next DR drill, not just as a theoretical architecture note.

**Risk controls:** ensure the locking mechanism also has a cross-region-viable fallback story — if using DynamoDB-based locking, consider a DynamoDB Global Table for the lock table so locking remains available in the secondary region too, not just the state objects themselves.

**Validation steps:** during the next scheduled DR drill, deliberately simulate the primary region's state backend being unreachable and confirm the documented fallback procedure (pointing Terraform at the replicated bucket) actually works end-to-end, not just that replication is technically enabled.

**Rollback or recovery strategy:** for the actual incident in this scenario, the immediate recovery is manually reconfiguring the backend to point at the replica bucket's region (a one-time, deliberate, careful action, understanding this touches your most sensitive infrastructure-management surface) to unblock executing the rest of the DR runbook.

**Long-term prevention:** treat "does every tool in our incident-response chain (Terraform state, CI/CD platform, secrets manager, monitoring) have a plan for the exact regional-outage scenario our DR runbook addresses" as a standing, explicit checklist item for DR architecture reviews, specifically because this class of "the tool needed to recover shares the same failure domain as what needs recovering" gap is easy to miss when each layer is designed by looking only at its own dependencies in isolation.

### Step-by-Step Implementation
```json
// S3 Cross-Region Replication configuration for the state bucket
{
  "Role": "arn:aws:iam::...:role/s3-replication-role",
  "Rules": [{
    "Status": "Enabled",
    "Destination": { "Bucket": "arn:aws:s3:::tf-state-us-west-2-replica" }
  }]
}
```
```bash
# Documented fallback procedure for the DR runbook
terraform init -backend-config="bucket=tf-state-us-west-2-replica" -backend-config="region=us-west-2" -reconfigure
terraform plan   # proceed using the replicated bucket as the working backend during the regional outage
```

### Under-the-Hood Explanation
S3 Cross-Region Replication asynchronously copies new/updated objects from a source bucket to a destination bucket in a different region as part of AWS's own managed replication service — this happens independently of Terraform, meaning the replica bucket's contents (including state object versions) stay current with a small replication lag, giving Terraform a viable alternate backend target if the primary region's bucket becomes unreachable. The `-reconfigure`/`-backend-config` override lets you point an existing working directory at a different backend location without needing to redo the full `init` setup from scratch during an actual incident, provided the replicated state is genuinely current enough to trust.

### Common Weak Answer
"We'll just wait for the region to recover before running the DR runbook."

### Why the Weak Answer Fails
This defeats the entire purpose of having a DR plan for a regional outage — if you can only execute the DR runbook once the outage causing the need for it has already resolved, the DR plan provides zero actual protection during the exact event it exists to address.

### Follow-Up Questions
1. How would you handle the small replication lag between the primary state bucket and its cross-region replica — could this cause you to apply against slightly stale state during a real incident?
2. What other tooling in your incident-response chain should be audited for this same "shares fate with what it's recovering from" gap?
3. How would this design change if you were using Terraform Cloud/Enterprise instead of a self-managed S3 backend?

### Key Interview Signals
Confirms the candidate recognizes this specific, easy-to-miss class of DR planning gap (the recovery tool itself depending on the thing being recovered from) and designs a concrete, testable fix (cross-region state replication plus a documented, drilled fallback procedure) rather than treating it as an edge case not worth addressing.

### Hands-On Connection
[Lab 2 — Secure Remote State](../labs/lab-02-remote-state/) and [Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).

---

## Question 102: The failback that found two versions of the truth

### Scenario
After a successful DR failover (traffic served entirely from the secondary region for six hours during a primary-region outage), the primary region recovers and your team begins the failback process — only to discover the secondary region's database accumulated writes during the six-hour window that now need to be reconciled with the primary region's database, which itself has slightly stale data from before the failover.

### Interview Question
How do you approach this reconciliation, and how does your DR architecture choice affect how hard this problem is?

### Strong Senior-Level Answer
**Initial assessment:** this reconciliation difficulty is a direct consequence of the data-layer replication model chosen for this DR architecture — the difficulty (and whether it's even a real conflict-resolution problem or a straightforward one-directional sync) depends entirely on whether the data layer supports genuine multi-master writes or was designed as one-directional replication that was never expected to have the "wrong" side accumulate writes.

**Technical reasoning:** if the data layer is something like DynamoDB Global Tables (genuinely multi-master, designed for exactly this kind of bidirectional-write scenario with built-in last-writer-wins conflict resolution), reconciliation is largely automatic, though "last writer wins" itself has implications worth understanding (a write to primary during the outage window that's older than a corresponding write to secondary could be silently overwritten). If the data layer is an RDS read-replica-based setup (asynchronous, one-directional, primary-to-replica under normal operation) that was promoted to standalone-primary during the failover, the six hours of writes now sitting in the (formerly-replica, now-standalone) secondary database need a genuine, likely partially-manual reconciliation against the primary's pre-failover state — RDS wasn't designed for this direction of sync, so there's no automatic mechanism.

**Investigation process:** determine exactly which data changed in each region during the divergence window (query-based diffing, or application-level audit logs if available) to scope the actual reconciliation work — is this a small, easily-reconcilable set of writes, or a large, complex one?

**Recommended solution:** for an RDS-based one-directional-replication architecture, the practical failback approach is usually: treat the (now-standalone) secondary's database as authoritative going forward (since it has the most complete, current data including the six hours of writes), re-establish it as the primary, and rebuild the original primary region as the new *replica* — rather than trying to merge the old primary's slightly-stale pre-failover state back in, which is usually more complex and error-prone than simply continuing with the region that has the complete data and re-establishing replication in the new direction.

**Risk controls:** whichever reconciliation approach is chosen, validate data integrity thoroughly (row counts, checksums on critical tables, application-level sanity checks) before considering failback complete and directing full production traffic back with confidence.

**Validation steps:** run application-level validation (not just infrastructure health checks) confirming the reconciled/re-established primary serves correct, complete data before shifting full traffic back.

**Rollback or recovery strategy:** if reconciliation reveals data conflicts too complex to resolve automatically, be prepared to continue operating from the (now-standalone) secondary region longer than planned while the reconciliation is worked through carefully, rather than rushing a failback that risks data integrity.

**Long-term prevention:** if this scenario is a plausible outcome for a business-critical service, that's a strong argument for choosing a genuinely multi-master data-replication technology (DynamoDB Global Tables, or a database engine designed for active/active) from the start, specifically to avoid the complex, largely-manual reconciliation burden that one-directional-replication architectures impose during failback — factor this into the DR strategy decision (Question 99) explicitly, not just RTO/RPO for the failover direction alone.

### Step-by-Step Implementation
```bash
# Assess scope of divergence (illustrative, RDS-based one-directional replication case)
# Compare row counts/checksums for critical tables between the two databases
psql -h primary-db -c "SELECT count(*), max(updated_at) FROM orders;"
psql -h secondary-db -c "SELECT count(*), max(updated_at) FROM orders;"
```
```text
Recommended failback approach for one-directional (RDS-style) replication:
  1. Treat the (now-standalone) secondary as authoritative - it has the complete data
  2. Re-establish it as the new primary
  3. Rebuild the original primary region's database as a new replica, syncing FROM
     the (new) primary - the reverse of the original replication direction
  4. Validate data integrity thoroughly before considering failback complete
```

### Under-the-Hood Explanation
DynamoDB Global Tables implement multi-master replication with built-in, automatic conflict resolution (last-writer-wins, based on timestamps) specifically because they're designed to support writes accepted in multiple regions simultaneously — this is a genuine architectural capability of the service, not something Terraform provides or manages beyond provisioning the Global Table resource itself. RDS's standard cross-region read replica mechanism, by contrast, is fundamentally one-directional (primary writes propagate to replica) and has no built-in mechanism for accepting and later reconciling writes made directly against a promoted replica — this asymmetry between data-replication technologies is precisely why the failback difficulty in this question is a direct consequence of the data-layer choice, not something Terraform's infrastructure-provisioning role can smooth over regardless of how well the failover/failback Terraform configuration itself is written.

### Common Weak Answer
"Just copy the primary's data back over the secondary's to restore consistency."

### Why the Weak Answer Fails
This would discard the six hours of legitimate writes that occurred against the secondary during the failover window — real customer data (orders, transactions) that the business needs preserved, not overwritten with stale pre-failover data; the correct approach preserves the more-complete data set (the secondary's) rather than naively reverting to the older, less-complete primary.

### Follow-Up Questions
1. How would you handle a failback scenario where the data layer is something in between full multi-master and pure one-directional replication (e.g., a database with limited bidirectional sync support)?
2. What application-level changes (idempotency keys, conflict-resolution logic) could make this reconciliation easier regardless of the underlying data-replication technology?
3. How would you communicate the risk of this reconciliation complexity to stakeholders *before* choosing a DR data-replication strategy, so it's a known trade-off rather than a surprise during an actual failback?

### Key Interview Signals
Confirms the candidate connects the failback reconciliation difficulty directly to the specific data-replication technology's capabilities (multi-master vs. one-directional), and recommends preserving the more-complete data set rather than a naive "restore the old primary" approach that would silently discard legitimate recent writes.

### Hands-On Connection
[Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).

---

## Question 103: Multi-AZ isn't multi-region

### Scenario
During a post-incident review after a full regional AWS service disruption, a stakeholder is surprised the application went down at all, pointing out that the RDS database is configured Multi-AZ, which they believed meant it was "protected against outages."

### Interview Question
Clarify the actual scope of what Multi-AZ protects against, and use this to explain the difference between HA and DR to the stakeholder.

### Strong Senior-Level Answer
**Initial assessment:** this is a common and understandable confusion — Multi-AZ RDS is a genuine, valuable **high-availability** feature (protecting against AZ-level failures — a single data center's outage, hardware failure, or an AZ-scoped network issue) but provides **no protection whatsoever against a full regional outage**, since all of a Multi-AZ deployment's AZs are still within the same AWS region.

**Technical reasoning:** HA (high availability) and DR (disaster recovery) address different failure scopes — HA is about surviving failures *within* a region (an AZ going down, an instance failing) with typically fast, often fully-automatic recovery; DR is about surviving the loss of an *entire region*, which requires infrastructure and data replicated to a genuinely separate region, which Multi-AZ, by definition, does not provide.

**Investigation process:** confirm exactly what happened during the incident — was this genuinely a full regional service disruption (affecting all AZs within the region) as the scenario states, which is precisely the scope Multi-AZ was never designed to address, distinguishing it clearly from a single-AZ failure (which Multi-AZ *would* have handled automatically, with no customer-visible impact).

**Recommended solution:** explain this distinction clearly to the stakeholder using the actual incident as the concrete example: "Multi-AZ protected us against a single data center failing — if that had happened, our database would have failed over automatically within about a minute with no customer impact. What actually happened was a full regional issue, which is a different, much larger-scope failure that Multi-AZ was never designed to protect against — that requires actual disaster recovery infrastructure in a separate region, which is a separate investment decision (see [Question 99](#question-99-picking-a-dr-strategy-before-picking-a-dr-budget))." If the business determines regional-outage protection is now warranted for this service (which this incident may well justify), that's the trigger for a genuine DR architecture conversation, not an expectation that Multi-AZ should have somehow covered it.

**Risk controls:** audit other services/stakeholders for the same Multi-AZ-equals-DR misconception, since it's a common one — proactively clarifying this distinction for every business-critical service, rather than only after an incident exposes the gap for one specific service.

**Validation steps:** confirm the stakeholder's understanding has actually been corrected (not just that you delivered the explanation) by checking their subsequent expectations/questions reflect the HA-vs-DR distinction going forward.

**Rollback or recovery strategy:** not applicable — this is a clarification/education exercise following the incident, not an infrastructure change (unless the incident review concludes DR investment is now warranted, which becomes its own separate initiative).

**Long-term prevention:** include an explicit "this is what we're protected against, and this is what we're not" statement in every service's architecture documentation and periodic stakeholder communication, so the HA/DR scope of any given configuration is stated proactively rather than discovered as a surprise during a real incident.

### Step-by-Step Implementation
```markdown
<!-- Stakeholder-facing clarification -->
**What Multi-AZ RDS protects against:** a single Availability Zone failing (a data
center outage, hardware failure, AZ-scoped network issue). Automatic failover,
typically ~60-120 seconds, no customer-visible data loss.

**What Multi-AZ RDS does NOT protect against:** a full AWS region becoming
unavailable, since every AZ in a Multi-AZ deployment is within the same region.

**What actually happened in this incident:** a [regional service disruption],
which is outside Multi-AZ's protection scope. This is exactly what disaster
recovery (DR) architecture — infrastructure replicated to a separate region —
is designed to address, and is a separate investment decision from HA.
```

### Under-the-Hood Explanation
RDS Multi-AZ works by synchronously replicating to a standby instance in a *different Availability Zone within the same region*, with automatic detection and failover to that standby if the primary AZ's instance becomes unreachable — this entirely depends on the region's other AZs remaining operational, which is precisely why it provides no protection when the disruption affects the region as a whole (all AZs simultaneously, or a regional control-plane/service-level issue rather than an AZ-scoped hardware/network failure) rather than a single AZ specifically.

### Common Weak Answer
"Multi-AZ should have handled this — maybe it was misconfigured."

### Why the Weak Answer Fails
This assumes Multi-AZ was supposed to cover a scope it was never designed for, potentially leading to an unproductive investigation looking for a "misconfiguration" that doesn't exist — the actual explanation is a scope mismatch between what Multi-AZ provides (AZ-level HA) and what the stakeholder expected (regional DR), not a configuration defect.

### Follow-Up Questions
1. How would you design a service's documentation to make its actual HA/DR scope unambiguous to non-specialist stakeholders from the start?
2. What's the cost/complexity difference between adding genuine regional DR for this service versus accepting the risk of a full regional outage given its actual business criticality?
3. How would you explain the same HA-vs-DR distinction for a different resource type, like an EKS cluster with multi-AZ node groups?

### Key Interview Signals
Confirms the candidate can clearly explain the HA/DR scope distinction to a non-specialist audience using the actual incident as a concrete teaching example, without either dismissing the stakeholder's concern or agreeing there was a misconfiguration where none exists.

### Hands-On Connection
[Lab 8 — AWS Networking Platform](../labs/lab-08-aws-networking/) and [Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).

---

## Question 104: DR on a budget, for something that still matters

### Scenario
An internal tool (an engineering metrics dashboard, not customer-facing, but genuinely useful to several teams' daily workflow) currently has no DR plan at all. Leadership acknowledges it's "nice to have back quickly" after a regional outage but explicitly won't approve budget for a full warm-standby architecture given the tool's non-critical, internal-only nature.

### Interview Question
Design a cost-conscious DR approach appropriate for this tool's actual criticality.

### Strong Senior-Level Answer
**Initial assessment:** this tool's stated criticality ("nice to have back quickly" but not business-critical, no explicit RTO/RPO SLA, limited budget) maps clearly to the backup/restore tier (see [`ha-dr.md` §2](../docs/ha-dr.md#2-dr-strategies-and-their-terraform-deployment-implications)) — the cheapest tier, with no standing DR-region infrastructure at all, just a documented, tested "redeploy from scratch" runbook, appropriately matched to genuinely low criticality rather than over-engineering a response this tool doesn't warrant.

**Technical reasoning:** since the same Terraform module set already used for this tool's primary-region deployment can, in principle, be applied to a different region's provider configuration on demand, the actual "DR investment" here is almost entirely about *making that redeploy-elsewhere path genuinely fast and reliable when actually needed*, not about pre-provisioning any standing secondary-region infrastructure.

**Investigation process:** confirm the tool's data layer (metrics data) has *some* backup mechanism already, even if minimal (a periodic export/snapshot) — even a low-criticality tool benefits from not needing to fully reconstruct historical data from nothing during a recovery.

**Recommended solution:** ensure the tool's Terraform configuration is genuinely region-parameterized (no hardcoded region-specific values) so a "deploy this to `us-west-2` instead" is a one-variable change, not a manual reconstruction exercise; ensure the tool's data has periodic backups exported to a location with its own cross-region durability (e.g., an S3 bucket with cross-region replication, cheap given the tool's likely modest data volume); and, critically, **actually test the "redeploy from scratch" runbook at least once** (even if not on an ongoing drill cadence given the low priority) so it's a proven, not just theoretical, capability — a backup/restore DR plan that's never been executed is exactly as much of an unvalidated hypothesis as a warm-standby architecture that's never been drilled (see [Question 100](#question-100-the-drill-that-told-an-uncomfortable-truth)), just cheaper to eventually validate.

**Risk controls:** set honest expectations with the tool's users about the actual recovery time this approach implies (likely hours, not minutes) — matching the "nice to have back quickly, not critical" framing leadership already gave, rather than either over-promising or leaving the actual recovery time undefined.

**Validation steps:** the one-time test deployment to a different region, from the backup, is the validation — confirming the region-parameterization actually works and the data restore actually produces a usable dashboard, not just a theoretical belief that it would.

**Rollback or recovery strategy:** the runbook itself (region-parameterized redeploy plus data restore from the periodic export) is the recovery strategy for this tier — there's no faster failover path being built, deliberately, given the tool's assessed criticality.

**Long-term prevention:** revisit this decision if the tool's actual usage/criticality grows over time (e.g., if it becomes load-bearing for an on-call/incident-response workflow, which would argue for a higher DR tier) — criticality assessments shouldn't be treated as permanent, especially for internal tools whose usage patterns can shift.

### Step-by-Step Implementation
```hcl
# Ensure genuine region-parameterization - no hardcoded region-specific values
variable "region" {
  type = string
}

provider "aws" {
  region = var.region
}
# Same module set, deployable to any region via a one-variable change
```
```bash
# Periodic, cheap data export with cross-region durability
aws s3 sync /var/lib/metrics-dashboard-data/ s3://metrics-dashboard-backups/ --delete
# Bucket configured with cross-region replication to a secondary region, low cost given modest data volume
```
```bash
# One-time validation: actually redeploy from scratch to a different region and restore data
terraform apply -var="region=us-west-2"
aws s3 sync s3://metrics-dashboard-backups/ /var/lib/metrics-dashboard-data/
# Confirm the dashboard comes up correctly and data is usable
```

### Under-the-Hood Explanation
This is the direct, deliberate application of the lowest DR tier (backup/restore) rather than any special mechanism — the key engineering discipline is ensuring the *ordinary* Terraform module set has no hidden regional assumptions baked in (hardcoded AZs, region-specific AMI IDs without a lookup, hardcoded ARNs referencing region-specific resources) that would silently break a "just redeploy elsewhere" attempt when actually needed; validating this via one real test deployment is what converts "should theoretically work" into "has been proven to work," at minimal ongoing cost given the low-frequency validation cadence appropriate for this tool's actual criticality.

### Common Weak Answer
"Since there's no budget, just accept the tool will be unavailable during a regional outage with no plan at all."

### Why the Weak Answer Fails
This overcorrects in the other direction — "limited budget" and "not business-critical" don't mean "no DR consideration is worthwhile at all"; a backup/restore-tier approach costs very little (mostly just engineering discipline around region-parameterization and a cheap, periodic data export) while still providing a real, validated recovery path appropriately matched to the tool's actual criticality, which is a better outcome than leadership's stated tolerance ("nice to have back quickly") would otherwise get with zero DR planning.

### Follow-Up Questions
1. How would you decide when this tool's criticality has grown enough to warrant moving up to a higher DR tier?
2. What's the actual cost of the one-time validation test (region redeploy plus data restore) compared to the cost of never knowing whether the "plan" would actually work?
3. How would you apply this same low-cost, backup/restore-tier discipline across many similar internal tools without repeating this full analysis for each one individually?

### Key Interview Signals
Confirms the candidate right-sizes the DR investment to the tool's actual, stated criticality (neither over-engineering nor abandoning DR planning entirely under budget constraints) and insists on at least one real validation test regardless of how low-priority the tool is, since an untested plan provides no real assurance at any tier.

### Hands-On Connection
[Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).
