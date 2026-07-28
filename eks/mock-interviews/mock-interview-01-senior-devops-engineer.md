# Mock Interview 1: Senior DevOps Engineer

**Format**: 15 questions, 60 minutes. **Focus**: EKS cluster operations, networking, and troubleshooting. **Level target**: Senior (score 3 on the rubric is a pass; 4-5 is exceeding expectations for this specific level).

Use the [Scoring Rubric](#scoring-rubric-reference) at the end for every question. Run this cold — resist the urge to look up answers mid-interview; that defeats the purpose of a mock.

---

## Question 1
**Interviewer asks:** "A `terraform apply` for a new EKS cluster just finished, and it shows `ACTIVE`. Can the team deploy their application now?"

**Expected answer points:**
- No — `ACTIVE` means the control plane and EKS-managed add-ons (`vpc-cni`, `coredns`, `kube-proxy`) exist; it says nothing about ingress, autoscaling, security policy, or observability.
- Names the specific gap: no AWS Load Balancer Controller, no Karpenter/Cluster Autoscaler, no IRSA setup for the specific workload, no admission policy.
- Treats "control plane exists" and "genuinely production-ready" as two distinct, separately-verified milestones.

**Follow-up questions:**
1. What's the very first thing you'd check on a freshly-provisioned cluster before anything else?
2. How would you automate this entire post-provisioning bootstrap so it's not a manual checklist every time?
3. Which of these gaps would you consider truly non-negotiable versus nice-to-have?

**Red flags:** "Once ACTIVE shows, the cluster is ready to use" — the exact misconception this question tests for.

**Model answer:** *"`ACTIVE` only confirms the control plane and the handful of EKS-managed add-ons Terraform's `aws_eks_addon` resources installed — it says nothing about ingress, autoscaling, security policy, or observability, none of which exist by default. Before I'd call this production-ready, I'd need the AWS Load Balancer Controller, an autoscaler, IRSA configured for whatever AWS access the workload needs, baseline Pod Security Admission, and a working observability stack — each a separate, verified step, not implied by `ACTIVE`."*

**Full reference:** [Question 9: Where the Terraform apply ends](../interview-questions/01-eks-cluster-architecture.md#question-9-where-the-terraform-apply-ends)

---

## Question 2
**Interviewer asks:** "A pod is stuck in `ContainerCreating` with a CNI-related error, but the node has plenty of free CPU and memory. What's your diagnosis?"

**Expected answer points:**
- Likely IP exhaustion — pod density is capped by ENI count × IPs-per-ENI for the node's instance type, a separate ceiling from CPU/memory.
- Prefix delegation (`ENABLE_PREFIX_DELEGATION=true`) is the standard fix, raising the pods-per-node ceiling substantially.
- Confirms via `ipamd` warm-pool state / node's actual available IP count before jumping to a fix.

**Follow-up questions:**
1. How does prefix delegation actually work at the ENI level?
2. What's the trade-off of enabling prefix delegation on an already-running cluster?
3. How would you monitor for this proactively rather than discovering it via a stuck pod?

**Red flags:** Assumes CPU/memory pressure must be the cause without checking the specific CNI error message — misses that pod density has its own, separate ceiling.

**Model answer:** *"Since CPU/memory are fine, this points to IP exhaustion — pod density is capped by the node's ENI count times IPs-per-ENI, a completely separate ceiling from compute resources. I'd confirm via the pod's events for the specific CNI allocation error, then check `ipamd`'s actual available-IP state on that node. The standard fix is enabling prefix delegation, which assigns a `/28` prefix per ENI instead of individual IPs, substantially raising the pods-per-node ceiling."*

**Full reference:** [Question 11: The subnet that ran out of room](../interview-questions/02-networking.md#question-11-the-subnet-that-ran-out-of-room)

---

## Question 3
**Interviewer asks:** "Users report intermittent connection errors right after every deployment, even though your ALB Ingress health checks look green throughout. What would you check?"

**Expected answer points:**
- Likely `target-type: instance` — health checks reflect node/NodePort reachability, not the specific pod's health.
- A crashed pod on an otherwise-healthy node can still receive traffic briefly before Kubernetes fully reschedules it.
- Fix: switch to `target-type: ip`, giving pod-level health-check granularity.

**Follow-up questions:**
1. What's the mechanical difference in how `instance` vs `ip` mode routes traffic?
2. Why would this specific symptom show up right after deployments particularly?
3. Is there ever a legitimate reason to still use `instance` mode?

**Red flags:** Assumes the health check configuration (interval/threshold) is the problem and proposes tuning it, without recognizing the structural target-type gap.

**Model answer:** *"This is the classic `instance`-mode blind spot — target-group health checks in `instance` mode reflect NodePort/node-level reachability, not any specific pod's health, so a pod that just crashed during a deployment can still receive routed traffic briefly since the node itself is still reachable. Tuning the health-check interval doesn't fix this structurally; switching to `target-type: ip` does, since it registers each pod's actual IP as a target and checks that specific pod directly."*

**Full reference:** [Question 12: The health check that lied](../interview-questions/02-networking.md#question-12-the-health-check-that-lied)

---

## Question 4
**Interviewer asks:** "A security team asks you to prove that your cluster's NetworkPolicy objects actually isolate two namespaces from each other. How do you prove it?"

**Expected answer points:**
- A `NetworkPolicy` object's existence proves nothing by itself — enforcement requires an active CNI capability (native VPC CNI policy support, or Calico).
- The only real proof is a positive-control test: attempt a connection that should be blocked and confirm it's actually rejected.
- Never trust `kubectl get networkpolicy` output alone as evidence of isolation.

**Follow-up questions:**
1. How would you check whether native VPC CNI policy enforcement is actually enabled?
2. What's the difference between native VPC CNI enforcement and Calico for this purpose?
3. How would you build this into a standing, automated check rather than a one-time manual test?

**Red flags:** Points to `kubectl get networkpolicy` output as sufficient proof — exactly the false-confidence trap this question is built around.

**Model answer:** *"I wouldn't trust the object's existence at all — `NetworkPolicy` is inert without an active enforcement mechanism, either native VPC CNI network-policy support or Calico, and there's no error or warning if nothing is enforcing it. The only real proof is a positive-control test: spin up a pod in the other namespace and attempt exactly the connection the policy should block, confirming it's genuinely rejected. I'd automate this as a standing test, not something checked once and assumed to still hold."*

**Full reference:** [Question 14: The NetworkPolicy that did nothing](../interview-questions/02-networking.md#question-14-the-networkpolicy-that-did-nothing)

---

## Question 5
**Interviewer asks:** "A managed node group version update stalls at 60% complete and never finishes. What's your diagnostic approach?"

**Expected answer points:**
- Node group updates respect `PodDisruptionBudget`s during draining — the most common stall cause is an unsatisfiable PDB (e.g., `minAvailable` too high relative to actual replica count).
- Check `kubectl get pdb` for any PDB showing zero allowed disruptions.
- Fix: correct the PDB or scale the affected Deployment, don't force-delete pods to bypass it.

**Follow-up questions:**
1. Why shouldn't you force-delete the blocking pods to unblock the drain?
2. How would you proactively catch this before initiating any future node group update?
3. Does this same stall risk apply to Karpenter-managed nodes?

**Red flags:** Suggests force-deleting the stuck pods to "unblock" the drain — bypasses the exact safety mechanism correctly doing its job.

**Model answer:** *"Node group updates drain nodes respecting PodDisruptionBudgets — a stall at a specific point almost always means a PDB can't be satisfied, commonly `minAvailable` set higher than the workload's actual replica count. I'd check `kubectl get pdb -A` for anything showing zero allowed disruptions, then fix the actual PDB or replica-count mismatch — never force-delete the blocking pods, since that bypasses a safety mechanism that's correctly preventing an availability loss, not malfunctioning."*

**Full reference:** [Question 37: The managed node group stuck mid-update](../interview-questions/04-node-management.md#question-37-the-managed-node-group-stuck-mid-update)

---

## Question 6
**Interviewer asks:** "A pod requesting a GPU resource has been `Pending` for a week. Karpenter is installed and shows no errors in its logs. What's happening?"

**Expected answer points:**
- Karpenter only provisions nodes matching at least one existing `NodePool`'s constraints — if no `NodePool` permits a GPU-capable instance family, there's no valid provisioning option, and Karpenter correctly does nothing.
- This is a configuration gap, not a Karpenter malfunction.
- Fix: add a `NodePool`/`EC2NodeClass` permitting GPU instance families, typically tainted to prevent non-GPU workloads from landing there.

**Follow-up questions:**
1. Why does Karpenter "correctly do nothing" here instead of erroring?
2. How would you prevent expensive GPU capacity from being consumed by non-GPU workloads once the NodePool exists?
3. How would you catch this gap before a pod sits pending for a week?

**Red flags:** Assumes Karpenter itself must be broken and suggests restarting it — misses that this is a structural configuration gap, not a runtime failure.

**Model answer:** *"Karpenter only provisions instance types permitted by at least one existing `NodePool` — if every current `NodePool` restricts to general-purpose families with no GPU-capable option, there's structurally nothing for Karpenter to provision, and it correctly does nothing rather than erroring. This isn't a malfunction; it's a configuration gap. The fix is adding a `NodePool` permitting GPU families, typically tainted so non-GPU workloads don't waste that expensive capacity."*

**Full reference:** [Question 36: The Karpenter NodePool that never matched](../interview-questions/04-node-management.md#question-36-the-karpenter-nodepool-that-never-matched)

---

## Question 7
**Interviewer asks:** "A workload with 3 replicas across a node group spanning 3 AZs still went fully down during a single-AZ outage. Why?"

**Expected answer points:**
- Node-level multi-AZ distribution (the node group spanning 3 AZs) doesn't guarantee any specific workload's replicas are actually spread across them.
- Without an explicit `topologySpreadConstraint` (or pod anti-affinity), the scheduler's default placement can concentrate all replicas in one AZ.
- Fix: add an explicit topology spread constraint with `maxSkew: 1`.

**Follow-up questions:**
1. What's the difference between `DoNotSchedule` and `ScheduleAnyway` for this constraint, and when would you choose each?
2. How would you audit an entire fleet of workloads for this same missing-constraint gap?
3. How would you test AZ-failure resilience proactively?

**Red flags:** Assumes "our node group spans 3 AZs" automatically implies workload resilience — the exact conflation this question is testing for.

**Model answer:** *"Spreading nodes across AZs and spreading a specific workload's replicas across AZs are two different things — without an explicit topology spread constraint, the scheduler has no obligation to distribute any particular Deployment's replicas evenly, and its default placement logic can concentrate all three replicas in one AZ by unremarkable coincidence. The fix is an explicit `topologySpreadConstraint` with `maxSkew: 1`, and for a genuinely critical workload I'd use `DoNotSchedule` rather than `ScheduleAnyway` to make the resilience guarantee a hard constraint, not just a preference."*

**Full reference:** [Question 105: Three replicas, one AZ](../interview-questions/12-ha-dr.md#question-105-three-replicas-one-az)

---

## Question 8
**Interviewer asks:** "A pod that was serving traffic normally for hours suddenly starts returning 500s for every request, but `kubectl get pods` still shows it as `Running` and `Ready`. What's your diagnostic process?"

**Expected answer points:**
- A passing readiness probe only proves what the probe itself checks — a shallow probe (TCP port, or a check that doesn't reflect real dependency health) can pass while the application is genuinely broken.
- Investigate application logs for the actual failure onset — likely a downstream dependency issue or an internal state problem (memory leak reaching a threshold).
- Fix: deepen the readiness probe to reflect genuine functional health, and add circuit-breaker logic if a downstream dependency is the cause.

**Follow-up questions:**
1. What's the risk of an overly deep, expensive readiness probe?
2. How would you distinguish a downstream-dependency cause from an internal application-state cause?
3. Would you restart the pod immediately, or investigate first?

**Red flags:** Trusts `Ready` status as proof of genuine health without questioning what the probe actually checks.

**Model answer:** *"'Ready' only reflects what the configured probe checks — if it's shallow, like just confirming a TCP port is open, it says nothing about whether the application can actually process requests correctly. I'd check the application's own logs around the failure's onset for a downstream dependency error or an internal-state issue like a memory leak nearing a threshold. Once I understand the actual cause, I'd both fix it and deepen the readiness probe to reflect real functional health, so this specific failure mode is caught automatically if it recurs."*

**Full reference:** [Question 99: The pod that was healthy right up until it wasn't](../interview-questions/11-troubleshooting.md#question-99-the-pod-that-was-healthy-right-up-until-it-wasnt)

---

## Question 9
**Interviewer asks:** "You're investigating an incident and find three seemingly-related symptoms across three different teams' workloads at the same time. Do you assume one root cause?"

**Expected answer points:**
- No — investigate each symptom's specific root cause independently and in parallel before assuming a shared cause.
- On a large, shared, multi-tenant platform, coincidental, genuinely independent issues are a realistic, non-rare occurrence.
- Look for a genuine correlating signal (a recent shared change, a control-plane event) before committing to a single-cause theory.

**Follow-up questions:**
1. What would change your assessment toward a genuine shared cause?
2. How would you staff/coordinate investigating three symptoms in parallel during a live incident?
3. What's the risk of prematurely committing to a single-cause theory?

**Red flags:** Immediately assumes one shared root cause and starts investigating only that, without first testing whether the three symptoms are actually related.

**Model answer:** *"I wouldn't assume a shared cause without checking — on a large, shared platform, several genuinely independent issues coinciding is a realistic occurrence, not rare. I'd investigate each symptom's own specific root cause in parallel, explicitly looking for a correlating signal — like a recent cluster-wide change or a control-plane event — that would confirm a shared cause. If no such signal exists, treating this as three independent issues, each fixed on its own terms, is usually the faster and more accurate path than chasing a single unifying theory that might not exist."*

**Full reference:** [Question 100: The incident that was actually three incidents](../interview-questions/11-troubleshooting.md#question-100-the-incident-that-was-actually-three-incidents)

---

## Question 10
**Interviewer asks:** "A postmortem concludes 'root cause: Kubernetes scheduler bug' for a pod that wouldn't schedule. A follow-up review finds the actual cause was a NodePool constraint. What does the original postmortem's conclusion reveal?"

**Expected answer points:**
- The scheduler is one of the most heavily-used, well-tested components in the ecosystem — a genuine bug is far less likely than a configuration mismatch.
- A proper investigation should systematically eliminate configuration causes (requests vs. capacity, affinity, taints, topology spread, NodePool constraints) before concluding a platform defect.
- The postmortem's premature conclusion risks leaving the actual, still-present configuration gap unaddressed.

**Follow-up questions:**
1. What systematic checklist would you apply before ever concluding "platform bug"?
2. Why does an incorrect postmortem conclusion matter beyond just being wrong?
3. How would you build this discipline into your team's postmortem process?

**Red flags:** Accepts "scheduler bug" as plausible without questioning whether the more common, more likely configuration explanations were actually ruled out first.

**Model answer:** *"'The platform has a bug' should be a conclusion of last resort — the scheduler is one of the most heavily-tested components in the whole ecosystem, and the overwhelming majority of 'won't schedule' issues trace back to a specific, checkable configuration cause. A proper investigation systematically checks resource requests against capacity, affinity, taints, topology spread constraints, and NodePool restrictions before ever concluding a platform defect. The bigger problem with the original postmortem isn't just that it was wrong — it's that the real, still-present NodePool gap went unaddressed until the follow-up review caught it."*

**Full reference:** [Question 103: The postmortem that blamed the wrong layer](../interview-questions/11-troubleshooting.md#question-103-the-postmortem-that-blamed-the-wrong-layer)

---

## Question 11
**Interviewer asks:** "CoreDNS starts showing high CPU and occasional restarts as your cluster grows past a few hundred nodes. What's your fix?"

**Expected answer points:**
- CoreDNS's default replica count (often just 2) serves the entire cluster's DNS load — a central bottleneck at scale.
- NodeLocal DNSCache is the standard fix: a DaemonSet caching DNS locally on each node, dramatically reducing load reaching central CoreDNS.
- Increasing CoreDNS replica count is a complementary, not alternative, fix.

**Follow-up questions:**
1. How does NodeLocal DNSCache actually intercept and cache queries?
2. What's the cluster-proportional-autoscaler, and how does it relate to this?
3. How would you monitor for this bottleneck proactively as the cluster grows?

**Red flags:** Suggests just restarting CoreDNS repeatedly whenever it has trouble — a reactive, temporary relief that doesn't address the actual scaling bottleneck.

**Model answer:** *"At this scale, CoreDNS's small, fixed replica count is trying to serve the entire cluster's DNS query volume — a genuine central bottleneck, not something restarting fixes durably. I'd deploy NodeLocal DNSCache, which caches DNS responses locally on each node via a DaemonSet, dramatically cutting the query volume that ever reaches central CoreDNS, and I'd also increase CoreDNS's own replica count as a complementary fix, ideally via the cluster-proportional-autoscaler so it scales automatically with node count going forward."*

**Full reference:** [Question 15: The DNS resolver that couldn't keep up](../interview-questions/02-networking.md#question-15-the-dns-resolver-that-couldnt-keep-up)

---

## Question 12
**Interviewer asks:** "Two Ingress resources sharing an ALB via IngressGroup have overlapping paths, and requests intermittently route to the wrong backend. Diagnose it."

**Expected answer points:**
- Not actually intermittent/random — the AWS Load Balancer Controller merges rules from every Ingress in the group into one ALB's listener rules, evaluated by priority.
- Without explicit `group.order` coordination, the resulting precedence can be effectively arbitrary from either team's perspective.
- Fix: explicit `group.order` annotations, or restructure paths to be genuinely non-overlapping.

**Follow-up questions:**
1. How would you design an automated pre-merge check catching this kind of conflict before deployment?
2. What's the trade-off of one shared ALB via IngressGroup versus separate ALBs per team?
3. How would you establish a path-namespacing convention across many teams?

**Red flags:** Describes the behavior as "intermittent" or "random" without recognizing it's actually deterministic, just based on an unintended rule-priority outcome.

**Model answer:** *"This isn't actually random — the AWS Load Balancer Controller merges every Ingress in the shared group into one ALB's listener rule set, evaluated by priority, and without explicit `group.order` coordination between the two teams, the resulting precedence is deterministic but effectively arbitrary from either team's intent. I'd add explicit `group.order` annotations reflecting an agreed priority, or better, restructure the paths to be genuinely non-overlapping, and establish a path-namespacing convention so future teams sharing this ALB don't hit the same conflict."*

**Full reference:** [Question 17: The Ingress that routed to the wrong version](../interview-questions/02-networking.md#question-17-the-ingress-that-routed-to-the-wrong-version)

---

## Question 13
**Interviewer asks:** "Your team's Kubecost-equivalent cost report can't attribute shared node-pool costs to individual teams accurately. Why is this hard, and how do you solve it?"

**Expected answer points:**
- Multiple teams' pods sharing the same underlying nodes have no natural per-team cost attribution from raw AWS billing alone.
- A crude tagging approach (tag the node by whichever team uses it "most") breaks down exactly in the shared-node-pool scenario.
- Fix: a purpose-built tool (Kubecost/OpenCost) correlating Kubernetes-level pod consumption against actual AWS billing data.

**Follow-up questions:**
1. What's the difference between requests-based and usage-based allocation methodology?
2. How would you validate the tool's own accuracy before trusting it for real chargeback decisions?
3. How would you handle genuinely shared infrastructure costs, like the observability stack itself?

**Red flags:** Proposes a crude node-tagging approach as sufficient — doesn't address the actual shared-node attribution problem at all.

**Model answer:** *"Raw AWS billing has no visibility into what's happening at the pod level inside a shared node — a crude tag-the-node-by-dominant-team approach breaks down exactly when multiple teams' pods genuinely share the same instance. I'd use a purpose-built tool like Kubecost or OpenCost, which correlates actual pod-level resource consumption against the real AWS Cost and Usage Report, proportionally attributing shared node costs to whichever pods actually consumed them — and I'd validate its output against the real total AWS bill before trusting it for chargeback decisions."*

**Full reference:** [Question 114: The cost allocation nobody could untangle](../interview-questions/13-performance-scale.md#question-114-the-cost-allocation-nobody-could-untangle)

---

## Question 14
**Interviewer asks:** "A ResourceQuota is blocking a rapidly-growing team's new pods from scheduling, even though the overall cluster has plenty of spare capacity. What's going on, and what do you do?"

**Expected answer points:**
- `ResourceQuota` enforces a per-namespace ceiling entirely independent of overall cluster capacity — a team can be blocked by their own quota regardless of what's free elsewhere.
- The quota was likely set once, a year ago, and never revisited as the team grew.
- Fix: review and adjust the quota based on actual current, legitimate need, and establish periodic quota review going forward.

**Follow-up questions:**
1. Why shouldn't you just remove the quota entirely to unblock the team?
2. How would you determine the right new quota value?
3. How would you design a periodic review process across many namespaces without it becoming its own burden?

**Red flags:** Proposes removing the ResourceQuota entirely — eliminates its fair-sharing protection for the whole cluster, not just fixing this one team's need.

**Model answer:** *"ResourceQuota enforces a per-namespace ceiling independent of the rest of the cluster's capacity — this team can be blocked by their own quota even while plenty of capacity sits unused elsewhere. This is almost certainly a stale quota, set once when the team was smaller and never revisited. I'd adjust it based on actual current usage data plus reasonable growth headroom, not remove it entirely — removing it eliminates the fair-sharing protection it provides for the whole shared cluster, not just this one team's immediate blocker."*

**Full reference:** [Question 112: The namespace quota that quietly capped growth](../interview-questions/13-performance-scale.md#question-112-the-namespace-quota-that-quietly-capped-growth)

---

## Question 15
**Interviewer asks:** "You're new to a team and inherit an EKS platform with no documentation, and the person who built most of it has left. What's your first week look like?"

**Expected answer points:**
- Read and audit before touching anything — understand existing conventions before assuming they're wrong.
- Prioritize acute-risk audit first (API server endpoint exposure, IAM role scope) separate from broader understanding.
- Use `kubectl get` across every namespace, `aws eks describe-cluster`, and actual GitOps/deployment history to build real understanding, not guesswork.

**Follow-up questions:**
1. What's the very first command you'd run against this cluster?
2. How would you distinguish load-bearing configuration from accidental cruft?
3. What would justify an immediate fix versus something that can wait?

**Red flags:** "I'd rebuild it properly with best practices" with no discovery/audit phase first.

**Model answer:** *"I wouldn't start rebuilding — I'd start auditing. `aws eks describe-cluster` for the endpoint access configuration, a full `kubectl get` sweep across every namespace, and whatever Git history exists for the GitOps repo tell me what's really there and how it evolved. In parallel, I'd specifically audit for acute risk — is the API server endpoint appropriately restricted, are IAM roles scoped correctly — since those are worth fixing immediately regardless of broader conventions. Only after understanding what's load-bearing versus accidental would I propose structural changes, and even then, incrementally."*

**Full reference:** [Question 118: Migrating a legacy fleet onto EKS](../interview-questions/15-migration-leadership.md#question-118-migrating-a-legacy-fleet-onto-eks)

---

## Scoring Rubric Reference
- **1 (Beginner):** Definitions only, no production experience, no failure handling.
- **2 (Intermediate):** Understands normal implementation, limited troubleshooting, weak security/scale awareness.
- **3 (Senior):** Explains production implementation, covers validation and rollback, understands the control-plane/data-plane boundary and workload placement. **This is the passing bar for this interview.**
- **4 (Lead):** Explains architecture trade-offs, covers team governance and scale, anticipates failure modes, offers preventive controls.
- **5 (Staff/Architect):** Connects technical choices to business risk, designs for multiple teams/clusters, covers blast radius/security/cost/compliance/HA/DR.

For this Senior-level mock, a candidate consistently scoring 3+ across all 15 questions is interview-ready for Senior DevOps Engineer roles. Consistent 4s suggest readiness for Lead-level interviews — try [Mock Interview 2](mock-interview-02-lead-platform-engineer.md) next.
