# Category 12: High Availability and Disaster Recovery

Questions 105–110 of 120. Category weight: 6 questions. Deep-dive reference: [`docs/ha-dr.md`](../docs/ha-dr.md).

---

## Question 105: Three replicas, one AZ

### Scenario
A critical Deployment runs 3 replicas across a node group spanning 3 AZs, with no topology spread constraint or anti-affinity configured. An AZ outage takes down all 3 replicas simultaneously, since the scheduler's default bin-packing had placed all 3 on nodes within that single AZ.

### Interview Question
Diagnose why "3 replicas across a 3-AZ node group" didn't provide the expected resilience.

### Strong Senior-Level Answer
**Initial assessment:** per [`docs/ha-dr.md`](../docs/ha-dr.md) §2, spreading *nodes* across AZs is necessary but not sufficient for workload resilience — without an explicit topology spread constraint or anti-affinity rule, the scheduler's default placement logic has no obligation to distribute a specific Deployment's replicas evenly across those AZs, and can (as happened here) concentrate them all in one, entirely by coincidence of scheduling order and available capacity at deployment time.

**Technical reasoning:** the scheduler's default behavior optimizes for factors like resource balance and existing pod distribution generally, but has no built-in guarantee about *any specific workload's* per-AZ replica distribution unless explicitly told to enforce one — three replicas landing in the same AZ is an entirely plausible, unremarkable outcome under default scheduling, not a bug or unusual coincidence.

**Investigation process:** confirm via `kubectl get pods -o wide` (cross-referencing node-to-AZ mapping) that all 3 replicas were indeed in the same AZ at the time of the outage — settling that this was a genuine distribution failure, not a different underlying cause.

**Recommended solution:** add an explicit `topologySpreadConstraint` (per [`diagrams/01-control-plane-data-plane.md`](../diagrams/01-control-plane-data-plane.md)'s broader AZ-awareness theme and Question 56's mechanics) with `maxSkew: 1` across `topology.kubernetes.io/zone`, ensuring future scheduling decisions for this Deployment genuinely distribute replicas across all 3 AZs rather than leaving it to chance.

**Risk controls:** for genuinely critical workloads, consider `whenUnsatisfiable: DoNotSchedule` (a hard constraint, per Question 56) rather than `ScheduleAnyway`, if the resilience guarantee is important enough to warrant blocking scheduling rather than risking uneven distribution under capacity pressure.

**Validation steps:** after adding the constraint, confirm (via a deliberate redeploy/scale test) that replicas are indeed evenly distributed across all 3 AZs, and confirm a simulated single-AZ node cordon (removing that AZ's capacity from consideration) still leaves the remaining replicas serving traffic without a full outage.

**Rollback or recovery strategy:** for the immediate incident, once the affected AZ recovers, confirm replicas reschedule and redistribute correctly (ideally now with the topology spread constraint in place preventing recurrence).

**Long-term prevention:** audit every genuinely critical workload across the cluster for the presence of an appropriate topology spread constraint, treating its absence as a real, checkable AZ-resilience gap — never assuming "our node group spans 3 AZs" alone provides the workload-level resilience it implies without explicit placement constraints.

### Step-by-Step Implementation
```yaml
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule   # hard constraint for a genuinely critical workload
    labelSelector:
      matchLabels: { app: critical-service }
```

### Under-the-Hood Explanation
The Kubernetes scheduler evaluates each pod's placement independently against its own declared constraints — without an explicit `topologySpreadConstraint`, nothing in the scheduler's logic considers "how many replicas of this exact Deployment already exist in each AZ" as a placement factor at all, meaning replica distribution across AZs is an unintended emergent property of whatever other scheduling factors happen to apply, not a deliberate, guaranteed outcome.

### Common Weak Answer
"Multi-AZ node groups automatically make workloads resilient to AZ failures."

### Why the Weak Answer Fails
This conflates node-level AZ distribution (a property of the node group's own subnet configuration) with workload-level replica distribution (a property requiring explicit scheduling constraints) — exactly the distinction this incident demonstrates matters, since the node group's multi-AZ span provided zero actual protection without a corresponding topology spread constraint on the workload itself.

### Follow-Up Questions
1. How would you audit an entire fleet of workloads for missing topology spread constraints efficiently?
2. What's the trade-off of `DoNotSchedule` versus `ScheduleAnyway` specifically for this critical workload?
3. How would you test AZ-failure resilience proactively (a chaos-engineering-style AZ-outage simulation) rather than discovering a gap only during a real outage?

### Key Interview Signals
Precisely distinguishes node-level multi-AZ spread from workload-level replica distribution, correctly diagnosing the missing topology spread constraint as the actual gap.

### Hands-On Connection
[Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).

---

## Question 106: The DR cluster that was ready, except for the part that mattered

### Scenario
An organization's DR-region EKS cluster is kept warm via the same GitOps repository as production, correctly running identical application configuration at all times. During an actual regional failover drill, the application starts successfully but immediately fails — its database (a separate, primary-region-only RDS instance with no cross-region replica) is unreachable from the DR region.

### Interview Question
Diagnose this DR gap and explain what GitOps-based configuration parity does and doesn't provide.

### Strong Senior-Level Answer
**Initial assessment:** per [`docs/ha-dr.md`](../docs/ha-dr.md) §6, GitOps-based configuration parity (the same manifests reconciled in both regions) correctly ensures the *application configuration* is identical and ready in both regions — but it does nothing to address *data* replication, which requires its own, entirely separate mechanism; this DR test correctly exposed exactly that gap.

**Technical reasoning:** the DR cluster's GitOps controller successfully reconciled the same Deployment/Service/ConfigMap manifests as production, meaning the *application layer* was genuinely ready — but the database dependency, being a stateful, primary-region-only resource with no cross-region replication configured, was never actually part of what GitOps parity covers at all, since GitOps only manages Kubernetes-level resources, not the underlying RDS instance's own replication topology.

**Investigation process:** confirm this was indeed the actual gap (no cross-region read replica, no cross-region backup/restore mechanism for the database) — and separately assess whether *any* part of the DR plan had accounted for data replication at all, or whether this was an entirely unaddressed assumption.

**Recommended solution:** implement actual cross-region data replication for the database (an RDS cross-region read replica, promotable to primary during a genuine regional failover, provisioned and managed via the companion Terraform repository's multi-region database guidance) — this is an infrastructure-level, Terraform-managed concern, entirely separate from and not addressed by the GitOps-managed application configuration parity that was already correctly in place.

**Risk controls:** for any DR architecture, explicitly enumerate every stateful dependency (databases, persistent storage per [`docs/storage.md`](../docs/storage.md), any other data store) and confirm each has its own explicit, tested cross-region replication/recovery mechanism — application-configuration parity alone, however well-implemented via GitOps, never covers this.

**Validation steps:** after implementing database replication, re-run the DR failover drill and confirm the application in the DR region can now actually reach and use a genuinely current (or acceptably-recent) copy of its data, not just successfully start with its configuration correct but no usable data behind it.

**Rollback or recovery strategy:** not applicable to the gap itself — this is a DR-readiness gap requiring the described infrastructure addition, not a change with its own rollback consideration.

**Long-term prevention:** treat "does our DR test actually exercise the full dependency chain, including data, not just application configuration" as the standard bar for any DR drill — a DR test that only confirms application configuration parity (as GitOps naturally provides) without also validating actual data availability gives a dangerously incomplete picture of genuine DR-readiness, exactly as this drill demonstrated.

### Step-by-Step Implementation
```hcl
# Terraform - cross-region RDS read replica as part of the DR architecture
resource "aws_db_instance" "dr_replica" {
  replicate_source_db = aws_db_instance.primary.arn
  # provisioned in the DR region, promotable during an actual failover
}
```

### Under-the-Hood Explanation
GitOps's continuous reconciliation (per [`docs/cicd-gitops.md`](../docs/cicd-gitops.md) §1) operates entirely at the Kubernetes API level — it has no awareness of, and no mechanism to manage, an external AWS resource like an RDS instance's replication topology; "the same manifests reconciled in both regions" genuinely guarantees identical *application* configuration, but says absolutely nothing about whether the *data* those applications depend on has any cross-region presence at all, which is a distinct, infrastructure-level concern requiring its own explicit design and tooling (Terraform, RDS's own replication features).

### Common Weak Answer
"Our GitOps setup keeps both regions identical, so we should be DR-ready."

### Why the Weak Answer Fails
This conflates application-configuration parity (genuinely provided by GitOps) with full DR-readiness (which additionally requires data replication, a completely separate concern GitOps has no mechanism to address) — exactly the false confidence this drill's discovery corrects.

### Follow-Up Questions
1. How would you design and test the actual failover/promotion process for the cross-region database replica during a real regional outage?
2. What's the RPO (recovery point objective) trade-off of an asynchronous cross-region read replica versus other replication approaches?
3. How would you extend this same "GitOps covers config, not data" awareness check to other stateful dependencies beyond the database?

### Key Interview Signals
Precisely distinguishes what GitOps-based configuration parity actually guarantees (application config) from what it doesn't (data replication), correctly attributing this DR gap to an entirely separate, unaddressed infrastructure concern.

### Hands-On Connection
[Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).

---

## Question 107: The failover that failed over to nothing

### Scenario
A Route 53 failover routing policy is configured to redirect traffic to the DR-region cluster's Ingress if the primary region's health check fails. During an actual primary-region outage, Route 53 correctly fails over — but the DR cluster's own Karpenter has `minReplicas: 0`-equivalent node pools that had scaled down to zero nodes during the long idle period since the last drill, and takes 8 minutes to provision capacity before the application can actually serve any traffic.

### Interview Question
Diagnose this cold-start gap in the DR failover and design the fix.

### Strong Senior-Level Answer
**Initial assessment:** a DR cluster that's cost-optimized down to zero standing capacity during normal (non-failover) operation trades cost savings for exactly this kind of failover-latency gap — Route 53's DNS-level failover is nearly instantaneous, but it's only as useful as the DR region's actual ability to serve traffic *immediately* upon receiving it, and an 8-minute cold-start negates much of the value of a fast DNS failover if the business's actual recovery-time objective is tighter than that.

**Technical reasoning:** Karpenter's cost-optimized scale-to-zero behavior for idle node pools (a genuinely good practice for reducing standing DR-cluster cost during normal operation) directly conflicts with the need for the DR cluster to have *some* immediately-available capacity the moment a failover actually occurs — this is a real, deliberate trade-off between DR-standby cost and failover speed that needs to be explicitly reasoned through, not defaulted into via generic cost-optimization settings applied uniformly without considering this specific context.

**Investigation process:** confirm the organization's actual documented RTO (recovery time objective) for this application — if 8 minutes is genuinely within acceptable RTO, the current configuration might be acceptable as-is; if not (as is likely, given this was flagged as a gap), the cold-start time needs to be reduced.

**Recommended solution:** configure the DR cluster's Karpenter `NodePool` with a `minReplicas` floor (some minimum standing capacity, not zero) sufficient to serve at least baseline traffic immediately upon failover, sized based on the actual expected failover traffic volume and the acceptable RTO — accepting a modest, deliberate increase in standing DR cost specifically to close this cold-start gap.

**Risk controls:** balance the minimum standing capacity against genuine cost — this doesn't need to be full production capacity at all times (which would defeat much of the cost-saving purpose of a DR region existing in warm-standby rather than fully active-active), just enough to avoid a multi-minute complete-unavailability gap during the failover window while additional capacity scales up.

**Validation steps:** after setting the minimum floor, re-run the DR failover drill and confirm traffic is served immediately (or within acceptable RTO) upon failover, with Karpenter scaling additional capacity beyond the floor as actual failover traffic ramps up.

**Rollback or recovery strategy:** if the chosen minimum floor proves insufficient during a drill (traffic exceeds what the floor capacity can handle before additional scaling completes), increase the floor and re-test — an iterative sizing exercise informed by actual drill results.

**Long-term prevention:** treat "does our DR architecture's cost-optimization settings conflict with our actual RTO" as a standing design review question whenever cost-optimization changes (like enabling scale-to-zero) are applied to DR infrastructure specifically, distinct from how the same setting might be entirely appropriate for genuinely non-critical, non-DR workloads.

### Step-by-Step Implementation
```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: dr-standby-pool
spec:
  limits:
    cpu: "1000"   # ceiling for full failover scale-up
  # A minimum floor isn't a native Karpenter NodePool field directly, but achieved via
  # a small, separately-maintained baseline managed node group or a scheduled
  # "pre-warm" job ensuring some minimum capacity is always present in the DR region
```

### Under-the-Hood Explanation
Karpenter's cost-optimized consolidation (per [`docs/node-management-and-autoscaling.md`](../docs/node-management-and-autoscaling.md) §3) actively scales down to genuinely zero nodes when a NodePool has no pending workload demand, which is exactly correct behavior for cost efficiency during normal operation — but it also means the *first* request needing capacity after a genuine zero-node state must wait through the full node-provisioning latency (EC2 instance launch, bootstrap, kubelet registration) before it can be served, a real, physical latency floor that no amount of software configuration eliminates entirely, only mitigates via maintaining some non-zero standing capacity.

### Common Weak Answer
"Route 53 failover happened correctly, so our DR setup is working as designed."

### Why the Weak Answer Fails
DNS-level failover succeeding is necessary but not sufficient for genuine DR-readiness — the actual measure of success is whether the DR region can serve traffic within the organization's real RTO, and an 8-minute cold-start gap, however "correct" the DNS failover itself was, represents a real, likely-unacceptable service disruption this narrow framing misses entirely.

### Follow-Up Questions
1. How would you determine the appropriate minimum standing-capacity floor based on actual expected failover traffic volume?
2. What's the cost trade-off analysis you'd present to leadership justifying a non-zero standing DR capacity floor?
3. How would you extend this same cold-start-risk awareness to other cost-optimized components in the DR architecture (e.g., a scaled-to-zero observability stack)?

### Key Interview Signals
Recognizes that DNS-level failover success doesn't equal genuine DR-readiness, and identifies the specific conflict between cost-optimized scale-to-zero settings and the actual RTO requirement, designing a deliberate, sized standing-capacity floor as the fix.

### Hands-On Connection
[Lab 5 — Karpenter Autoscaling](../labs/lab-05-karpenter-autoscaling/) and [Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).

---

## Question 108: The backup that was never tested until it mattered

### Scenario
Following the lessons from earlier questions in this repository (Velero backup gaps, break-glass path staleness), an organization implements a quarterly "full DR drill" — but the drill has always been performed by the same one engineer who originally designed the DR architecture. That engineer leaves the company. The next quarterly drill, run by someone else following the existing documentation, fails at multiple steps due to undocumented manual steps the original engineer always performed from memory.

### Interview Question
Diagnose this "bus factor" risk in DR readiness and design a fix.

### Strong Senior-Level Answer
**Initial assessment:** a DR process that only works when one specific, knowledgeable individual executes it isn't actually a tested, reliable DR capability — it's a demonstration of that individual's personal expertise, which is a fundamentally different (and much more fragile) thing; per the "recovery tool can't share fate with what it's recovering" principle threaded throughout this repository series, a DR process that depends on one specific person's continued availability shares fate with that person's employment status, exactly the kind of single-point-of-failure this discipline exists to eliminate.

**Technical reasoning:** the quarterly drills were successfully validating the *documented* DR process's correctness only insofar as the original engineer's own undocumented, memorized steps filled the gaps — the drills were never actually testing whether the *documentation* alone was sufficient for someone else to execute successfully, which is the real, meaningful test a DR process needs to pass.

**Investigation process:** have the new engineer (or, ideally, someone else entirely unfamiliar with the process) attempt the drill strictly following only the written documentation, explicitly noting every point where the documentation was insufficient, ambiguous, or assumed knowledge not actually written down — this directly surfaces every gap the original engineer had been silently filling from memory.

**Recommended solution:** update the DR documentation to explicitly capture every step previously performed from memory, and re-test with yet another person unfamiliar with the process (ideally rotating who performs each quarterly drill specifically to continuously validate that the documentation, not any individual's tribal knowledge, is what makes the process actually work).

**Risk controls:** treat "the drill succeeded" as meaningfully different from "the drill succeeded because the person running it happened to already know undocumented steps" — the entire value of a DR drill is testing whether the *documented, repeatable* process works, and a drill run by its own author doesn't actually validate that.

**Validation steps:** after updating documentation, confirm a genuinely unfamiliar person (not the original author, not someone who's run it before) can successfully execute the full DR process using only the written documentation, with no external help.

**Rollback or recovery strategy:** not applicable — this is a process-documentation gap being surfaced and corrected, not an infrastructure change.

**Long-term prevention:** institutionalize rotating drill ownership (a different person executes each quarterly drill, ideally someone who hasn't run it recently) as a standing practice specifically to continuously validate that DR readiness lives in documentation and tooling, not in any one individual's memory — directly extending the "test your break-glass path, don't just document it" discipline from the companion Ansible/IRSA questions to the full DR process itself.

### Step-by-Step Implementation
```text
Quarterly DR drill process:
1. Assign the drill to someone who has NOT run it in the past two quarters
   (rotating ownership, never defaulting back to the original architect).
2. Require strict adherence to only the written documentation - no informal
   help from anyone with undocumented tribal knowledge.
3. Document every gap/ambiguity encountered as an explicit documentation
   update, closing it before the next quarter's drill.
4. Track "time to complete" and "number of undocumented-gap incidents"
   as trending metrics - both should improve over successive quarters
   as documentation genuinely improves.
```

### Under-the-Hood Explanation
This is a documentation and process-design problem, not a technical one — no tooling change fixes tribal knowledge; only the discipline of having someone genuinely unfamiliar with the process attempt it, strictly from documentation, reliably surfaces every gap where institutional memory was silently substituting for written, repeatable process, exactly the same principle underlying any "test the actual documented recovery process, not the expert's memory of it" DR-readiness discipline.

### Common Weak Answer
"The DR drills have passed every quarter, so our DR readiness is solid."

### Why the Weak Answer Fails
Every quarter's "pass" was actually validating one specific individual's personal expertise, not the documented process's genuine, person-independent repeatability — the moment that individual left, this false confidence was immediately exposed, exactly the risk a rotating-ownership drill practice would have caught much earlier.

### Follow-Up Questions
1. How would you handle the immediate gap while documentation is being fully updated, given a real DR event could occur before that work is complete?
2. How would you measure whether documentation quality is genuinely improving over successive drill cycles?
3. How does this "bus factor" risk apply to other critical, infrequently-exercised processes in this platform beyond DR specifically?

### Key Interview Signals
Recognizes that a DR drill's repeated "success" can mask a bus-factor risk if always executed by the same knowledgeable individual, and designs rotating ownership specifically to validate documentation's genuine, person-independent sufficiency.

### Hands-On Connection
[Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).

---

## Question 109: One region down, then the other

### Scenario
Following a successful failover to the DR region during a primary-region outage, the DR region itself experiences a separate, unrelated issue two hours later (an unrelated AWS service disruption affecting that specific region). The organization has no plan for "what happens if the region we just failed over to also has a problem."

### Interview Question
Discuss this gap and how you'd think about the actual, realistic scope of DR planning.

### Strong Senior-Level Answer
**Initial assessment:** a two-region active/DR architecture inherently has no further fallback if both regions experience issues — this is a legitimate, often-accepted limitation of a two-region design, and the right response isn't necessarily "build a third region" (a significant additional cost/complexity investment) but rather an honest, deliberate risk-acceptance discussion about what level of resilience the organization has actually chosen to invest in versus what residual risk remains.

**Technical reasoning:** the probability of two independent AWS regions experiencing genuinely unrelated issues within the same short window is low but non-zero — the actual question for the organization isn't "can we eliminate this risk entirely" (only a maximally-resilient, and maximally-expensive, N-region architecture could approach that), but "is this specific, low-probability residual risk acceptable given its cost to further reduce, or does the business's risk tolerance genuinely warrant investing in additional regions."

**Investigation process:** quantify (as best as can be reasonably estimated) the actual business impact of an extended, both-regions-affected outage, and compare it against the cost of adding a third region (or other mitigations, like a different cloud provider as an even more independent fallback) — this is fundamentally a business risk-tolerance and cost-benefit decision, not a purely technical one.

**Recommended solution:** document this residual risk explicitly (rather than leaving it as an unstated assumption nobody has consciously decided on) as part of the organization's DR strategy documentation, with an explicit decision: either accept this residual risk as-is (a legitimate choice for many organizations, given the genuinely low probability and the cost of further mitigation), or invest in additional resilience (a third region, or a different mitigation entirely) if the business's risk tolerance and the potential impact genuinely warrant it.

**Risk controls:** whichever decision is made, ensure it's a deliberate, documented, and periodically-revisited choice (as business criticality/risk tolerance can change over time) rather than an unexamined gap nobody has actually thought through, which is the real problem this scenario surfaces — not necessarily the two-region architecture itself.

**Validation steps:** not applicable in the traditional sense — the "validation" here is ensuring leadership/business stakeholders have genuinely reviewed and signed off on this specific residual risk, with full understanding of its likelihood and impact.

**Rollback or recovery strategy:** for the immediate both-regions-affected incident, the actual recovery options are limited to whatever manual, ad hoc mitigation is possible (a maintenance page, a degraded-mode static fallback, waiting for either region to recover) — genuinely accepting that a two-region architecture has this residual gap by design.

**Long-term prevention:** treat "have we explicitly documented and business-approved our DR architecture's residual risk boundary" as a standing governance item, ensuring the organization's actual risk tolerance is knowingly and deliberately reflected in the DR investment level, rather than an assumption nobody examined.

### Step-by-Step Implementation
```text
Documentation update (not a technical change): explicitly state in the DR
strategy document: "This architecture protects against a single-region
outage. A simultaneous, independent issue affecting both the primary and
DR regions is a residual risk we have assessed as [accepted / requiring
further investment], based on [documented probability/impact analysis and
business stakeholder sign-off]."
```

### Under-the-Hood Explanation
This is fundamentally a business-risk-management question, not a technical/architectural one — every DR architecture has some residual risk boundary beyond which it doesn't protect (a two-region design's boundary is "both regions simultaneously affected"), and the appropriate response is making that boundary explicit and deliberately chosen, not attempting to build an infinitely-resilient system regardless of cost, nor leaving the boundary unexamined and undocumented.

### Common Weak Answer
"We need to add a third region immediately to fully solve this."

### Why the Weak Answer Fails
This assumes eliminating all residual risk is automatically the correct answer regardless of cost, without first quantifying the actual probability/impact and comparing it against the very real cost and complexity of a third region — the correct answer might genuinely be "add a third region" for a sufficiently critical business, but it might just as legitimately be "document and accept this risk," and reaching that answer requires an actual cost-benefit analysis, not an automatic assumption in either direction.

### Follow-Up Questions
1. How would you estimate the actual probability of two independent regions experiencing correlated or coincidental issues within a short window?
2. What business/stakeholder conversation would you have to reach a genuine, informed decision on this residual risk?
3. What's a lower-cost mitigation option (short of a full third region) that might partially address this gap?

### Key Interview Signals
Frames this as a legitimate business risk-tolerance and cost-benefit decision rather than assuming maximal technical resilience is always the correct answer regardless of cost, and insists on making the residual risk explicit and deliberately decided rather than an unexamined assumption.

### Hands-On Connection
[Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).

---

## Question 110: The capstone question — designing HA/DR from a blank page

### Scenario
You're asked to design the HA/DR architecture for a new, business-critical application from scratch, with no existing constraints to work around.

### Interview Question
Walk through your complete design process, synthesizing the concepts from this entire category.

### Strong Senior-Level Answer
**Initial assessment:** a from-scratch HA/DR design needs to reason through every layer this category has covered — workload-level AZ resilience (Question 105), what the platform's own mechanisms (GitOps, Kubernetes self-healing) do and don't provide automatically (Question 106), failover-speed versus standing-cost trade-offs (Question 107), the genuine testability of the recovery process itself (Question 108), and an explicit, deliberate statement of residual risk (Question 109) — treating HA/DR not as a single feature to enable, but as a layered set of deliberate decisions.

**Technical reasoning:** starting with actual business requirements (RTO/RPO, informed by real business-impact analysis, not a default assumption) is the correct starting point — every subsequent technical decision (single-region multi-AZ vs. multi-region, warm-standby vs. active-active, synchronous vs. asynchronous data replication) should be derived from these requirements, not chosen first and then rationalized.

**Investigation process:** gather the actual RTO/RPO requirements from business stakeholders (how much downtime and how much data loss is genuinely tolerable), and the actual cost tolerance for the resilience investment — these two inputs (business impact and cost tolerance) jointly determine the appropriate architecture tier, from "single-region, multi-AZ, workload-level resilience only" (Question 105's pattern, sufficient for many applications) up through "multi-region active-active with synchronous replication" (a very high-cost, low-RTO/RPO tier appropriate only for the most critical applications).

**Recommended solution:** design in layers, matched to the actual determined requirement tier: (1) workload-level AZ resilience via topology spread constraints as a baseline for any tier; (2) if multi-region is warranted, GitOps-based configuration parity across regions (correctly scoped to what it actually provides — Question 106) plus explicit, separately-designed data replication for every stateful dependency; (3) an appropriately-sized standing-capacity floor in the DR region matched to the actual RTO (Question 107); (4) a genuinely tested, rotating-ownership-validated recovery process (Question 108); (5) an explicit, documented, business-approved statement of whatever residual risk remains beyond the chosen architecture's boundary (Question 109).

**Risk controls:** avoid both under-investment (assuming Kubernetes/GitOps automatically provides more resilience than they actually do, per Question 106) and over-investment (building a maximally-resilient, maximally-expensive architecture for a workload whose actual business-impact analysis doesn't warrant that cost) — the correct design is precisely matched to genuine requirements, in both directions.

**Validation steps:** for whatever architecture tier is chosen, define and execute the corresponding tested-and-validated drill process (Question 108's rotating-ownership discipline) proving the design actually delivers its intended RTO/RPO under a genuine, realistic test, not just a theoretical design review.

**Rollback or recovery strategy:** built into the design itself — a well-designed DR architecture's own recovery/failback process should itself be documented and tested, including the "failing back" step (returning to the primary region once it recovers) which is often under-designed relative to the initial failover.

**Long-term prevention:** revisit the architecture's requirements (RTO/RPO, cost tolerance) periodically as the business and application evolve — a design appropriate for an application's criticality level at launch may need to evolve as that application's actual business importance changes over time.

### Step-by-Step Implementation
```text
1. Gather RTO/RPO requirements from business stakeholders (not assumed).
2. Determine appropriate architecture tier from RTO/RPO + cost tolerance.
3. Layer 1 (all tiers): topology spread constraints for workload-level AZ resilience.
4. Layer 2 (if multi-region): GitOps config parity + explicit, separate data
   replication design for every stateful dependency.
5. Layer 3 (if multi-region): sized standing-capacity floor matched to RTO.
6. Layer 4: documented, rotating-ownership-tested recovery AND failback process.
7. Layer 5: explicit, business-approved statement of residual risk beyond
   the chosen architecture's boundary.
```

### Under-the-Hood Explanation
Every technical mechanism covered in this category — topology spread constraints, GitOps reconciliation, Karpenter capacity management, Velero/RDS replication — solves one specific, bounded piece of the overall HA/DR picture; genuine resilience emerges from correctly composing all the relevant pieces for a given requirement tier, informed by actual business needs, rather than from any single mechanism alone, which is exactly why this category's individual questions build toward this synthesis question.

### Common Weak Answer
"Enable multi-AZ, set up a DR region, and configure backups — that's a complete HA/DR design."

### Why the Weak Answer Fails
This lists mechanisms without deriving them from actual requirements or addressing the specific gaps this category has demonstrated at each layer (workload placement, GitOps's actual scope, cold-start timing, drill validity, residual risk) — a genuinely complete design reasons through each of these explicitly, not just invokes their names.

### Follow-Up Questions
1. How would you present this layered design and its cost implications to business stakeholders for approval?
2. How would you handle a mid-project change in business-criticality requirements after the architecture is already partially built?
3. How would you design the failback process (returning to the primary region) with the same rigor as the initial failover?

### Key Interview Signals
Synthesizes every concept from this category into a coherent, requirements-driven design process, explicitly deriving architecture decisions from actual business RTO/RPO and cost tolerance rather than defaulting to a generic "best practices" checklist applied without regard to actual need.

### Hands-On Connection
[Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).
