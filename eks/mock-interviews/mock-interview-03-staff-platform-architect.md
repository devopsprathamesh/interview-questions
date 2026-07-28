# Mock Interview 3: Staff Platform Architect

**Format**: 15 questions, 90 minutes. **Focus**: governance, HA/DR, performance at scale, migration strategy, and organizational leadership. **Level target**: Staff/Architect (score 5 on the rubric is the target).

Use the [Scoring Rubric](#scoring-rubric-reference) at the end for every question.

---

## Question 1
**Interviewer asks:** "Design the complete HA/DR architecture for a critical, business-facing application on EKS, from a blank page."

**Expected answer points:**
- Start from actual business RTO/RPO requirements, not a default assumption — every subsequent decision derives from this.
- Layer: workload-level AZ resilience via topology spread constraints; correctly-scoped GitOps configuration parity across regions (recognizing what it does and doesn't cover); an explicit, separate data-replication mechanism for every stateful dependency; a region-independent GitOps controller (not sharing fate with a primary-region outage); a sized standing-capacity floor for acceptable failover latency; a tested, rotating-ownership DR drill matching the actual intended scenario; a documented failback process.
- Avoid both under-investment (assuming GitOps parity alone is DR) and over-investment relative to genuine business criticality.

**Follow-up questions:**
1. How would you present this design and its cost implications to business stakeholders?
2. What's the most commonly-skipped layer in a real organization's EKS DR design, in your experience?
3. How would you design the failback process with the same rigor as the initial failover?

**Red flags:** Lists mechanisms (multi-region, backups) without deriving them from actual RTO/RPO requirements, or conflates GitOps configuration parity with full recovery.

**Model answer:** *"I'd start with actual, business-stated RTO/RPO requirements — that determines everything else. Then I'd design in explicit layers: topology spread constraints for workload-level AZ resilience as a baseline; GitOps-based configuration parity across primary and DR regions, understood correctly as covering configuration only, never data; an explicit, separately-designed and tested data-replication mechanism for every stateful dependency; a DR-region GitOps controller instance independent of primary-region availability, since a controller that only exists in primary shares fate with exactly the outage it's meant to respond to; a standing-capacity floor sized to avoid an unacceptable cold-start delay if using cost-optimized autoscaling; and a drill testing the actual intended failover scenario, with rotating ownership so it validates documentation, not one person's memory. I'd give the failback process — returning to primary once it recovers — the same explicit design and testing as the initial failover, since it's commonly neglected."*

**Full reference:** [Question 110: The capstone question — designing HA/DR from a blank page](../interview-questions/12-ha-dr.md#question-110-the-capstone-question--designing-hadr-from-a-blank-page)

---

## Question 2
**Interviewer asks:** "Your DR-region cluster is 'ready' — GitOps shows it perfectly in sync with primary. A real failover reveals the application has no usable data at all. What was missing from the DR readiness assessment?"

**Expected answer points:**
- GitOps-based configuration parity and data replication are entirely separate concerns — GitOps has no mechanism for, and no awareness of, the actual data behind a stateful dependency.
- "Configuration synced successfully" and "the application actually works with real data" must be two explicitly distinct DR-readiness criteria.
- This mirrors the identical lesson in the companion Ansible repository's DR-readiness guidance — the same underlying gap in a different technology context.

**Follow-up questions:**
1. Why does GitOps parity give false confidence about DR readiness specifically?
2. How would you design the explicit data-recovery mechanism this scenario is missing?
3. How would you build a drill catching this gap before a real failover does?

**Red flags:** Accepts "GitOps shows perfect sync" as sufficient DR-readiness evidence, without questioning whether data was ever part of what GitOps actually manages.

**Model answer:** *"GitOps parity and data replication are entirely separate concerns being conflated here — the GitOps controller reconciles Kubernetes-level configuration, with zero awareness of or mechanism for the actual data behind any stateful dependency like a database. 'Configuration is in sync' and 'the application has usable data' are two genuinely distinct claims, and this DR readiness assessment only ever verified the first one. I'd treat every stateful dependency as needing its own, explicitly designed and independently tested data-replication or backup-restore mechanism, and I'd design the next DR drill to specifically verify real data availability post-failover, not just configuration sync status."*

**Full reference:** [Question 106: The DR cluster that was ready, except for the part that mattered](../interview-questions/12-ha-dr.md#question-106-the-dr-cluster-that-was-ready-except-for-the-part-that-mattered)

---

## Question 3
**Interviewer asks:** "A DR drill has passed every quarter for two years, always run by the same engineer who designed the DR architecture. That engineer just left. What's actually been proven by two years of passing drills?"

**Expected answer points:**
- Very little, in terms of genuine, person-independent process reliability — the drills validated one individual's tribal knowledge, not the documented process itself.
- The real test is having someone genuinely unfamiliar with the process execute it using only written documentation.
- Fix: rotating drill ownership going forward, as a standing practice, not a one-time correction.

**Follow-up questions:**
1. How would you have caught this gap before the engineer's departure forced the issue?
2. How does this connect to break-glass-access-path testing generally?
3. What would you do in the immediate aftermath, before the next quarterly drill?

**Red flags:** "Two years of passing drills is strong evidence the process works" — exactly the false confidence this scenario is built to expose.

**Model answer:** *"Very little was actually proven about the documented process's own reliability — every 'pass' validated that this one engineer, executing largely from memory, could recover the system, never whether the documentation itself was sufficient for someone else to succeed. That's the real test a DR drill needs to pass. I'd have caught this earlier by rotating drill ownership from the start, never letting the same person run it twice consecutively — the same principle as testing a break-glass access path: an emergency procedure never exercised by anyone but its author is functionally undocumented, no matter how many times the author has run it privately."*

**Full reference:** [Question 108: The backup that was never tested until it mattered](../interview-questions/12-ha-dr.md#question-108-the-backup-that-was-never-tested-until-it-mattered) (companion repository — the identical DR bus-factor lesson applies directly to EKS DR drills)

---

## Question 4
**Interviewer asks:** "You've discovered twenty independently-drifted policy sets across twenty clusters, all supposedly descended from the same original security baseline. A new compliance mandate requires proving consistent enforcement across all of them. How do you approach this?"

**Expected answer points:**
- Manual, per-cluster policy reconciliation doesn't scale and isn't defensible for compliance purposes.
- Consolidate to a single, centrally-managed, GitOps-reconciled (`ApplicationSet`-driven) policy source applied identically to every cluster, with explicit, reviewed exceptions for genuinely necessary variation.
- Establish an ongoing, automated compliance-consistency check, not a one-time reconciliation snapshot.

**Follow-up questions:**
1. How would you handle a cluster team's legitimate need for a genuine policy exception?
2. What's the risk of treating this as a one-time cleanup rather than an ongoing practice?
3. How would you present this consolidation's findings to a compliance team credibly?

**Red flags:** Proposes asking each of the twenty teams to manually sync their policies to a shared reference — the exact process that produced the drift in the first place.

**Model answer:** *"Twenty independently-maintained copies with no structural mechanism keeping them in sync is exactly why they drifted — asking teams to manually reconcile again just resets the clock on the same failure. I'd consolidate to a single, centrally-managed policy source applied identically across every cluster via an `ApplicationSet`, with any genuinely necessary per-cluster variation expressed as an explicit, reviewed exception rather than an independently-maintained copy. Critically, I'd add a standing, scheduled compliance-consistency check comparing each cluster's actual deployed policies against the central source continuously — a one-time reconciliation without that ongoing check will simply drift apart again."*

**Full reference:** [Question 117: One policy set, twenty clusters, twenty opinions](../interview-questions/14-governance-policy.md#question-117-one-policy-set-twenty-clusters-twenty-opinions)

---

## Question 5
**Interviewer asks:** "How would you migrate a 40-application, VM-based Ansible-managed platform to EKS over 18 months, and how would you present this business case to non-technical executives?"

**Expected answer points:**
- A staged, risk-tiered migration — low-complexity/low-criticality applications first, learning cheaply — never a simultaneous big-bang.
- Maintain the legacy platform in parallel per application until its EKS replacement is proven stable for a defined bake period.
- For the business case: translate every technical decision into cost, risk, and timeline, backed by real pilot data, honest about trade-offs.

**Follow-up questions:**
1. How would you categorize the 40 applications for migration-wave sequencing?
2. What would you do if the pilot wave revealed the team needs significantly more Kubernetes expertise than planned?
3. How would you maintain executive trust throughout the full 18 months, not just at the initial pitch?

**Red flags:** Proposes migrating all 40 applications simultaneously to hit the deadline, or pitches using generic industry-best-practice appeals instead of organization-specific evidence.

**Model answer:** *"I'd categorize all 40 applications by migration complexity and business criticality, starting with a genuine learning phase of low-complexity, lower-criticality applications, with room to course-correct before committing to the harder, higher-stakes ones — never a simultaneous cutover. Each application's legacy version keeps running in parallel until its EKS replacement is proven stable through a defined bake period. For the executive presentation, I'd translate every technical capability into cost, risk, and timeline specific to this organization, backed by real pilot data rather than generic best-practice framing, and commit to ongoing, honest progress reporting throughout the full 18 months — including any deviation from plan — not just a confident initial pitch."*

**Full reference:** [Question 118: Migrating a legacy fleet onto EKS](../interview-questions/15-migration-leadership.md#question-118-migrating-a-legacy-fleet-onto-eks) and [Question 120: Explaining a platform decision to people who don't run Kubernetes](../interview-questions/15-migration-leadership.md#question-120-explaining-a-platform-decision-to-people-who-dont-run-kubernetes)

---

## Question 6
**Interviewer asks:** "Your CI runner's own IAM role has broad, unscoped permissions, and a prior security review only checked in-cluster Kubernetes RBAC and Pod Security Admission, declaring everything 'fully secured.' What did that review miss?"

**Expected answer points:**
- In-cluster security controls (RBAC, PSA, NetworkPolicy) only cover what happens inside the cluster — they say nothing about the execution environment running CI/CD against it.
- A genuinely complete review must extend to the CI runner's own IAM permissions and credential-storage practices, an entirely separate, foundational layer.
- Apply the same least-privilege derivation (CloudTrail-informed) to the runner's role as to any other automation identity.

**Follow-up questions:**
1. Why is it easy for a security review to stop at "in-cluster controls" without extending further?
2. How would you build a review checklist that structurally can't skip this layer again?
3. What's the actual blast radius if this CI runner's credentials were compromised right now?

**Red flags:** Agrees the review was thorough because "RBAC and PSA are correctly configured" — misses the scope gap entirely.

**Model answer:** *"The review conflated 'in-cluster controls are correct' with 'the entire system operating on the cluster is secure' — RBAC, PSA, and NetworkPolicy all operate entirely within the cluster's own boundary, with zero visibility into the CI runner's own IAM permissions or credential handling. I'd apply the same CloudTrail-derived least-privilege remediation process to the runner's role as I would any other automation identity, and I'd explicitly add the execution-environment layer to the review checklist going forward — this is the same 'four layers correctly configured, fifth layer never even considered' gap that recurs whenever a review stops at what's easiest to check instead of the full system with real access to the cluster."*

**Full reference:** [Question 66: Least privilege, checked at every layer but one](../interview-questions/07-security-hardening.md#question-66-least-privilege-checked-at-every-layer-but-one) (extended to the CI/execution-environment layer, per the companion Ansible repository's Question 68 pattern)

---

## Question 7
**Interviewer asks:** "How would you decide, for your organization, whether to keep patching EC2 node AMIs in place versus moving fully to a golden-AMI, immutable-infrastructure model for your EKS node groups?"

**Expected answer points:**
- A genuine trade-off, not a universally-correct answer either direction — weigh drift-elimination/reproducibility benefits against bake-pipeline investment and rollout speed.
- A common, pragmatic middle ground: golden-AMI as the default for routine patching, a fast in-place path reserved for genuinely urgent, same-day-critical fixes, fed back into the next bake.
- Base the decision on actual patching urgency profile and current pipeline maturity.

**Follow-up questions:**
1. What's the actual risk of over-relying on the "emergency" in-place path?
2. How would you measure organizational readiness to shift the default toward golden-AMI?
3. How does rollback-ability differ between the two approaches for a node group specifically?

**Red flags:** Declares one approach universally correct without weighing the organization's actual urgency/maturity trade-offs.

**Model answer:** *"This isn't a case where one approach is simply correct — it's a genuine trade-off between reproducibility, since a golden-AMI-based node's actual state is a function of exactly one thing, the AMI it booted from, and rollout speed, since in-place patching skips the full bake-test-cycle for a single urgent fix. My default recommendation is golden-AMI as the primary mechanism for routine node patching, paired with an ASG instance-refresh, with a fast in-place path reserved for genuinely same-day-critical fixes — explicitly fed back into the next golden-AMI bake so it doesn't become permanent, undocumented drift. Rollback is also meaningfully cleaner with golden-AMI: reverting a launch template to a previous AMI version is far more reliable than trying to undo an in-place patch's actual effect on running nodes."*

**Full reference:** [Question 50: Rolling update or fresh cattle?](../../ansible/interview-questions/05-aws-cloud-integration.md#question-50-rolling-update-or-fresh-cattle) (companion Ansible repository — the identical trade-off applied directly to EKS node-group AMI management)

---

## Question 8
**Interviewer asks:** "Your organization's single AWX-equivalent automation platform — or in this EKS context, your single ArgoCD instance — is a single point of failure for the entire fleet's deployment capability. During routine maintenance, it goes down, and an unrelated incident occurs during that window with no way to deploy a fix. What's the architectural lesson, beyond 'add HA'?"

**Expected answer points:**
- The GitOps controller is a single point of failure specifically for the moments it matters most — incident remediation via a genuine, reviewed change.
- Fix: genuine multi-node HA for ArgoCD, plus a tested, documented break-glass fallback (direct, reviewed `kubectl apply` against a specific, urgent fix) for the period before HA is fully in place, or in case HA itself has an unexpected gap.
- This mirrors the identical "recovery tool sharing fate with what it recovers" principle from DR design generally.

**Follow-up questions:**
1. Why is a break-glass fallback still necessary even after implementing HA?
2. How would you test the break-glass fallback without waiting for a real incident to reveal its gaps?
3. What's the trade-off of a direct `kubectl apply` break-glass path against GitOps's own "never bypass Git" discipline?

**Red flags:** Says "just add HA and this is solved" without acknowledging that even HA architectures can have unexpected gaps, and a break-glass fallback remains valuable defense-in-depth.

**Model answer:** *"The deeper lesson is that the GitOps controller is a single point of failure precisely for the moments that matter most — deploying a fix during an active incident. HA addresses the routine-maintenance-collision risk, but I'd also build and periodically test a documented, tightly-scoped break-glass fallback: a reviewed, deliberate direct `kubectl apply` for a specific urgent fix, explicitly logged and followed up with an immediate corresponding Git commit once the controller is back, so the break-glass action itself doesn't become permanent, untracked drift. This mirrors the exact 'the tool you depend on during a crisis can't share fate with the crisis' principle from DR design generally — HA reduces the likelihood of needing this path, but doesn't eliminate the need to have it, tested, for whatever gap HA itself might still have."*

**Full reference:** [Question 78: The AWX instance that was a single point of failure for everything](../../ansible/interview-questions/08-cicd-automation.md#question-78-the-awx-instance-that-was-a-single-point-of-failure-for-everything) (companion Ansible repository — the identical single-point-of-failure principle, applied here to ArgoCD)

---

## Question 9
**Interviewer asks:** "A postmortem for a production incident concludes 'a typo in a variable name caused a security policy to silently never apply; fixed the typo.' Is this a sufficient postmortem?"

**Expected answer points:**
- No — this addresses only the proximate cause, missing the deeper, more valuable question of why a silent, security-relevant failure was possible at all with no detection mechanism.
- A genuinely useful postmortem distinguishes proximate cause from contributing systemic factors (no assertion/validation catching the typo, no monitoring confirming the policy actually applied recently, no periodic compliance audit).
- Action items must address the systemic factors, not just the specific instance.

**Follow-up questions:**
1. How would you structure a postmortem template ensuring this distinction is always made?
2. What specific monitoring would you build to catch this exact class of gap proactively?
3. How does this connect to the companion EKS repository's own "postmortem that blamed the wrong layer" lesson?

**Red flags:** "The typo is fixed, the immediate problem is resolved, the postmortem can be brief" — conflates fixing one instance with addressing the systemic gap that allowed it to go undetected.

**Model answer:** *"This postmortem stops at the proximate cause and misses the more valuable, systemic question: what allowed a security-relevant failure to go undetected for as long as it did, with nothing catching it sooner. A genuinely useful postmortem would also identify and drive fixes for the contributing systemic factors — no validation catching this class of typo, no monitoring confirming the policy was actually enforcing anything recently, no periodic compliance audit that would have caught the gap sooner than an incidental discovery. The specific typo being fixed doesn't mean the next similar typo, in a different policy, wouldn't produce the identical undetected-for-months outcome — that's exactly why the systemic action items matter as much as the immediate fix."*

**Full reference:** [Question 103: The postmortem that blamed the wrong layer](../interview-questions/11-troubleshooting.md#question-103-the-postmortem-that-blamed-the-wrong-layer) (same postmortem-rigor principle, generalized from a scheduler-blame scenario to any premature-conclusion postmortem)

---

## Question 10
**Interviewer asks:** "How would you design Ansible/Kubernetes automation architecture for a fleet growing toward 10,000 hosts/pods over two years, at the platform-architecture level, not just individual tuning knobs?"

**Expected answer points:**
- Compose every relevant scaling lever together (control-plane load, node/pod density, observability cardinality, CI concurrency) rather than relying on any single fix.
- Profile a representative subset first to prioritize which levers matter most for this specific fleet's actual characteristics.
- Consider whether the platform should be partitioned into multiple smaller clusters/namespaces once a single unit's management genuinely becomes unwieldy.

**Follow-up questions:**
1. Why is composing multiple levers more effective than maximizing any single one?
2. How would you benchmark this design as the fleet actually grows toward the target size?
3. When would you decide to split into multiple clusters rather than scale one?

**Red flags:** "Just increase the control plane / add more nodes" — treats one lever as sufficient, ignoring the other independently significant factors at this scale.

**Model answer:** *"No single setting handles this scale — I'd compose control-plane load management (efficient controllers, avoiding excessive watch/list patterns), node/pod density tuning (prefix delegation, Karpenter consolidation), observability cardinality control (avoiding unbounded label values in metrics), and CI/CD concurrency design together, since each addresses a genuinely distinct scaling dimension. I'd profile a representative subset of the actual fleet first to see where the real bottlenecks are rather than guessing, and I'd seriously evaluate splitting into multiple, smaller clusters or namespaces once a single unit's management genuinely becomes unwieldy, rather than scaling one monolithic cluster indefinitely regardless of the operational cost of doing so."*

**Full reference:** [Question 111: The cluster that outgrew its own control plane's comfort zone](../interview-questions/13-performance-scale.md#question-111-the-cluster-that-outgrew-its-own-control-planes-comfort-zone)

---

## Question 11
**Interviewer asks:** "A shared multi-tenant cluster's namespace-level isolation (RBAC, ResourceQuota, NetworkPolicy) all look correct, yet one tenant's traffic spike still degraded performance for unrelated tenants sharing the same nodes. What's the missing isolation layer?"

**Expected answer points:**
- Namespace-level isolation provides logical, not physical, isolation — co-located pods on the same node still compete for real, finite CPU/memory at the kernel level.
- CPU specifically is compressible (throttled, not OOM-killed), meaning multiple tenants bursting simultaneously can genuinely contend even within their own individually-correct quotas.
- Fix: dedicated node pools (taints/tolerations) for genuinely noisy-neighbor-sensitive or high-isolation-requirement tenants.

**Follow-up questions:**
1. Why does ResourceQuota not prevent this specific contention?
2. How would you decide which tenants warrant dedicated node pools versus a shared pool?
3. What's the cost trade-off of dedicated node pools at scale across many tenants?

**Red flags:** Assumes correct namespace-level isolation (RBAC, ResourceQuota, NetworkPolicy) automatically implies full tenant isolation — misses the node-level physical-sharing gap.

**Model answer:** *"Namespace-level controls provide logical isolation — RBAC governs actions, ResourceQuota bounds aggregate *declared requests*, NetworkPolicy bounds network reachability — but none of them provide physical isolation at the node level. If tenants share underlying nodes, their pods still compete for the same finite CPU/memory at the kernel level; CPU specifically is compressible, meaning multiple tenants simultaneously bursting toward their individual limits can genuinely contend even while each stays within their own quota. For tenants with variable load patterns or genuinely high isolation requirements, I'd add dedicated node pools via taints and tolerations — a deliberate cost trade-off, reserved for tenants where it's actually warranted, not a blanket default for every tenant on the platform."*

**Full reference:** [Question 113: The tenant that was too loud for the room](../interview-questions/13-performance-scale.md#question-113-the-tenant-that-was-too-loud-for-the-room)

---

## Question 12
**Interviewer asks:** "How would you prove, for a compliance audit, that every IRSA role across thirty clusters follows least privilege — without a slow, unreliable manual review?"

**Expected answer points:**
- Convert the vague audit ask into specific, automatable checks (trust-policy subject-scoping, node-role-fallback exposure, RBAC/permission wildcards).
- Build a systematic, scripted audit across every cluster, not a per-cluster manual review.
- Self-attestation from each team is not defensible evidence for a compliance audit.

**Follow-up questions:**
1. How would you validate the automated scan's own accuracy before trusting its output?
2. How would you prioritize remediation across many findings with limited engineering time?
3. How would you make this a recurring, not one-time, practice?

**Red flags:** Proposes having each of the thirty cluster teams self-attest to compliance — unenforceable and not real evidence for an audit.

**Model answer:** *"I'd convert 'prove least privilege' into specific, checkable criteria — does every IRSA role's trust policy include proper `sub`/`aud` scoping, are there any RBAC wildcard grants, does any ServiceAccount lack IRSA annotation entirely and silently fall back to the node role. Then I'd build one automated script running that check across all thirty clusters, producing a single, defensible report — self-attestation from each cluster team individually isn't real evidence for a compliance audit, and manual review at this scale isn't reliable or fast enough regardless. I'd spot-check the automated scan against a manual sample first to validate its own accuracy before relying on the full output."*

**Full reference:** [Question 34: Auditing IRSA at fleet scale](../../ansible/interview-questions/03-roles-collections.md#question-34-sunsetting-the-role-nobody-was-supposed-to-still-be-using) (companion Ansible repository — the identical fleet-scale audit methodology, applied here to EKS IRSA roles specifically)

---

## Question 13
**Interviewer asks:** "Design the coordination process for rolling out a Kubernetes minor-version upgrade across 20 clusters shared by 20 independent teams."

**Expected answer points:**
- A staged, cohort-based rollout by risk tolerance (lowest-impact first), never simultaneous.
- Objective, evidence-based criteria for advancing between cohorts, not subjective judgment.
- Balance team scheduling autonomy against a firm, externally-anchored deadline (e.g., end-of-standard-support date).

**Follow-up questions:**
1. How would you handle a team resisting every proposed upgrade window?
2. What's the risk of an entirely open-ended, no-deadline rollout?
3. How would you incorporate lessons from one year's rollout into the next?

**Red flags:** Proposes upgrading all 20 simultaneously "to save time," or leaving it entirely open-ended with no deadline.

**Model answer:** *"I'd stage this in cohorts by risk tolerance — a single lowest-impact production cluster first, as a genuine canary with a defined bake period, then progressively larger, higher-impact cohorts, each gated on objective, evidence-based criteria rather than subjective confidence. I'd give teams real input into their specific slot within an overall window, but anchor the whole process to a firm, non-negotiable final deadline — the actual end-of-standard-support date — so flexibility within the window doesn't become indefinite, unaccountable delay."*

**Full reference:** [Question 74: Canarying a cluster upgrade](../interview-questions/08-addons-upgrades.md#question-74-canarying-a-cluster-upgrade) and [Question 78: One upgrade calendar, twenty teams](../interview-questions/08-addons-upgrades.md#question-78-one-upgrade-calendar-twenty-teams)

---

## Question 14
**Interviewer asks:** "Your organization's entire security/quality standard for Kubernetes manifests exists only in one senior engineer's memory and manual PR review habits — nothing is written down or automated. That engineer is going on extended leave next month. What do you do?"

**Expected answer points:**
- This is a genuine, high-impact bus-factor risk requiring active, systematic extraction before the person becomes unavailable.
- Interview the engineer to explicitly enumerate every "we should never do X" rule, converting tacit knowledge into documented and, where possible, automated Kyverno/OPA checks.
- Roll out newly-codified rules in audit mode first, validating they correctly capture the engineer's actual judgment before full enforcement.

**Follow-up questions:**
1. How would you prioritize which rules to automate first given limited time before the engineer leaves?
2. How would you validate the newly-codified rules actually reflect the engineer's real judgment?
3. How would you prevent this same concentration-of-knowledge risk from recurring with someone else later?

**Red flags:** "We'll just make sure they review PRs remotely while on leave" — doesn't address the underlying, indefinite single-point-of-failure risk at all.

**Model answer:** *"This is a genuine bus-factor risk needing active remediation before it becomes an emergency — I wouldn't wait for the leave to start. I'd interview the engineer specifically to enumerate every unwritten rule they currently catch manually, then codify each one as either an automated Kyverno/OPA check or, where that's not yet feasible, an explicit, written review-checklist item visible to every reviewer, not just this one person. I'd validate the codified rules against real historical PRs the engineer previously caught issues in, confirming the automation genuinely reflects their judgment before relying on it, and I'd treat 'is any critical standard living only in one person's memory' as a standing risk to actively watch for going forward."*

**Full reference:** [Question 112: The policy that only existed in one person's head](../../ansible/interview-questions/13-governance-policy.md#question-112-the-policy-that-only-existed-in-one-persons-head) (companion Ansible repository — the identical bus-factor-in-governance lesson, applied here to Kubernetes manifest review standards)

---

## Question 15
**Interviewer asks:** "Present the business case for a dedicated platform engineering investment (centered on EKS) to executives who care only about cost, risk, and timeline — not Kubernetes internals."

**Expected answer points:**
- Translate every technical capability into business terms: Karpenter cost-optimized autoscaling → reduced infrastructure spend; GitOps audit trail and staged rollouts → reduced deployment/security risk; policy-as-code → consistent, demonstrable standards not dependent on any one person.
- Back every claim with real, quantified evidence, not generic industry-best-practice appeals.
- Commit to ongoing, honest reporting after the initial pitch, including any deviation from plan.

**Follow-up questions:**
1. How would you handle a skeptical executive questioning the realism of projected savings?
2. How would you adjust this pitch if an initial pilot's results were less favorable than hoped?
3. Why does this business-communication skill matter as much as technical depth at this level?

**Red flags:** Leans on "this is industry best practice, everyone runs Kubernetes" as the primary justification, rather than translating specific, organization-relevant risk and cost into concrete terms.

**Model answer:** *"I'd structure this around exactly what they care about: cost — projected infrastructure savings from cost-optimized autoscaling and consolidation, backed by real pilot data, not an estimate; risk — the specific incident patterns this reduces, named concretely, like deployment-related outages or security-policy inconsistency, not a vague appeal to best practice; and timeline — how a mature platform actually accelerates safe delivery rather than only being a cost center. I'd be honest about the genuine upfront investment required, and I'd commit to an ongoing, honest reporting cadence afterward, including reporting if a pilot's results come in less favorable than hoped — that credibility matters more long-term than an overconfident initial pitch, and this translation skill is exactly what distinguishes a staff-level engineer who can drive organizational investment decisions from one who can only execute technical work handed to them."*

**Full reference:** [Question 120: Explaining a platform decision to people who don't run Kubernetes](../interview-questions/15-migration-leadership.md#question-120-explaining-a-platform-decision-to-people-who-dont-run-kubernetes)

---

## Scoring Rubric Reference
- **1 (Beginner):** Definitions only, no production experience, no failure handling.
- **2 (Intermediate):** Understands normal implementation, limited troubleshooting, weak security/scale awareness.
- **3 (Senior):** Explains production implementation, covers validation and rollback, understands the control-plane/data-plane boundary and workload placement.
- **4 (Lead):** Explains architecture trade-offs, covers team governance and scale, anticipates failure modes, offers preventive controls.
- **5 (Staff/Architect):** Connects technical choices to business risk, designs for multiple teams/clusters, covers blast radius/security/cost/compliance/HA/DR. **This is the target bar for this interview.**

A candidate consistently scoring 5 across all 15 questions is demonstrating genuine Staff/Principal-level judgment — not just deeper EKS knowledge, but the organizational and risk-management reasoning that distinguishes this level from Lead. If most answers land at 4, that's still a strong Lead-level performance; the gap to Staff is usually in connecting technical decisions explicitly to business risk, cost, and cross-team coordination, not in technical depth alone.
