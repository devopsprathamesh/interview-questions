# Mock Interview 2: Lead Platform Engineer

**Format**: 15 questions, 75 minutes. **Focus**: IAM/IRSA, storage, security, observability, and GitOps/CI-CD architecture. **Level target**: Lead (score 4 on the rubric is the target; consistent 3s suggest more Senior-level readiness than Lead).

Use the [Scoring Rubric](#scoring-rubric-reference) at the end for every question.

---

## Question 1
**Interviewer asks:** "Design the IRSA trust policy for a role, and explain exactly what happens if you forget one specific condition."

**Expected answer points:**
- The trust policy must condition on both the OIDC provider's `sub` (namespace + ServiceAccount) and `aud` (audience) claims.
- Omitting the `sub` condition means the trust policy only verifies "this token came from some pod in this cluster" — any ServiceAccount can assume the role.
- This should be verified with a positive-control test (a pod with a *different* ServiceAccount attempting to assume the role), not just configuration review.

**Follow-up questions:**
1. How would you audit every existing IRSA role in a fleet for this exact missing condition, at scale?
2. What does EKS Pod Identity change about this specific risk?
3. What's the actual blast radius if this gap exists in production right now?

**Red flags:** Describes the trust policy only referencing the OIDC provider ARN as "correctly configured" — misses the missing subject-scoping entirely.

**Model answer:** *"The trust policy needs a `Condition` block checking both `sub` — scoped to the exact namespace and ServiceAccount — and `aud`, matching `sts.amazonaws.com`. If the `sub` condition is missing, the trust policy only verifies the token came from the trusted OIDC provider, which is true for every pod in the cluster — meaning any ServiceAccount, not just the intended one, can successfully assume the role. I'd never trust this by configuration review alone; I'd run a positive-control test with an unrelated ServiceAccount attempting to assume the same role, confirming it's correctly denied."*

**Full reference:** [Question 23: The trust policy that trusted everyone](../interview-questions/03-iam-irsa.md#question-23-the-trust-policy-that-trusted-everyone)

---

## Question 2
**Interviewer asks:** "A security audit finds a pod making AWS API calls successfully, but its ServiceAccount has no IRSA annotation at all. How is this possible, and how serious is it?"

**Expected answer points:**
- Without an IRSA annotation, the pod silently falls back to the node's own IAM instance-profile role — no error, no warning.
- The actual severity depends entirely on how broad the node role's permissions are; likely broader than this specific workload needs.
- Fix: create a properly-scoped IRSA role for this workload and confirm (via CloudTrail's `userIdentity`) it's now using the new role, not the node's.

**Follow-up questions:**
1. Why does this fallback happen with no error at all?
2. How would you audit an entire cluster for other ServiceAccounts with this same gap?
3. Should the node role itself also be tightened as part of this fix?

**Red flags:** Says "it's working, so it's fine" — conflates functional success with least-privilege correctness, missing the actual security exposure.

**Model answer:** *"This is the standard AWS SDK credential-resolution fallback — without IRSA configuration, the pod falls through to the EC2 instance metadata service and picks up the node's own instance-profile credentials, entirely transparently and with no error. The severity depends on how broad the node role is, which is often scoped for general node operational needs and therefore broader than any single workload should have. I'd create a properly-scoped IRSA role for this specific workload, confirm via CloudTrail that its calls now show the new assumed role rather than the node's, and separately audit the cluster for other ServiceAccounts missing this same annotation."*

**Full reference:** [Question 24: The pod that fell back to the node](../interview-questions/03-iam-irsa.md#question-24-the-pod-that-fell-back-to-the-node)

---

## Question 3
**Interviewer asks:** "A pod was rescheduled onto a different node and got stuck unable to attach its existing EBS volume. What happened, and what's the fix?"

**Expected answer points:**
- EBS volumes are zonal — a PV created in one AZ can only attach to a node in that same AZ.
- Without `volumeBindingMode: WaitForFirstConsumer`, the PV may have been created before the pod was scheduled, in a mismatched AZ.
- Fix: `WaitForFirstConsumer` binding mode, deferring volume creation until the scheduler has chosen a node.

**Follow-up questions:**
1. Why doesn't this same problem happen with EFS?
2. How would you migrate an existing volume's data if a genuine cross-AZ move is needed?
3. What's the availability trade-off of relying on a single EBS volume for a stateful workload's AZ resilience?

**Red flags:** Proposes manually deleting and recreating the pod repeatedly, without addressing the actual AZ-mismatch root cause — the same failure would recur on the next reschedule.

**Model answer:** *"EBS volumes are zonal — a PV created in one AZ simply cannot attach to a node in a different AZ, a hard AWS-level constraint, not a scheduling bug. If the StorageClass uses `Immediate` binding mode, the PV can be created before the scheduler has even chosen a node, risking exactly this AZ mismatch on any future reschedule. The fix is `volumeBindingMode: WaitForFirstConsumer`, which defers volume creation until after scheduling, so the resulting PV's node affinity correctly constrains all future placement to the matching AZ."*

**Full reference:** [Question 43: The pod that couldn't follow its volume](../interview-questions/05-storage-stateful.md#question-43-the-pod-that-couldnt-follow-its-volume)

---

## Question 4
**Interviewer asks:** "Your team just discovered a Velero backup restore comes back with completely empty volumes, despite the backup job reporting success every night for months. Diagnose it."

**Expected answer points:**
- Velero's default behavior backs up Kubernetes resource manifests only — restoring PVC/PV objects gives new, empty volumes matching the spec, not the actual data, unless volume snapshotting (via the CSI plugin) was also configured.
- "Backup job reported success" only confirms the backup *process* ran without erroring — it says nothing about whether a restore would actually recover data.
- Fix: install/configure the Velero CSI plugin with `--snapshot-volumes=true`, and re-verify via an actual restore test.

**Follow-up questions:**
1. Why didn't the nightly "successful" backup job ever reveal this gap?
2. How would you establish periodic, actual restore-testing as a standing practice?
3. What's the cost/storage trade-off of enabling volume snapshotting for every scheduled backup?

**Red flags:** Assumes "the backup job succeeded every night" is sufficient evidence the backup strategy works — the exact false confidence this scenario exposes.

**Model answer:** *"Velero's default backup captures Kubernetes resource manifests only — restoring a PVC gives you a fresh, empty volume matching the same specification, not the actual underlying data, unless volume snapshotting via the CSI plugin was explicitly configured. A nightly 'successful' backup job only confirms the backup process itself didn't error — it says nothing about whether the resulting backup could actually restore real data, which is exactly the gap this incident reveals. I'd enable the CSI plugin with `snapshot-volumes: true`, and just as importantly, establish periodic, actual restore-testing as a standing practice, since 'the job succeeded' and 'the data is recoverable' are two different claims."*

**Full reference:** [Question 47: The Velero restore that came back empty](../interview-questions/05-storage-stateful.md#question-47-the-velero-restore-that-came-back-empty)

---

## Question 5
**Interviewer asks:** "You've enabled Pod Security Admission at `restricted` for a namespace, RBAC is correctly scoped, and NetworkPolicy is verified enforced. A colleague says the workload still isn't 'fully secured.' What are they likely pointing at?"

**Expected answer points:**
- Container-level hardening (`securityContext`: `runAsNonRoot`, dropped capabilities, `seccompProfile`) is a fifth, independent layer none of the others cover.
- The five-layer model (IAM/IRSA, RBAC, PSA, NetworkPolicy, container hardening) are non-substitutable — a gap in one isn't compensated by correctness in the others.
- A container running as root with full capabilities, even inside a PSA-compliant, RBAC-scoped, NetworkPolicy-enforced pod, still has a materially larger blast radius if compromised.

**Follow-up questions:**
1. Why doesn't Pod Security Admission alone guarantee container-level hardening?
2. How would you audit an entire fleet for this specific fifth-layer gap?
3. What's the actual risk difference between a hardened and unhardened container, given the other four layers are already correct?

**Red flags:** Agrees the workload is "basically secured" with four layers correct — misses that the fifth, container-level layer is a genuinely separate, non-overlapping concern.

**Model answer:** *"They're likely pointing at container-level hardening — `runAsNonRoot`, dropped Linux capabilities, `allowPrivilegeEscalation: false`, a `seccompProfile` — which is a fifth, entirely independent layer none of the other four cover. IAM/IRSA governs AWS API access, RBAC governs Kubernetes API access, PSA and NetworkPolicy govern pod-spec and network constraints, but none of them constrain what the actual running process can do at the kernel-syscall level if it's compromised. Getting four layers right doesn't compensate for a gap in the fifth — a container running as root with full capabilities has a meaningfully larger blast radius if compromised, regardless of how well the other four layers are configured."*

**Full reference:** [Question 66: Least privilege, checked at every layer but one](../interview-questions/07-security-hardening.md#question-66-least-privilege-checked-at-every-layer-but-one)

---

## Question 6
**Interviewer asks:** "Your team signs every container image with Cosign as part of CI, and has for six months. A security review finds this has provided essentially zero actual protection. Why?"

**Expected answer points:**
- Signing without admission-time *verification* provides an audit trail, not a deploy-time security control.
- The actual protection requires a Kyverno `verifyImages` policy (or equivalent) rejecting any image lacking a valid signature — which was never implemented.
- Fix: implement verification in audit mode first (given six months of unsigned/unverified history may include currently-running non-compliant images), then enforce.

**Follow-up questions:**
1. What's the actual difference between "signing" and "verification" as security controls?
2. How would you retroactively audit the past six months for any deployed images that would now fail verification?
3. What's the `failurePolicy` trade-off once verification is enabled?

**Red flags:** Says "we're signing every image, so we're protected against supply-chain tampering" — the exact misconception this scenario exposes.

**Model answer:** *"Signing alone, without admission-time verification, produces an audit trail — a record that a specific pipeline vouches for a specific image — but does nothing to prevent an unsigned or tampered image from being deployed, since nothing was ever checking for a valid signature before allowing a pod to run. The actual security control is a Kyverno `verifyImages` policy rejecting anything without a valid signature from the trusted identity, which this team never implemented. I'd roll it out in audit mode first, since six months of unsigned/unverified deployment history might include currently-running images that would fail a newly-introduced check, then move to enforcement once validated."*

**Full reference:** [Question 64: The signature nobody checked](../interview-questions/07-security-hardening.md#question-64-the-signature-nobody-checked)

---

## Question 7
**Interviewer asks:** "Design observability for a P50-latency dashboard that's reporting healthy, while a real incident is affecting 5% of your users severely. What's wrong with the dashboard, and how do you fix it?"

**Expected answer points:**
- P50 (median) is mathematically insensitive to a severe issue affecting a minority of traffic — the median request is still one of the unaffected majority.
- Fix: add P99 (and ideally P95/P90) monitoring/alerting, which specifically surfaces tail behavior.
- Segmentation (by pod, AZ, customer tier) as a complementary fix for identifying which subset is actually affected.

**Follow-up questions:**
1. Why specifically does P50 miss this while P99 catches it?
2. How would you choose which percentiles are worth actively alerting on, without over-alerting?
3. How would you retroactively check whether past incidents were similarly masked by aggregate-only monitoring?

**Red flags:** Treats this as an unusual, hard-to-predict edge case rather than a well-known, structural limitation of median-based monitoring.

**Model answer:** *"This is a well-known, structural limitation of P50 monitoring, not an unusual edge case — a percentile summarizes one point in a distribution, and P50 is mathematically insensitive to how bad the tail gets as long as the majority of traffic remains unaffected. The affected 5% simply doesn't show up in the median. I'd add P99 monitoring and alerting specifically, since it surfaces tail behavior directly, and I'd add segmentation by pod/AZ/customer tier as a complementary tool for identifying exactly which subset is actually affected once an issue is flagged."*

**Full reference:** [Question 83: The dashboard that lied by omission](../interview-questions/09-observability.md#question-83-the-dashboard-that-lied-by-omission)

---

## Question 8
**Interviewer asks:** "Your Prometheus instance goes silently down for six hours due to a resource-exhaustion issue on its own pod. During that window, an unrelated production incident occurs completely undetected. What's the architectural fix, beyond just fixing the resource exhaustion?"

**Expected answer points:**
- A monitoring system's own silent failure is a genuine, dangerous blind spot — nothing about the monitoring stack's own outage triggers its own alerts, since it's not evaluating anything during that window.
- Fix: a "dead man's switch" — an externally, independently-running service expecting a continuous heartbeat, alerting via a separate path if that heartbeat stops.
- The external watchdog must be genuinely independent (different failure domain) from the primary monitoring stack.

**Follow-up questions:**
1. Why can't you just add more alert rules inside Prometheus to catch this?
2. Where would you run the dead-man's-switch service to ensure genuine failure-domain independence?
3. How does this connect to the same principle applied to a GitOps controller's own availability during a DR event?

**Red flags:** Proposes adding more Prometheus alert rules as the fix — misses that any additional rule still depends on Prometheus itself being healthy enough to evaluate it.

**Model answer:** *"Any additional Prometheus alert rule still depends on Prometheus itself being alive and evaluating rules — it can't detect its own silent failure. The actual fix is a dead-man's-switch pattern: an externally, independently-running service expecting a continuous heartbeat from the monitoring stack, alerting via a completely separate notification path the moment that heartbeat stops. It needs genuine failure-domain independence — ideally not even sharing infrastructure with the primary monitoring stack — so a shared root cause can't take down both the monitor and its own watchdog simultaneously. This is the same 'who watches the watcher' principle that applies to a GitOps controller's own availability during a DR event."*

**Full reference:** [Question 85: Monitoring the monitors](../interview-questions/09-observability.md#question-85-monitoring-the-monitors)

---

## Question 9
**Interviewer asks:** "An on-call engineer runs `kubectl scale --replicas=10` on a GitOps-managed Deployment during an active incident, and it reverts two minutes later. What actually happened, and what should the engineer have done instead?"

**Expected answer points:**
- GitOps self-healing correctly reverted the manual change, since it diverged from Git's declared state — this is intended, documented behavior, not a bug.
- The correct emergency action is committing the change to Git (or deliberately, temporarily pausing auto-sync), never a direct `kubectl` change against a GitOps-managed resource.
- Design implication: a fast-path emergency Git-commit process, or a pre-configured HPA with sufficient `maxReplicas` headroom, so the correct action is fast enough to actually use under pressure.

**Follow-up questions:**
1. Why doesn't ArgoCD distinguish an "emergency" manual change from an accidental one?
2. What's the risk of routinely pausing auto-sync as an emergency workaround?
3. How would you train on-call engineers on this behavior before it costs time during a real incident?

**Red flags:** Concludes ArgoCD has a bug reverting "legitimate emergency changes" — misses that this is documented, intentional self-healing behavior.

**Model answer:** *"This is GitOps's self-healing working exactly as designed, not a bug — the reconciliation loop detected live state diverging from Git's declared state and corrected it, with no way to distinguish 'an accidental drift' from 'a deliberate emergency change,' since both look identical to the controller. The correct emergency action is committing the replica-count change directly to Git, letting the same reconciliation loop converge toward and *maintain* the new value — or, if speed is critical, temporarily pausing auto-sync with an explicit, tracked follow-up to resume it. I'd make sure on-call engineers know this behavior before an incident, not discover it mid-incident, and I'd consider a pre-configured HPA with generous headroom to reduce how often a manual scale-up is even needed."*

**Full reference:** [Question 87: The kubectl apply that fought the GitOps controller](../interview-questions/10-cicd-gitops.md#question-87-the-kubectl-apply-that-fought-the-gitops-controller)

---

## Question 10
**Interviewer asks:** "A canary deployment's `AnalysisTemplate` reported success, and the rollout promoted to 100% — but the new version was actually broken the whole time. How did automated analysis miss this?"

**Expected answer points:**
- The `AnalysisTemplate`'s PromQL query was likely unscoped — measuring service-wide error rate rather than the canary's own traffic specifically.
- Early in a canary rollout (e.g., 10% weight), a genuinely broken canary's errors get diluted by the much larger volume of healthy stable traffic, producing a false pass.
- Fix: scope the query to the canary's specific `rollouts-pod-template-hash` label.

**Follow-up questions:**
1. Why does this dilution effect get worse the smaller the canary's traffic percentage is?
2. How would you validate a new `AnalysisTemplate`'s correctness before trusting it for a real rollout?
3. What other metrics beyond error rate might have this same dilution risk?

**Red flags:** Assumes the canary must have genuinely been healthy since analysis passed, without questioning whether the query itself was measuring the right thing.

**Model answer:** *"A passing analysis result is only as trustworthy as the query behind it — this is almost certainly an unscoped query measuring error rate across the *entire* service rather than the canary specifically, meaning at low canary traffic weight, its genuine errors get diluted by the much larger volume of healthy stable traffic and the aggregate still looks fine. The fix scopes the PromQL query to the canary's specific pod-template-hash label, so it measures only what the canary itself is actually serving. I'd validate any new AnalysisTemplate against a deliberately-broken test canary before trusting it for a real, consequential rollout."*

**Full reference:** [Question 89: The AnalysisTemplate that measured the wrong thing](../interview-questions/10-cicd-gitops.md#question-89-the-analysistemplate-that-measured-the-wrong-thing)

---

## Question 11
**Interviewer asks:** "Design the correct CI/CD pipeline for Kubernetes manifests in a GitOps world — what does CI still own, and what moves to the GitOps controller?"

**Expected answer points:**
- CI's job narrows to: build/test the app, build/scan/sign the image, and commit the new image reference to the GitOps repo — never `kubectl apply`/`helm upgrade` directly.
- The actual deployment step is the GitOps controller's own reconciliation, decoupled from CI's completion.
- Concurrency control (never two runs racing to commit to the same GitOps target) and pinned, atomic artifact identity (a digest, computed and referenced within the same run) are both required to avoid a race condition.

**Follow-up questions:**
1. What's the actual risk if two CI runs for near-simultaneous commits aren't serialized?
2. Why does using a digest instead of a mutable tag matter here specifically?
3. How would you validate this pipeline design catches the exact race condition it's meant to prevent?

**Red flags:** Describes a pipeline where CI directly applies manifests to the cluster — misses the core GitOps principle that deployment is the controller's job, not CI's.

**Model answer:** *"In a GitOps model, CI's role narrows specifically to building and testing the app, building/scanning/signing the image, and committing the resulting image reference — ideally an immutable digest, not a mutable tag — to the GitOps repository. It should never `kubectl apply` or `helm upgrade` directly; the actual deployment is the GitOps controller's own reconciliation, entirely decoupled from when CI happens to finish. I'd also add a concurrency group serializing runs targeting the same deployment target, since without it, two near-simultaneous commits could interleave their build/validate/commit steps and pair a validated manifest with the wrong image."*

**Full reference:** [Question 95: The pipeline that tested the wrong artifact](../interview-questions/10-cicd-gitops.md#question-95-the-pipeline-that-tested-the-wrong-artifact)

---

## Question 12
**Interviewer asks:** "How would you migrate a cluster from Calico-based NetworkPolicy enforcement to native VPC CNI enforcement, given both implement the same Kubernetes NetworkPolicy API?"

**Expected answer points:**
- Implementing the same API surface doesn't guarantee identical enforcement behavior at every edge case — each has its own independent enforcement engine.
- Never assume equivalence — run both in parallel (or validate exhaustively in non-production) with positive-control tests for every existing policy before decommissioning Calico.
- Any Calico-specific extension (e.g., `GlobalNetworkPolicy`) has no native equivalent and needs an explicit plan.

**Follow-up questions:**
1. Why might the two implementations genuinely differ in behavior despite the same API?
2. How would you handle a policy relying on a Calico-only feature?
3. What's your rollback plan if the migration reveals a gap only after Calico is already removed?

**Red flags:** Assumes migrating is safe simply because both consume the same standard NetworkPolicy object — misses that enforcement behavior isn't guaranteed identical.

**Model answer:** *"Both consuming the same NetworkPolicy API doesn't guarantee identical enforcement behavior — each has its own independent engine translating that declarative object into actual datapath rules, and subtle differences at edge cases are genuinely possible. I'd never assume equivalence; I'd inventory every existing policy including any Calico-specific extensions like `GlobalNetworkPolicy`, run positive-control tests for each under the native implementation in a non-production cluster mirroring production's real policy set, and only decommission Calico once every single policy's enforcement behavior is confirmed equivalent — keeping Calico installed, even if redundant, until that validation is complete."*

**Full reference:** [Question 22: The migration from Calico that nobody tested](../interview-questions/02-networking.md#question-22-the-migration-from-calico-that-nobody-tested)

---

## Question 13
**Interviewer asks:** "A CI pipeline for a shared, organization-wide Kubernetes manifest template has never been tested itself. A recent change silently broke every project using it simultaneously. What should have been true before this happened?"

**Expected answer points:**
- A shared, organization-wide template deserves the *highest*, not lowest, testing rigor, given its blast radius spans every consumer at once.
- "It's been running for years without issues" describes accumulated risk, not evidence of safety.
- Fix: a contract-test suite using representative consumer repositories, run before any change is published, plus backward-compatible transitions for breaking changes.

**Follow-up questions:**
1. Why is a shared template's testing need different from a single project's own CI pipeline?
2. How would you select representative consumer repositories for the contract-test suite?
3. What's the right way to introduce a genuinely necessary breaking change safely?

**Red flags:** Says "it was stable for years, this was just an unlucky one-off" — dismisses a systemic testing gap as bad luck.

**Model answer:** *"'Stable for years without testing' describes accumulated risk, not safety — it just means no one had introduced a genuinely breaking change yet. A shared, organization-wide template needs the highest testing rigor precisely because its blast radius spans every consumer simultaneously, unlike a single project's own pipeline where a mistake is contained. I'd build a contract-test suite using a representative sample of real consumer repositories, run automatically before any template change is published, and for something like a new required variable, I'd introduce it as optional-with-a-safe-default first, giving consumers time to adopt it before it's ever required."*

**Full reference:** [Question 86: Testing the thing that tests everything else](../../../ansible/ansible-senior-interview-preparation/interview-questions/09-testing-validation.md#question-86-testing-the-thing-that-tests-everything-else)

---

## Question 14
**Interviewer asks:** "How would you build a system so your team can quickly answer 'which of our 60 workloads depend on this shared internal service' during a live incident?"

**Expected answer points:**
- Reconstructing this live, during every incident involving a shared dependency, is a preventable, structural readiness gap.
- Build an automated, continuously-updated dependency map derived from real observed traffic (tracing data), not manually-maintained documentation.
- Validate periodically against real traffic; test the capability via a tabletop exercise before a real incident needs it.

**Follow-up questions:**
1. Why is tracing-derived mapping preferable to manually-maintained documentation?
2. How would you catch a genuinely low-traffic or intermittent dependency the map might miss?
3. How would you structure a tabletop exercise validating this capability?

**Red flags:** Proposes "ask each of the 60 teams during the incident" as an acceptable ongoing process — slow and unreliable exactly when speed matters most.

**Model answer:** *"Reconstructing this live during every incident is a preventable readiness gap, not something to keep solving reactively. I'd build this once, ideally auto-derived from distributed tracing data — real, observed call graphs naturally encode which services actually depend on which others, and stay current automatically rather than going stale like manually-maintained documentation would. I'd validate it periodically against real traffic and specifically run a tabletop exercise simulating a shared-dependency outage to confirm the team can answer 'who's affected' quickly using this tooling, well before a real incident tests it for the first time."*

**Full reference:** [Question 104: The incident that revealed the team didn't know their own dependencies](../interview-questions/11-troubleshooting.md#question-104-the-incident-that-revealed-the-team-didnt-know-their-own-dependencies)

---

## Question 15
**Interviewer asks:** "Two senior engineers disagree for weeks on whether to adopt Karpenter or stay with Cluster Autoscaler. As the lead, how do you resolve this?"

**Expected answer points:**
- Convert both positions into specific, testable claims rather than abstract preferences.
- Run a bounded, time-boxed pilot testing the real workload patterns with both approaches, deciding on real evidence by a committed date.
- Never unilaterally override without incorporating both engineers' genuine expertise.

**Follow-up questions:**
1. How would you handle an inconclusive pilot result?
2. How would you communicate the decision to the "losing" side while preserving trust?
3. What specific evidence would most likely settle this particular debate?

**Red flags:** "As the lead, I'd just decide" with no evidence-gathering process — risks a worse decision and damages team trust.

**Model answer:** *"I wouldn't unilaterally decide — I'd convert both positions into testable claims and run a bounded, time-boxed pilot on a subset of the fleet's actual workload patterns with both approaches, evaluated against concrete criteria: cost impact from consolidation, provisioning latency for spiky demand, and genuine operational complexity. I'd set a decision date upfront so the evidence-gathering process itself doesn't become another source of stalled uncertainty, and whichever way it lands, I'd make sure both engineers see their input reflected in the final reasoning, not just the outcome."*

**Full reference:** [Question 119: The architecture decision nobody wanted to own](../interview-questions/15-migration-leadership.md#question-119-the-architecture-decision-nobody-wanted-to-own)

---

## Scoring Rubric Reference
- **1 (Beginner):** Definitions only, no production experience, no failure handling.
- **2 (Intermediate):** Understands normal implementation, limited troubleshooting, weak security/scale awareness.
- **3 (Senior):** Explains production implementation, covers validation and rollback, understands idempotency/security/maintainability.
- **4 (Lead):** Explains architecture trade-offs, covers team governance and scale, anticipates failure modes, offers preventive controls. **This is the target bar for this interview.**
- **5 (Staff/Architect):** Connects technical choices to business risk, designs for multiple teams/clusters, covers blast radius/security/cost/compliance/HA/DR.

For this Lead-level mock, a candidate consistently scoring 4+ across all 15 questions is interview-ready for Lead Platform Engineer roles. Consistent 5s suggest readiness for Staff-level interviews — try [Mock Interview 3](mock-interview-03-staff-platform-architect.md) next.
