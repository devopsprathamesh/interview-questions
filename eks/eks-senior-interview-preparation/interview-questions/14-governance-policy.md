# Category 14: Governance and Policy as Code (OPA/Kyverno)

Questions 115–117 of 120. Category weight: 3 questions. Deep-dive reference: [`docs/governance-policy.md`](../docs/governance-policy.md).

---

## Question 115: The policy that blocked its own emergency fix

### Scenario
During an active production incident, an on-call engineer attempts to apply an emergency hotfix manifest with a slightly relaxed resource limit (to handle unexpectedly high load) but is blocked by a Kyverno policy requiring resource limits to fall within a specific, pre-approved range. There's no documented emergency-bypass process.

### Interview Question
Diagnose this policy-enforcement/incident-response conflict and design a resolution.

### Strong Senior-Level Answer
**Initial assessment:** per [`docs/governance-policy.md`](../docs/governance-policy.md) §2's `failurePolicy` trade-off discussion (generalized here to policy design overall), a policy with no legitimate emergency-bypass mechanism creates exactly this conflict — the policy is correctly doing its job (preventing an unreviewed, out-of-range resource configuration), but the *process* around it never accounted for a genuinely legitimate, time-critical exception need.

**Technical reasoning:** admission policies are binary (allow or deny) unless explicitly designed with an exception mechanism — Kyverno supports policy exceptions (`PolicyException` resources) allowing specific, pre-authorized deviations from a general rule, but if none exists for this scenario, the on-call engineer has no sanctioned path around the block during a genuine emergency, forcing either a dangerous, ad hoc policy-disabling action or continued blockage during an active incident.

**Investigation process:** confirm whether any `PolicyException` mechanism or documented emergency-override process exists at all for this policy — if not, this incident is exposing a genuine gap in the policy's operational design, not a flaw in the policy's underlying intent.

**Recommended solution:** for the immediate incident, use whatever break-glass mechanism exists for policy exceptions (if genuinely none exists, this may require a platform-team member with elevated permissions to temporarily create a scoped `PolicyException` for this specific resource, as an explicit, logged, temporary action) — then, immediately following the incident, implement a proper, pre-authorized emergency-exception mechanism (a `PolicyException` template requiring on-call lead sign-off, or a pre-approved wider resource-limit range specifically for declared-incident conditions) so this exact conflict doesn't recur.

**Risk controls:** any emergency exception mechanism must itself be tightly scoped, logged, and time-bound (e.g., auto-expiring after a defined window) — an emergency bypass that becomes a permanent, unreviewed backdoor defeats the policy's original purpose entirely.

**Validation steps:** test the newly-designed emergency-exception process in a simulated incident scenario, confirming it provides a genuinely fast, usable path during a real emergency while still requiring appropriate authorization and leaving an audit trail.

**Rollback or recovery strategy:** ensure any emergency exception applied during the incident is explicitly reverted/expired once the emergency passes, returning to the normal, fully-enforced policy state.

**Long-term prevention:** treat "does every enforced policy have a legitimate, documented, appropriately-controlled emergency-exception path" as a standard policy-design review question, alongside the audit-mode rollout discipline from [`docs/governance-policy.md`](../docs/governance-policy.md) §3 — a policy without any escape hatch for genuine emergencies will eventually create exactly this kind of conflict during a real incident.

### Step-by-Step Implementation
```yaml
apiVersion: kyverno.io/v2beta1
kind: PolicyException
metadata:
  name: incident-emergency-exception
  namespace: production
spec:
  exceptions:
    - policyName: require-resource-limit-range
      ruleNames: ["check-resource-limits"]
  match:
    any:
      - resources:
          kinds: [Pod]
          namespaces: [production]
  conditions:
    all:
      - key: "{{ request.object.metadata.labels.incident-exception }}"
        operator: Equals
        value: "true"   # explicit, deliberate opt-in label, not a blanket bypass
```

### Under-the-Hood Explanation
Kyverno's `PolicyException` resource allows scoped, explicit carve-outs from an otherwise-enforced policy, evaluated by the same admission controller alongside the base policy — designing this correctly (narrow match criteria, an explicit opt-in condition like a specific label) ensures the exception applies only to deliberately-flagged, genuinely-exceptional resources, not silently weakening the policy's enforcement for anything else.

### Common Weak Answer
"Just temporarily disable the policy entirely during incidents."

### Why the Weak Answer Fails
Disabling the entire policy removes protection for every resource, not just the specific emergency one — a scoped, explicit exception mechanism (per the implementation above) provides the needed emergency flexibility without exposing the whole namespace/cluster to unrelated, unreviewed configurations during the same window.

### Follow-Up Questions
1. How would you design the authorization/approval workflow for creating an emergency `PolicyException` quickly during a real incident?
2. How would you ensure emergency exceptions are automatically reverted/expired rather than becoming permanent, forgotten exceptions?
3. How does this scenario connect to the broader `failurePolicy: Fail` vs. `Ignore` trade-off from `docs/governance-policy.md` §2?

### Key Interview Signals
Recognizes the conflict as a policy-design gap (missing emergency-exception mechanism) rather than a reason to disable policy enforcement broadly, and designs a properly-scoped, temporary, audited exception process.

### Hands-On Connection
[Lab 13 — Policy as Code](../labs/lab-13-policy-as-code-opa/) and [Lab 14 — Troubleshooting and Recovery](../labs/lab-14-troubleshooting-and-recovery/).

---

## Question 116: The policy that passed in CI but failed in the cluster

### Scenario
A `kyverno test` run in CI passes cleanly for a new manifest. The same manifest, once merged and synced by ArgoCD, is rejected by the live cluster's admission webhook with a policy violation the CI test never caught.

### Interview Question
Diagnose this CI-versus-live-cluster policy discrepancy.

### Strong Senior-Level Answer
**Initial assessment:** per [`docs/governance-policy.md`](../docs/governance-policy.md) §4, `kyverno test` validates a manifest against a *local* copy of policy definitions provided to the test command — if the live cluster's actual, currently-enforced policies have since diverged from what CI's local test fixtures reference (a newer or different policy version deployed to the cluster but not correspondingly updated in the CI test repository), CI can pass while the live cluster legitimately enforces something different.

**Technical reasoning:** `kyverno test` is a static, offline evaluation against whatever `ClusterPolicy` YAML files are provided to it as test input — it has no live connection to the actual cluster's currently-deployed policies unless the CI process explicitly keeps its local policy fixtures synchronized with what's actually deployed, which is exactly the kind of "two copies of the same thing that need to stay in sync but have no enforced mechanism to do so" gap this repository series repeatedly flags.

**Investigation process:** compare the specific policy version/content CI tested against with what's actually currently deployed and enforced in the live cluster — this will very likely reveal a version mismatch (the cluster has a newer, stricter, or otherwise different policy than what CI's local fixtures reflect).

**Recommended solution:** establish CI's policy test fixtures as genuinely synchronized with the live, deployed policy set — ideally by having CI pull the *actual* currently-deployed `ClusterPolicy` definitions directly from the same GitOps repository that manages what's live in the cluster (single source of truth), rather than maintaining a separate, potentially-stale copy specifically for CI testing purposes.

**Risk controls:** if policies are managed via the same GitOps repository CI already validates against, ensure the CI test step explicitly references the current, in-repository policy definitions (not a cached, separately-maintained, or hardcoded older copy) — closing the synchronization gap at its source.

**Validation steps:** after fixing the synchronization, confirm a deliberately-crafted manifest that should fail under the current, live policy set is correctly caught and failed by `kyverno test` in CI as well, proving the two are now genuinely aligned.

**Rollback or recovery strategy:** for the specific incident, the manifest that failed live-cluster admission needs correction to actually satisfy the current policy — not a CI-side workaround, since the live cluster's enforcement is the actual, authoritative gate.

**Long-term prevention:** treat "does CI test against the exact same policy definitions currently enforced live" as a standing verification, ideally structurally guaranteed (single source of truth, same repository/reference) rather than something that can silently drift out of sync over time, exactly the same "single source of truth" discipline established throughout this repository series' GitOps and configuration-management guidance.

### Step-by-Step Implementation
```yaml
# CI step - pull policy definitions from the SAME repo/path the cluster's GitOps
# controller reconciles from, not a separately-maintained CI-only copy
- name: Run kyverno test against current, live-matching policies
  run: |
    kyverno test ./policies/ --manifest ./test-manifests/
    # ./policies/ is the SAME directory ArgoCD syncs to the cluster - no separate copy
```

### Under-the-Hood Explanation
`kyverno test` is entirely self-contained and offline — it has no mechanism to query a live cluster's actual currently-enforced policy state unless explicitly pointed at policy definitions that are kept identical to what's deployed; any divergence between the test's input policies and the cluster's live policies (through separate maintenance, version lag, or manual live-cluster policy changes outside the GitOps flow) produces exactly this kind of "passed in CI, failed live" discrepancy.

### Common Weak Answer
"kyverno test must be buggy if it doesn't match the live cluster's behavior."

### Why the Weak Answer Fails
`kyverno test` behaves exactly as designed — evaluating against whatever policy input it's given; the actual gap is a synchronization failure between that input and the live cluster's actual policy set, not a defect in the testing tool itself.

### Follow-Up Questions
1. How would you structure the repository layout to guarantee CI and the live cluster always reference the identical policy source?
2. What's the risk if a live-cluster policy was manually changed outside the GitOps flow (connecting to Question 87's manual-change-reversion discussion)?
3. How would you extend this same single-source-of-truth discipline to other CI validation steps beyond policy testing?

### Key Interview Signals
Correctly identifies a policy-fixture synchronization gap (not a tooling defect) as the root cause, and fixes it by establishing a genuine single source of truth for policy definitions used by both CI and the live cluster.

### Hands-On Connection
[Lab 13 — Policy as Code](../labs/lab-13-policy-as-code-opa/) and [Lab 12 — CI/CD Pipeline](../labs/lab-12-cicd-pipeline/).

---

## Question 117: One policy set, twenty clusters, twenty opinions

### Scenario
The 20-cluster platform (from Category 8's scenarios) currently has each cluster's platform-adjacent team independently maintaining their own slightly-different set of Kyverno policies, having each started from the same original baseline years ago but drifted independently since. A new compliance mandate requires proving a specific, consistent security policy is enforced identically across all 20 clusters.

### Interview Question
Diagnose this governance gap and design the remediation.

### Strong Senior-Level Answer
**Initial assessment:** twenty independently-drifted policy sets, all supposedly descended from the same original baseline, is precisely the security-baseline-consistency gap from Question 68 (Category 7) recurring here at the policy-governance layer specifically — proving "consistent enforcement across all 20 clusters" is currently impossible, since the actual, current policy content genuinely differs cluster by cluster, not just in appearance but in real enforcement behavior.

**Technical reasoning:** without a single, centrally-managed policy source that every cluster's GitOps controller reconciles identically from (per Question 68's baseline-bootstrap pattern, applied here to policy specifically rather than the full security baseline), each cluster team's independent, well-intentioned local adjustments over time compound into genuine divergence — some clusters may be stricter, some more permissive, and none of it is currently provable or consistent.

**Investigation process:** diff all 20 clusters' current, actual Kyverno `ClusterPolicy` definitions against each other and against the original baseline, categorizing each divergence (a deliberate, justified cluster-specific exception versus unintentional drift that should be reconciled back to a common standard).

**Recommended solution:** establish a single, centrally-managed policy repository (mirroring Question 68's security-baseline pattern) that every cluster's GitOps controller reconciles from for the specific compliance-mandated policies, with any genuinely necessary cluster-specific variation expressed as an explicit, reviewed, and documented exception (via Kustomize overlays or Kyverno `PolicyException` resources) rather than an independently-maintained, drifted copy.

**Risk controls:** rolling out the now-centrally-managed policy set across 20 clusters risks the same kind of unexpected-legitimate-traffic-blocking issue as any policy enforcement rollout (per [`docs/governance-policy.md`](../docs/governance-policy.md) §3) — stage this in audit mode first, per cluster, reviewing what each cluster's actual current state would newly violate under the consolidated policy before switching to enforcement.

**Validation steps:** after consolidation, run an automated, scheduled compliance check (comparing each cluster's actual deployed policy definitions against the central source) proving ongoing consistency, not just a one-time snapshot satisfying the current audit — since without this ongoing check, the same independent-drift problem will simply recur over time.

**Rollback or recovery strategy:** for any cluster where consolidation reveals a currently-non-compliant workload that would newly be blocked, work with that cluster's team to remediate the workload (or grant an explicit, reviewed, temporary exception) before flipping that cluster to full enforcement.

**Long-term prevention:** treat policy-set consistency across a shared cluster fleet as a continuously-monitored, centrally-governed concern (exactly like the security-baseline bootstrap from Question 68) rather than something delegated entirely to independent per-cluster teams to maintain "consistently" without any structural mechanism actually ensuring that consistency persists over time.

### Step-by-Step Implementation
```yaml
# Central policy repository, reconciled identically to every cluster via GitOps
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: compliance-policies
spec:
  generators:
    - clusters: {}   # applies to every registered cluster
  template:
    spec:
      source:
        repoURL: https://github.com/my-org/compliance-policy-baseline
        targetRevision: v2.1.0   # single, versioned, centrally-reviewed source
        path: policies
      syncPolicy:
        automated: { prune: true, selfHeal: true }
```
```bash
# Ongoing, scheduled compliance-consistency check across all 20 clusters
for cluster in $(cat clusters.txt); do
  diff <(kubectl --context "$cluster" get clusterpolicy -o yaml) central-baseline-policies.yaml
done
```

### Under-the-Hood Explanation
Once policy management is consolidated into a single, `ApplicationSet`-driven GitOps source applied identically across every registered cluster, each cluster's GitOps controller independently reconciles toward the same, single, versioned policy definition — restoring the actual consistency guarantee the compliance mandate requires, with any needed cluster-specific variation made explicit and reviewable (rather than silently, independently drifted) via a clearly-delineated exception mechanism.

### Common Weak Answer
"Just ask each of the 20 cluster teams to manually sync their policies to match a shared reference document."

### Why the Weak Answer Fails
This is exactly the process that produced the current drift in the first place — a manually-coordinated, per-team-maintained approach with no structural enforcement mechanism will predictably drift again over time; the durable fix is a single, GitOps-reconciled source of truth applied identically, not a renewed manual coordination effort.

### Follow-Up Questions
1. How would you handle a cluster team's legitimate need for a genuinely different policy exception, without allowing this to become the seed of a new, unmanaged drift?
2. How would you present the ongoing, scheduled compliance-consistency check's results to the compliance team as defensible, audit-ready evidence?
9. How does this policy-consolidation effort relate to the broader security-baseline consolidation from Question 68 — should they be the same initiative?

### Key Interview Signals
Diagnoses independently-maintained, drifted policy sets as a structural governance gap (not a per-team diligence failure) and designs a centrally-managed, GitOps-reconciled solution with an ongoing, automated consistency check rather than a one-time manual reconciliation.

### Hands-On Connection
[Lab 13 — Policy as Code](../labs/lab-13-policy-as-code-opa/) and [Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).
