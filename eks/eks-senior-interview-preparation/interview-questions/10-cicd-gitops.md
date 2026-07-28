# Category 10: CI/CD and GitOps (ArgoCD/Flux, Progressive Delivery)

Questions 87–98 of 120. Category weight: 12 questions. Deep-dive reference: [`docs/cicd-gitops.md`](../docs/cicd-gitops.md).

---

## Question 87: The kubectl apply that fought the GitOps controller

### Scenario
During an incident, an on-call engineer runs `kubectl scale deployment my-app --replicas=10` directly to handle a traffic spike. Two minutes later, the replica count silently reverts to 3.

### Interview Question
Explain why the manual scale-up was reverted, and what the on-call engineer should have done instead.

### Strong Senior-Level Answer
**Initial assessment:** per [`docs/cicd-gitops.md`](../docs/cicd-gitops.md) §2, this is GitOps's self-healing behavior working exactly as designed — the GitOps controller's continuous reconciliation detected the live replica count diverging from what's declared in Git (still 3) and corrected it, exactly as it would for any other unintended drift; the manual `kubectl scale` wasn't "reverted by a bug," it was overwritten by the very mechanism GitOps provides for consistency.

**Technical reasoning:** ArgoCD/Flux don't distinguish between "an accidental manual change" and "a deliberate, urgent incident-response action" — both look identical from the reconciliation loop's perspective: live state diverges from Git-declared state, and (if auto-sync/self-heal is enabled) it corrects the divergence on its next reconciliation pass, regardless of the human intent behind the divergence.

**Investigation process:** confirm the GitOps controller's sync/self-heal settings for this application (this is expected behavior if self-heal is enabled, not a malfunction) and confirm the actual Git-declared replica count is indeed still 3.

**Recommended solution:** for an urgent, genuine incident-response scale-up, the correct action is committing the change *to Git* (updating the replica count in the manifest/values file and merging/pushing it) so the GitOps controller reconciles *toward* the new desired state rather than away from an out-of-band manual change — or, if a true emergency requires bypassing the normal Git review process, temporarily pausing the GitOps controller's auto-sync for this specific application before making the manual change, with an explicit, tracked follow-up to either commit the change to Git or resume normal sync once the emergency has passed.

**Risk controls:** pausing auto-sync (if used as an emergency bypass) should be treated as inherently temporary and explicitly tracked — a paused application means Git and live state are now free to diverge indefinitely with no automatic correction, exactly the kind of untracked exception this repository series consistently warns against if left in place too long.

**Validation steps:** after committing the correct change to Git, confirm the GitOps controller picks it up and the replica count is now maintained at the new value going forward (surviving future reconciliation passes, unlike the manual change).

**Rollback or recovery strategy:** once the incident subsides, commit the reversion (back to 3, or whatever the appropriate steady-state value is) to Git as well, so the GitOps-managed desired state accurately reflects the post-incident intended configuration.

**Long-term prevention:** train on-call engineers explicitly on this GitOps behavior (manual, out-of-band changes get reverted, by design) as part of incident-response onboarding, and consider a fast-path, pre-approved emergency-scaling mechanism (e.g., a documented, quick Git-commit process, or a pre-configured HPA with sufficiently high `maxReplicas` removing the need for a manual scale-up at all) so the correct action is fast enough to actually use during a real incident.

### Step-by-Step Implementation
```bash
# Correct: commit the emergency scale-up to Git
git commit -am "Emergency: scale my-app to 10 replicas for traffic spike"
git push
# ArgoCD picks this up and reconciles toward 10 replicas, and MAINTAINS it
```

### Under-the-Hood Explanation
The GitOps controller's reconciliation loop runs continuously, comparing live cluster state against the Git-declared manifest on every cycle — a manual `kubectl scale` changes live state but does nothing to the Git-declared value the controller is reconciling toward, so the very next reconciliation cycle (typically within seconds to a few minutes, depending on configured sync interval) simply restores the replica count to whatever Git still says, exactly as it's designed to do for any other form of drift.

### Common Weak Answer
"The GitOps controller must have a bug reverting legitimate emergency changes."

### Why the Weak Answer Fails
This is documented, intentional GitOps behavior (continuous self-healing reconciliation toward Git-declared state), not a bug — understanding this correctly is exactly what leads to the right process (commit to Git, or deliberately pause sync) rather than repeatedly fighting the controller with more manual changes that will keep getting reverted.

### Follow-Up Questions
1. How would you design a fast-path emergency Git-commit process that's quick enough to actually use during a real, time-pressured incident?
2. What's the risk of relying on pausing auto-sync as a routine emergency-response pattern rather than an exception?
3. How would a pre-configured HPA with generous `maxReplicas` have avoided needing this manual intervention in the first place?

### Key Interview Signals
Correctly identifies GitOps self-healing as the expected cause (not a bug) and redirects incident response toward committing the change to Git, the actually-correct action within a GitOps-managed system.

### Hands-On Connection
[Lab 10 — GitOps with ArgoCD](../labs/lab-10-gitops-argocd/).

---

## Question 88: The canary that never got promoted

### Scenario
An Argo Rollouts canary deployment successfully passes its automated analysis at 10% traffic and again at 50%, but then sits indefinitely at 50% traffic, never promoting to 100%, with no error reported anywhere.

### Interview Question
Diagnose why a successful canary might stall short of full promotion.

### Strong Senior-Level Answer
**Initial assessment:** per [`docs/cicd-gitops.md`](../docs/cicd-gitops.md) §3, a Rollout can be configured with a manual promotion gate (`pause: {}` with no `duration`, requiring an explicit `kubectl argo rollouts promote` or approval action) at any step — a canary sitting indefinitely at a specific traffic percentage, despite passing automated analysis, most commonly indicates the rollout reached a step configured for manual approval rather than fully automated promotion, and nobody has yet approved it.

**Technical reasoning:** Argo Rollouts distinguishes between a `pause` step with a `duration` (automatically resumes after the specified time) and one without (waits indefinitely for an explicit, manual `promote` action) — if the rollout strategy's steps include the latter at the 50% stage specifically, "successfully passed analysis" and "waiting for manual approval" are two entirely separate, sequential conditions, and passing the first doesn't automatically satisfy the second.

**Investigation process:** confirm via `kubectl argo rollouts get rollout my-app` the rollout's exact current status and step definition — this will explicitly show whether it's paused awaiting manual promotion versus stuck due to a genuine, unreported issue.

**Recommended solution:** if a manual approval gate is indeed the cause and the canary's results are genuinely satisfactory, manually promote it (`kubectl argo rollouts promote my-app`); if manual gates at this stage aren't actually the team's intended design (perhaps inherited from a template without full understanding), reconsider whether this specific stage should be automated (time-based `duration`) instead.

**Risk controls:** whichever gate design is used, ensure it's a deliberate choice communicated to the team — an unreviewed manual gate no one is monitoring for (as apparently happened here) effectively stalls every rollout indefinitely until someone happens to notice, a real availability/velocity risk for the deployment process itself.

**Validation steps:** after promotion (or reconfiguration to automated gating), confirm the rollout proceeds to 100% and completes, with the old ReplicaSet correctly scaled down.

**Rollback or recovery strategy:** if the canary's results at 50% actually reveal a problem upon closer review (rather than genuinely being ready for promotion), abort the rollout (`kubectl argo rollouts abort`) rather than promoting a genuinely problematic canary just to clear the stall.

**Long-term prevention:** document each application's specific Rollout strategy (which stages are automated vs. manually gated, and why) clearly, and consider alerting on a rollout that's been paused awaiting manual approval for longer than an expected threshold, so a forgotten approval gate doesn't silently stall a deployment indefinitely.

### Step-by-Step Implementation
```bash
# Diagnose the exact pause reason
kubectl argo rollouts get rollout my-app

# If genuinely ready, promote manually
kubectl argo rollouts promote my-app
```
```yaml
# Rollout strategy showing the manual gate explicitly
strategy:
  canary:
    steps:
      - setWeight: 10
      - analysis: { templates: [{ templateName: success-rate }] }
      - setWeight: 50
      - pause: {}   # no duration - waits indefinitely for manual promote
      - setWeight: 100
```

### Under-the-Hood Explanation
Argo Rollouts' step-based canary strategy processes each step sequentially, and a `pause: {}` step with no `duration` field is specifically designed to halt progression indefinitely until an external action (`promote`) is received — this is a deliberate design feature for workflows requiring human sign-off at a specific stage, not an error state, and the rollout controller correctly reports this as "paused," not "failed" or "stuck," which is why no error surfaces despite the apparent stall.

### Common Weak Answer
"The Rollout controller must be malfunctioning, restart it."

### Why the Weak Answer Fails
Restarting the controller does nothing to address a deliberately-configured manual pause step — the rollout would resume exactly where it left off (still awaiting manual promotion), since this is documented, intentional behavior, not a controller malfunction.

### Follow-Up Questions
1. How would you decide which stages of a canary rollout genuinely warrant manual approval versus full automation?
2. What alerting would you build to catch a rollout stuck at a manual gate longer than expected?
3. How would this scenario differ if the pause step had a `duration` specified instead?

### Key Interview Signals
Correctly distinguishes a duration-based automatic pause from an indefinite manual-approval gate, diagnosing the stall as intentional, documented behavior rather than a controller malfunction.

### Hands-On Connection
[Lab 11 — Progressive Delivery](../labs/lab-11-progressive-delivery/).

---

## Question 89: The AnalysisTemplate that measured the wrong thing

### Scenario
A canary rollout's automated analysis queries a Prometheus metric for error rate, but the query aggregates error rate across the *entire* service (including the stable, non-canary version's traffic), not just the canary's own traffic specifically. A genuinely broken canary version passes analysis anyway, since its errors are diluted by the much larger volume of healthy stable-version traffic.

### Interview Question
Diagnose this measurement flaw and fix the AnalysisTemplate.

### Strong Senior-Level Answer
**Initial assessment:** an AnalysisTemplate's query must be scoped specifically to the canary's own traffic (typically via a label distinguishing canary pods from stable pods) to actually measure what it's meant to measure — an unscoped, service-wide query dilutes a genuinely bad canary's error signal with the much larger volume of healthy stable traffic, exactly producing this false-pass scenario.

**Technical reasoning:** Argo Rollouts automatically labels canary and stable ReplicaSets' pods distinctly (e.g., via `rollouts-pod-template-hash`) — an AnalysisTemplate's PromQL query needs to explicitly filter on this label to isolate canary-specific metrics; without that filter, the query aggregates across both versions, and the canary's genuine problem gets mathematically washed out by the stable version's much larger, healthy traffic volume, especially early in a canary rollout when the canary is only receiving a small percentage of total traffic.

**Investigation process:** review the AnalysisTemplate's actual PromQL query and confirm it lacks a label selector isolating canary-specific pods/traffic — this settles that the measurement itself, not the canary's actual health, was the problem.

**Recommended solution:** rewrite the AnalysisTemplate's query to explicitly filter on the canary-specific label, ensuring the measured error rate genuinely reflects only the canary version's own traffic, not a diluted, service-wide aggregate.

**Risk controls:** validate the corrected query against a deliberately-broken test canary in a non-production environment, confirming it now correctly fails analysis (rather than passing due to dilution) before trusting it for production rollouts going forward.

**Validation steps:** after the fix, re-run a canary rollout with a deliberately-injected error condition specifically in the canary version and confirm the AnalysisTemplate correctly detects and fails it, rather than passing due to stable-traffic dilution.

**Rollback or recovery strategy:** for the specific incident where a broken canary was already promoted due to this measurement flaw, roll back to the previous stable version (`kubectl argo rollouts undo`) while the AnalysisTemplate fix is validated.

**Long-term prevention:** treat every AnalysisTemplate's query as requiring explicit validation that it's genuinely canary-scoped (not service-wide) before relying on it for automated promotion decisions — this exact "measurement dilution" flaw is a subtle, easy-to-miss mistake worth explicitly checking for in any progressive-delivery configuration review.

### Step-by-Step Implementation
```yaml
# Before - unscoped, diluted by stable traffic
metrics:
  - name: error-rate
    provider:
      prometheus:
        query: |
          sum(rate(http_requests_total{service="checkout",status=~"5.."}[5m]))
          / sum(rate(http_requests_total{service="checkout"}[5m]))

# After - explicitly scoped to canary traffic only
metrics:
  - name: error-rate
    provider:
      prometheus:
        query: |
          sum(rate(http_requests_total{service="checkout",status=~"5..",rollouts_pod_template_hash="{{args.canary-hash}}"}[5m]))
          / sum(rate(http_requests_total{service="checkout",rollouts_pod_template_hash="{{args.canary-hash}}"}[5m]))
```

### Under-the-Hood Explanation
Argo Rollouts passes the canary ReplicaSet's specific `pod-template-hash` label value as an argument accessible to the AnalysisTemplate, allowing the query to filter precisely to canary-originated traffic — without using this argument in the query's label selector, PromQL has no way to distinguish which portion of the aggregated metric came from the canary versus the stable version, since both are simply contributing to the same overall `service="checkout"` time series.

### Common Weak Answer
"The analysis passed, so the canary must genuinely be healthy — the rollback afterward must be due to something else."

### Why the Weak Answer Fails
This trusts the analysis result without examining whether the underlying query actually measured the right thing — a passing analysis result is only as trustworthy as the query's own correctness, and this scenario is exactly a case where the analysis technically "passed" while measuring something other than what it needed to for a meaningful signal.

### Follow-Up Questions
1. How would you design a standard AnalysisTemplate library ensuring every new canary rollout starts with correctly-scoped queries by default?
2. What other dilution-prone metrics (beyond error rate) might have this same measurement flaw if not carefully scoped?
3. How would you validate an AnalysisTemplate's correctness before trusting it for a genuinely important production rollout?

### Key Interview Signals
Identifies the specific measurement-dilution flaw (unscoped query aggregating across canary and stable traffic) rather than assuming the canary was genuinely healthy, and fixes the query's actual scoping.

### Hands-On Connection
[Lab 11 — Progressive Delivery](../labs/lab-11-progressive-delivery/).

---

## Question 90: The secret reference that pointed nowhere

### Scenario
A GitOps-managed application manifest references an External Secrets Operator `ExternalSecret` pointing at an AWS Secrets Manager secret. During a deployment to a newly-created environment, the pod fails to start — the referenced secret doesn't exist in that environment's AWS account/region yet.

### Interview Question
Diagnose this environment-promotion gap and design the correct process.

### Strong Senior-Level Answer
**Initial assessment:** per [`docs/cicd-gitops.md`](../docs/cicd-gitops.md) §4, External Secrets Operator's approach (Git holds only a *reference* to the secret's source, not the value itself) correctly avoids storing sensitive values in Git, but it introduces a real dependency: the referenced secret must actually exist in the target environment's AWS account/region *before* the GitOps-managed manifest referencing it is deployed there — a dependency easy to overlook when promoting a manifest to a genuinely new environment for the first time.

**Technical reasoning:** the manifest/Git repository's promotion (merging an overlay into a new environment) is a purely declarative, Kubernetes-manifest-level operation — it has no awareness of, and doesn't automatically provision, the actual AWS-side secret the `ExternalSecret` object references; that's an entirely separate, AWS-side provisioning step that must happen independently, typically via the same Terraform module that provisions the rest of the new environment's infrastructure.

**Investigation process:** confirm via the External Secrets Operator's own status/events on the `ExternalSecret` object the specific error (secret not found at the referenced ARN/path) — settling that this is a missing-AWS-resource issue, not a Kubernetes-manifest or GitOps-controller malfunction.

**Recommended solution:** create the missing secret in the new environment's AWS Secrets Manager (via the same Terraform module/process that provisions other environment-specific infrastructure, ensuring it's consistently and reproducibly created for every new environment going forward, not a manual one-off step), then confirm the `ExternalSecret` successfully syncs and the pod starts.

**Risk controls:** treat "provision every referenced secret in the new environment's AWS account" as an explicit, checked step in any new-environment bootstrap checklist — never assume a GitOps-managed manifest promotion alone is sufficient for an environment with real, environment-specific AWS-side dependencies.

**Validation steps:** after creating the secret, confirm the `ExternalSecret` object's sync status shows success and the pod starts correctly; more broadly, confirm every other secret reference in this environment's manifests has a correspondingly real AWS-side secret.

**Rollback or recovery strategy:** not applicable — this is a missing-dependency fix, not a change requiring rollback.

**Long-term prevention:** incorporate secret provisioning into the same Terraform-based environment-bootstrap process that creates the rest of a new environment's infrastructure (per the companion Terraform repository's environment-provisioning modules), so a new environment's AWS-side secrets are created automatically and consistently as part of environment creation, never a manually-remembered, easy-to-forget separate step.

### Step-by-Step Implementation
```hcl
# Terraform - secret provisioning as part of new-environment bootstrap, not a manual afterthought
resource "aws_secretsmanager_secret" "db_credential" {
  name = "production/db-credential"   # environment-specific, created alongside other new-env infra
}
```

### Under-the-Hood Explanation
`ExternalSecret` objects are purely declarative pointers — the External Secrets Operator's controller attempts to resolve the referenced AWS Secrets Manager path at reconciliation time, and if nothing exists at that path in the target account/region, the sync simply fails with a clear "not found" status, exactly reflecting that the actual secret provisioning is an entirely separate, AWS-side action that the Kubernetes-manifest-level GitOps promotion process has no mechanism to trigger automatically.

### Common Weak Answer
"The GitOps deployment must be broken since it worked fine in the other environments."

### Why the Weak Answer Fails
The GitOps deployment mechanism itself is working correctly — it's faithfully attempting to resolve a reference that genuinely doesn't exist yet in this specific, newly-created environment; the actual gap is in the new-environment bootstrap process not having provisioned this AWS-side dependency yet, not a defect in the GitOps promotion itself.

### Follow-Up Questions
1. How would you build a pre-flight check confirming every referenced secret exists in a target environment before attempting deployment there?
2. What's the coordination process between the team provisioning new environments' AWS infrastructure and the team managing GitOps-based application manifests?
3. How would you extend this same "does every referenced external dependency actually exist in the target environment" check to other resource types beyond secrets?

### Key Interview Signals
Correctly identifies the missing AWS-side dependency as an environment-bootstrap gap, not a GitOps-mechanism failure, and integrates the fix into the same infrastructure-provisioning process that creates the rest of a new environment.

### Hands-On Connection
[Lab 10 — GitOps with ArgoCD](../labs/lab-10-gitops-argocd/) and [Lab 5 — Multi-Environment](../labs/lab-05-karpenter-autoscaling/) (environment-specific configuration patterns).

---

## Question 91: The overlay that quietly diverged from base

### Scenario
A Kustomize-based repository structure (`base/` + `overlays/{dev,staging,production}/`) has, over eighteen months, accumulated so many environment-specific patches in the `production` overlay that it barely resembles `base` anymore, effectively becoming its own separate configuration rather than a genuine variation.

### Interview Question
Diagnose how this happened and design a remediation approach.

### Strong Senior-Level Answer
**Initial assessment:** per [`docs/cicd-gitops.md`](../docs/cicd-gitops.md) §5, the entire value of the base-plus-overlay pattern depends on the base capturing genuinely shared configuration and overlays capturing genuinely environment-specific *variation* — if production's overlay has accumulated so many patches that it's diverged into effectively its own configuration, the pattern's benefit (shared base, consistent core configuration verified once) has eroded, likely because each individual patch seemed reasonable in isolation without anyone stepping back to assess the cumulative drift.

**Technical reasoning:** Kustomize overlays have no inherent limit or warning mechanism for "how much patching is too much" — each additional patch is applied without any structural feedback about the overlay's growing divergence from base, meaning this kind of gradual, patch-by-patch drift is entirely possible to accumulate unnoticed over a long enough period, exactly as described here.

**Investigation process:** diff `base/` against the fully-rendered `production` overlay output (`kustomize build overlays/production`) and categorize each divergence — which represent genuinely necessary, environment-specific variation (acceptable) versus which represent configuration that should actually be common across environments but was patched into production alone for some historical, possibly-outdated reason (a candidate for moving back into `base`).

**Recommended solution:** for divergences that should genuinely be shared, refactor them back into `base` (updating other environments' overlays if needed to explicitly opt out, rather than production silently being the only one with the "correct" configuration); for genuinely necessary production-specific variation, keep it in the overlay, but as clean, well-organized patches rather than an accumulated pile — this is a deliberate refactoring exercise, not a one-off cleanup.

**Risk controls:** treat this refactoring itself with staged, careful validation (since a large refactor of production's configuration structure carries real risk of an unintended behavior change) — validate the fully-rendered output before and after the refactor is functionally equivalent (aside from deliberate, intended changes) via a diff of the rendered manifests, not just a review of the source structure.

**Validation steps:** after refactoring, confirm `kustomize build overlays/production`'s rendered output matches expectations (deployed successfully in a non-production validation first if at all possible), and confirm the base/overlay structure is meaningfully cleaner and more maintainable going forward.

**Rollback or recovery strategy:** if the refactor introduces an unexpected regression, revert to the previous (messy but known-working) overlay structure while the refactor is corrected and re-validated.

**Long-term prevention:** establish a periodic (e.g., quarterly) review specifically checking overlay divergence from base across all environments, catching this kind of gradual, patch-by-patch drift before it accumulates to the scale seen here — treating overlay hygiene as an ongoing maintenance concern, not a one-time initial design that's assumed to stay clean indefinitely.

### Step-by-Step Implementation
```bash
# Assess the actual scope of divergence
diff <(kustomize build base) <(kustomize build overlays/production)

# After categorizing divergences, refactor genuinely-shared config back into base,
# keeping only genuinely environment-specific patches in the production overlay
```

### Under-the-Hood Explanation
Kustomize's patching model applies overlay-specific patches on top of the base's rendered output at build time, with no structural awareness of or limit on how extensively an overlay patches the base — this flexibility is exactly what enables the gradual, unnoticed accumulation described here, since there's no built-in signal (unlike, say, a linter warning) indicating "this overlay has grown unusually large relative to its base."

### Common Weak Answer
"This is just how Kustomize overlays naturally evolve, it's not really a problem."

### Why the Weak Answer Fails
While some divergence is expected and healthy, unchecked, unlimited accumulation defeats the entire purpose of the base/overlay pattern (a shared, consistently-verified core configuration) — treating this as an inevitable, unaddressable side effect rather than a maintainability problem worth periodically reviewing and refactoring misses a real, actionable opportunity to keep the configuration structure genuinely useful.

### Follow-Up Questions
1. How would you design a periodic, automated check flagging when an overlay's divergence from base exceeds some reasonable threshold?
2. What's the risk-management approach for a large refactor of production's configuration structure specifically?
3. How would you decide, for a specific divergent patch, whether it represents genuinely necessary environment-specific variation versus configuration that drifted into the wrong place?

### Key Interview Signals
Recognizes gradual overlay divergence as a real, accumulating maintainability problem (not just an inevitable characteristic of the pattern), and designs a careful, validated refactoring approach along with periodic review to prevent recurrence.

### Hands-On Connection
[Lab 10 — GitOps with ArgoCD](../labs/lab-10-gitops-argocd/).

---

## Question 92: The Rollout's own state that Git didn't fully describe

### Scenario
A team asks: "if our GitOps repo fully describes desired state, why does `kubectl argo rollouts get rollout my-app` show information (current traffic split, analysis run history) that isn't in our Git repo at all?"

### Interview Question
Explain this apparent contradiction and what it means for how the team should think about GitOps's completeness.

### Strong Senior-Level Answer
**Initial assessment:** per [`docs/cicd-gitops.md`](../docs/cicd-gitops.md) §7, this isn't actually a contradiction — Git declares the *target* desired state and the *rollout strategy* (how to get there), while the Rollout controller's own live status tracks *where the rollout currently is* in executing that strategy at this moment — the *process* of getting from old to new state has its own, necessarily-live, non-Git-describable state, distinct from the Git-declared endpoint and strategy.

**Technical reasoning:** Git describes "eventually reach 100% traffic on the new version, via this specific canary strategy with these specific analysis steps" — it cannot describe "we are currently at 50% traffic, having passed the first two analysis steps 12 minutes ago," because that's runtime, point-in-time progress information that only exists once the rollout is actually executing, tracked by the Rollout controller's own status subresource, not something meaningfully expressible as static, declarative Git content.

**Investigation process:** not applicable as an incident investigation — this is a conceptual clarification question, best addressed by walking through exactly what Git contains (the `Rollout` object's `spec`) versus what the live cluster additionally tracks (the `Rollout` object's `status`, populated and updated continuously by the controller).

**Recommended solution:** help the team build the correct mental model: Git-declared state answers "what should eventually be true and how should we get there," while live cluster state (including a Rollout's `status`) answers "what's actually true and what's the current progress right now" — both are necessary, and neither is "more correct" than the other; they answer different, complementary questions, and this distinction matters most during an active rollout when someone needs to know current traffic split specifically (a live-status question, not something to look for in Git).

**Risk controls:** ensure the team knows to check live status (`kubectl argo rollouts get rollout`, or the ArgoCD/Argo Rollouts dashboard) rather than Git during an active incident involving an in-progress rollout — looking only at Git during such a moment would give an incomplete picture of what's actually happening right now.

**Validation steps:** not applicable — a conceptual clarification, not a technical change.

**Rollback or recovery strategy:** not applicable.

**Long-term prevention:** document this Git-vs-live-status distinction explicitly as part of the team's GitOps onboarding material, specifically calling out progressive-delivery status as a canonical example of information that's legitimately live-only and not expected to be present in Git.

### Step-by-Step Implementation
```bash
# Git describes: the Rollout's spec (target state + strategy)
cat manifests/production/rollout.yaml   # shows: strategy steps, target image version

# Live cluster describes: the Rollout's status (current progress)
kubectl argo rollouts get rollout my-app   # shows: current step, traffic split, analysis run results
```

### Under-the-Hood Explanation
Kubernetes' own object model separates `spec` (desired configuration, what a GitOps controller reconciles Git against) from `status` (actual, live-observed/controller-maintained state) for virtually every resource type — a `Rollout`'s `status` subresource is continuously updated by the Argo Rollouts controller as it executes the `spec`-declared strategy, and this separation is precisely why GitOps's "Git is the source of truth" claim applies specifically to `spec`, not to every field of every resource's full live representation.

### Common Weak Answer
"If GitOps means Git is the source of truth, this discrepancy means our GitOps setup must be broken."

### Why the Weak Answer Fails
This misunderstands what "Git as source of truth" actually claims — it applies to desired configuration (`spec`), not to live, runtime-only status information that has no meaningful "desired" analog to declare in Git in the first place; recognizing this distinction is the correct understanding, not a sign of a broken setup.

### Follow-Up Questions
1. What other Kubernetes resources have this same spec/status distinction worth understanding clearly?
2. How would you design a dashboard giving the team visibility into both Git-declared state and live status together, for a complete picture?
3. How does this distinction relate to the difference between Terraform's plan/state and the actual live infrastructure it manages?

### Key Interview Signals
Correctly resolves the apparent contradiction by distinguishing declarative desired-state/strategy (Git's domain) from live, in-progress runtime status (the controller's own tracked state), rather than concluding the GitOps setup itself must be flawed.

### Hands-On Connection
[Lab 11 — Progressive Delivery](../labs/lab-11-progressive-delivery/).

---

## Question 93: The image tag that meant something different every time

### Scenario
A team's GitOps-managed Deployment references `my-app:latest`. Their ArgoCD instance shows "Synced" and healthy at all times, yet different pods across a rolling update sometimes end up running genuinely different code versions, since `latest` was rebuilt and re-pushed multiple times without any corresponding Git change.

### Interview Question
Diagnose why "Synced" status didn't guarantee consistent, known behavior here.

### Strong Senior-Level Answer
**Initial assessment:** using a mutable tag like `:latest` in a GitOps-managed manifest breaks GitOps's core guarantee — Git is supposed to be the single source of truth for exactly *which* version is deployed, but `:latest` is a mutable pointer that can change its actual referenced content at the registry level without any corresponding Git commit, meaning "Synced" (Git matches the manifest's declared image *tag*) says nothing about whether the actual image *content* behind that tag has changed underneath.

**Technical reasoning:** ArgoCD's sync status compares the *declared manifest* (including the literal string `my-app:latest`) against the *live cluster's manifest* — if both say `my-app:latest`, ArgoCD correctly reports "Synced," entirely unaware that the registry has since re-pushed a different image under that same mutable tag, and that different pods (created at different times, each pulling `:latest` fresh at their own respective pod-creation moment) may have resolved to genuinely different actual image content.

**Investigation process:** confirm via each pod's actual running image digest (`kubectl get pod -o jsonpath='{.status.containerStatuses[].imageID}'`) that different pods indeed reference different underlying image digests despite an identical `:latest` tag in their spec — this confirms the mutable-tag diagnosis definitively.

**Recommended solution:** switch to immutable, specific image tags (a semantic version, or better, a content-addressable digest reference `my-app@sha256:...`) in the GitOps-managed manifest, with the CI pipeline updating this specific tag/digest via a genuine Git commit on every new build — restoring the actual guarantee that "Synced" means every pod is running the exact same, known image content.

**Risk controls:** enable ECR (or your registry's) tag immutability setting, preventing `:latest` (or any tag) from being overwritten after initial push — a registry-level guardrail backing up the manifest-level discipline, since even with the manifest correctly using specific tags, a mutable-tag mistake elsewhere could reintroduce this exact problem.

**Validation steps:** after switching to immutable digest/version references, confirm every pod across a rolling update consistently references the identical image digest, and confirm a new deployment genuinely requires (and is driven by) an actual Git commit changing the referenced digest.

**Rollback or recovery strategy:** for the immediate inconsistency, force a full rolling restart to at least bring every currently-running pod to a consistent (if still not clearly-versioned) state, while the underlying manifest is fixed to use immutable references going forward.

**Long-term prevention:** add a policy-as-code check (Kyverno/Gatekeeper, per [`docs/governance-policy.md`](../docs/governance-policy.md)) rejecting any Deployment manifest using `:latest` (or any known-mutable tag pattern) as a structural guardrail, and enable registry-level tag immutability as defense-in-depth.

### Step-by-Step Implementation
```yaml
# Before - mutable tag, breaks GitOps's version-consistency guarantee
image: my-registry/my-app:latest

# After - immutable digest reference, updated via an actual Git commit per build
image: my-registry/my-app@sha256:a1b2c3d4e5f6...
```
```yaml
# Kyverno policy blocking mutable tags
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: disallow-latest-tag
spec:
  validationFailureAction: Enforce
  rules:
    - name: require-specific-tag
      match: { any: [{ resources: { kinds: [Pod] } }] }
      validate:
        message: "Images must not use the 'latest' tag"
        pattern:
          spec:
            containers:
              - image: "!*:latest"
```

### Under-the-Hood Explanation
Container image tags are, by default, mutable pointers at the registry level — pushing a new image under an already-existing tag simply updates what that tag resolves to, with no versioning or history retained at the tag level itself; ArgoCD's sync comparison operates purely at the Kubernetes-manifest level (does the declared string match the live string), with zero visibility into or comparison of the actual underlying image content a mutable tag might resolve to at any given moment, which is exactly why "Synced" provided no real guarantee about consistent running code here.

### Common Weak Answer
"ArgoCD shows Synced and Healthy, so everything must genuinely be consistent."

### Why the Weak Answer Fails
"Synced" only confirms the declared manifest string matches between Git and the live cluster — it says nothing about whether a mutable reference within that string (like `:latest`) points to consistent actual content over time, which is exactly the gap this incident exposes.

### Follow-Up Questions
1. How would you audit an entire GitOps repository for any other mutable-tag references that might have this same gap?
2. What's the CI pipeline change needed to correctly update a specific digest reference in Git on every build, rather than relying on a mutable tag?
3. How does registry-level tag immutability complement (rather than replace) the manifest-level policy check?

### Key Interview Signals
Correctly distinguishes ArgoCD's manifest-string-level sync comparison from any guarantee about the actual, potentially-mutable underlying image content, and fixes both the manifest practice and adds registry-level and policy-level guardrails.

### Hands-On Connection
[Lab 10 — GitOps with ArgoCD](../labs/lab-10-gitops-argocd/) and [Lab 12 — CI/CD Pipeline](../labs/lab-12-cicd-pipeline/).

---

## Question 94: The sync wave that assumed too much

### Scenario
An ArgoCD Application uses sync waves to sequence resource creation (`CustomResourceDefinition` at wave -1, the operator Deployment at wave 0, instances of the CRD at wave 1). During a fresh cluster bootstrap, the wave-1 CRD instances fail repeatedly, since the wave-0 operator hadn't yet reached a genuinely *ready* state (just been *created*) before wave 1 began.

### Interview Question
Diagnose the sync-wave sequencing gap and fix it.

### Strong Senior-Level Answer
**Initial assessment:** ArgoCD sync waves control *creation order* (wave -1's resources are applied before wave 0's, which are applied before wave 1's) but, by default, only wait for each wave's resources to be *created*, not necessarily fully *healthy/ready* — if wave 1's CRD instances genuinely require the wave-0 operator to be not just created but actually running and ready to reconcile them, an additional explicit health-check mechanism is needed, not just wave ordering alone.

**Technical reasoning:** ArgoCD does support **health checks** per resource (built-in for common types like Deployments, which check replica readiness, not just existence) that sync waves *do* respect before proceeding to the next wave — if the operator Deployment's own health check is somehow not being correctly evaluated (e.g., a custom resource type ArgoCD doesn't have built-in health-check logic for, or a health check that's satisfied by "created" rather than genuinely "ready" for this specific operator), wave progression could proceed prematurely.

**Investigation process:** confirm exactly what ArgoCD considers the wave-0 operator Deployment's health status at the moment wave 1 begins — if ArgoCD's built-in Deployment health check is correctly configured and functioning, it should already wait for replica readiness; if the operator is deployed via a different resource type (e.g., a custom operator lifecycle manager resource) lacking a built-in health check, this is the likely gap.

**Recommended solution:** ensure every wave-gating resource has an appropriate health check ArgoCD can evaluate — for standard resource types this is usually automatic, but for custom resources (a custom operator CRD, for instance) define a custom health check (via ArgoCD's Lua-based custom health check configuration) so wave progression genuinely waits for functional readiness, not just object creation.

**Risk controls:** test the full bootstrap sequence (from an empty cluster) explicitly as part of any change to sync-wave configuration — this exact "creation order was right, but readiness wasn't verified" gap is specifically the kind of issue that might not surface during an incremental update (where the operator is often already running) but does surface during a genuine from-scratch bootstrap, exactly as described here.

**Validation steps:** after adding the custom health check, perform a full fresh-cluster bootstrap test and confirm wave 1's CRD instances now succeed reliably, with wave progression genuinely waiting for the operator's functional readiness.

**Rollback or recovery strategy:** for the immediate failure, manually re-sync/retry wave 1 once the operator has actually become ready — a workable immediate fix while the underlying health-check gap is properly addressed.

**Long-term prevention:** treat "does every wave-gating resource have a correctly-evaluated health check, not just an implicit assumption of readiness" as a standard review item for any sync-wave-based bootstrap sequence, and always test from a genuinely empty/fresh cluster state, not just incremental updates to an already-running one.

### Step-by-Step Implementation
```yaml
# Custom health check for a custom operator resource (ArgoCD ConfigMap configuration)
resource.customizations.health.my-operator.io_MyOperator: |
  hs = {}
  if obj.status ~= nil and obj.status.phase == "Ready" then
    hs.status = "Healthy"
  else
    hs.status = "Progressing"
  end
  return hs
```

### Under-the-Hood Explanation
ArgoCD's sync-wave mechanism gates progression to the next wave on the current wave's resources reaching a healthy state, using either a built-in health check (for well-known types like Deployment, checking `status.readyReplicas` against `spec.replicas`) or a custom, user-defined health check for types ArgoCD doesn't natively understand — without a correctly-defined health check for a given resource type, ArgoCD may fall back to treating "created successfully" (an object exists in the API) as sufficient for wave progression, which is exactly the gap that allows wave 1 to begin before the wave-0 operator is actually functionally ready.

### Common Weak Answer
"Sync waves guarantee order, so this shouldn't be possible — must be an ArgoCD bug."

### Why the Weak Answer Fails
Sync waves guarantee *creation order*, gated by whatever health-check logic ArgoCD has for each resource type — for a custom resource without a correctly-defined custom health check, "created" and "genuinely ready" can be different states ArgoCD doesn't distinguish by default, which is exactly the gap here, not a defect in the sync-wave mechanism itself.

### Follow-Up Questions
1. How would you write and test a custom health check for a novel custom resource type to ensure it correctly reflects genuine readiness?
2. What's the difference between sync waves and sync hooks, and when would you use each?
3. How would you design a standing test specifically validating fresh-cluster bootstrap sequencing, run regularly rather than only when manually remembered?

### Key Interview Signals
Correctly distinguishes "created" from "genuinely healthy/ready" in ArgoCD's wave-gating logic, and fixes the actual gap (a missing custom health check) rather than assuming a platform defect.

### Hands-On Connection
[Lab 10 — GitOps with ArgoCD](../labs/lab-10-gitops-argocd/) and [Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).

---

## Question 95: The pipeline that tested the wrong artifact

### Scenario
A CI pipeline runs `kyverno test` and `helm template` validation against the source chart in the repository, then, in a separate step, builds and pushes the container image. A production incident later reveals the deployed image was built from an *earlier* commit than the one whose manifests were actually validated and merged, due to a race condition between two concurrent pipeline runs.

### Interview Question
Diagnose this artifact-identity mismatch and design the fix.

### Strong Senior-Level Answer
**Initial assessment:** this is the Kubernetes/GitOps-world equivalent of the companion Terraform repository's plan-artifact-integrity guidance — if the pipeline doesn't pin and consistently reference a single, specific commit/artifact identity across every one of its steps (validation, build, and the final manifest update), concurrent runs can interleave in a way that results in validated-and-approved manifests being paired with a *different* image than the one actually validated together with them.

**Technical reasoning:** if two pipeline runs (triggered by two near-simultaneous commits) execute their build/push steps in an order that doesn't match their validation/merge steps' order, a race condition can result in the manifest referencing commit B's intended image tag while the actually-pushed image under that tag came from commit A's build (or vice versa) — exactly the kind of artifact-identity confusion that plan-artifact pinning (in the Terraform context) or immutable-digest-referencing (per Question 93) is designed to prevent.

**Investigation process:** review the CI pipeline's concurrency configuration — does it allow multiple runs for the same branch/target to execute simultaneously, and does each run's build step produce a uniquely-identified artifact (a digest, not just a commit-SHA-based tag that could theoretically be produced by two different concurrent runs in an unexpected order)?

**Recommended solution:** ensure the CI pipeline treats each commit's build as producing a uniquely-addressable artifact (an image digest specifically, not just a tag) and ensure the *same run* that validates a specific commit's manifests is the run that produces and references that exact commit's specific image digest in the Git commit updating the GitOps-managed manifest — closing any possibility of a mismatch between what was validated and what's actually referenced. Additionally, configure the CI pipeline to serialize (not run concurrently) builds targeting the same deployment target, removing the race condition's possibility entirely, per the standard concurrency-control discipline established in the companion repositories' CI/CD guidance.

**Risk controls:** for the specific incident, audit exactly which commit's manifests were actually validated versus which commit's image was actually deployed, to assess what functional difference (if any) existed between them and whether that difference caused any part of the reported production issue.

**Validation steps:** after adding concurrency serialization and digest-based artifact identity, deliberately trigger two near-simultaneous commits in a test scenario and confirm each one's validation and build steps remain correctly paired, with no interleaving possible.

**Rollback or recovery strategy:** for the immediate incident, redeploy the correct, validated commit's actual corresponding image (identified via the digest-based build record, once available) to restore the intended, consistent state.

**Long-term prevention:** treat "does our CI pipeline guarantee artifact-identity consistency across all its steps, even under concurrent execution" as a standing pipeline-design review question, applying the same rigor the companion Terraform repository applies to plan-artifact integrity to this Kubernetes/image-build context specifically.

### Step-by-Step Implementation
```yaml
# CI pipeline concurrency control - serialize runs targeting the same deployment target
concurrency:
  group: deploy-production
  cancel-in-progress: false   # queue, don't interleave

# Build step - output an immutable digest, not just a commit-SHA tag
- name: Build and push
  run: |
    docker build -t my-registry/my-app:${{ github.sha }} .
    docker push my-registry/my-app:${{ github.sha }}
    DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' my-registry/my-app:${{ github.sha }})
    echo "digest=$DIGEST" >> $GITHUB_OUTPUT
# The SAME run's later step commits this specific digest to the GitOps repo
```

### Under-the-Hood Explanation
Without explicit concurrency control, a CI system may run multiple triggered pipelines for the same target truly in parallel — if their individual steps (validate, build, commit-to-GitOps-repo) aren't strictly ordered relative to each other as complete, atomic units, the interleaving of two runs' individual steps can produce exactly this kind of cross-contaminated pairing, where run A's validated manifest ends up referencing run B's built image (or an even more confusing partial mix), a race condition entirely preventable by either serializing concurrent runs for the same target or ensuring artifact identity (digest) is tracked and passed atomically within a single run's own step sequence.

### Common Weak Answer
"Just add a delay between the validation step and the build step to avoid the race."

### Why the Weak Answer Fails
An arbitrary delay doesn't eliminate a race condition between two independently-triggered, concurrently-running pipeline executions — it might reduce the *likelihood* of hitting the exact timing window, but doesn't structurally prevent it; the actual fix (concurrency serialization, digest-based artifact identity) removes the race condition's possibility entirely rather than making it merely less probable.

### Follow-Up Questions
1. How would you audit historical deployments to determine whether this exact race condition affected any other, undiscovered past incidents?
2. What's the trade-off of serializing (versus allowing concurrent) CI runs for the same deployment target, in terms of pipeline throughput?
3. How does this scenario connect to the companion Terraform repository's plan-artifact-integrity guidance conceptually?

### Key Interview Signals
Diagnoses a genuine race condition in concurrent pipeline execution as the root cause, and fixes it structurally (serialization plus digest-based artifact identity) rather than a timing-based workaround that only reduces likelihood without eliminating the underlying race.

### Hands-On Connection
[Lab 12 — CI/CD Pipeline](../labs/lab-12-cicd-pipeline/).

---

## Question 96: The multi-cluster app-of-apps that only remembered one cluster

### Scenario
A platform team manages 20 clusters (per Category 8's scenarios) via a single ArgoCD instance using the "App of Apps" pattern with `ApplicationSet` generating per-cluster Applications. A new, 21st cluster is registered, but its Applications never get created — no error, just silence.

### Interview Question
Diagnose why the ApplicationSet didn't generate Applications for the new cluster.

### Strong Senior-Level Answer
**Initial assessment:** `ApplicationSet`'s cluster generator produces Applications based on clusters registered with ArgoCD (via `argocd cluster add` or an equivalent secret-based registration) — if the new cluster was provisioned (e.g., via Terraform) but never actually *registered* with this ArgoCD instance specifically, the `ApplicationSet` generator has no awareness of its existence at all, and correctly generates nothing for it, silently, since from its perspective there's simply one fewer cluster in its input set than the platform team assumes exists.

**Technical reasoning:** cluster registration with ArgoCD is a distinct, separate step from the cluster's own provisioning (Terraform creating the EKS cluster itself) — it requires an explicit `argocd cluster add` (or the equivalent secret creation with the correct labels the `ApplicationSet` cluster generator watches for) referencing the new cluster's API endpoint and credentials; skipping this step means the new cluster is fully provisioned infrastructure but entirely invisible to the GitOps platform managing the other 20.

**Investigation process:** confirm via `argocd cluster list` whether the new (21st) cluster actually appears as a registered cluster — if it's absent, this settles the diagnosis definitively as a missed registration step, not an `ApplicationSet` malfunction.

**Recommended solution:** register the new cluster (`argocd cluster add <new-cluster-context>`), after which the `ApplicationSet`'s cluster generator should automatically detect it on its next reconciliation and generate the appropriate per-cluster Applications.

**Risk controls:** verify the newly-generated Applications for this cluster actually sync successfully and reach a healthy state — registration alone doesn't guarantee every Application's manifests are correctly compatible with this specific new cluster's state (e.g., if it's missing some prerequisite the other 20 clusters already had).

**Validation steps:** after registration, confirm `kubectl get applications -n argocd | grep <new-cluster-name>` shows the expected set of Applications, matching the pattern already established for the other 20 clusters, and confirm they sync to a healthy state.

**Rollback or recovery strategy:** not applicable — this is a missing-step remediation, not a change requiring rollback.

**Long-term prevention:** integrate ArgoCD cluster registration directly into the same automated pipeline/process that provisions a new cluster (per Question 68's automated-baseline-bootstrap pattern) — making cluster registration a structural, non-skippable part of new-cluster provisioning, rather than a manual, separately-remembered step that can silently be missed exactly as happened here.

### Step-by-Step Implementation
```bash
# Register the new cluster with ArgoCD
argocd cluster add new-cluster-context --name cluster-21

# Confirm the ApplicationSet cluster generator picks it up
kubectl get applicationset platform-apps -n argocd -o yaml
kubectl get applications -n argocd | grep cluster-21
```

### Under-the-Hood Explanation
`ApplicationSet`'s cluster generator queries ArgoCD's own registered-cluster list (backed by Kubernetes Secrets labeled with `argocd.argoproj.io/secret-type: cluster` in the ArgoCD namespace) as its input set — a cluster that exists as real, running infrastructure but has no corresponding registration secret simply isn't part of that input set at all, meaning the generator has no way to know it should produce anything for it, correctly generating nothing rather than erroring, since from the generator's perspective, nothing is actually missing from its own view of the world.

### Common Weak Answer
"The ApplicationSet must have a bug not picking up the new cluster automatically."

### Why the Weak Answer Fails
`ApplicationSet`'s cluster generator works exactly as designed, based on its actual input (registered clusters) — the new cluster's absence from that input (due to a missed registration step) is the real cause, not a defect in the generator's own logic, which correctly reflects whatever clusters are actually registered.

### Follow-Up Questions
1. How would you build an automated check confirming every provisioned cluster is also correctly registered with ArgoCD, catching this gap proactively?
2. What's the right way to integrate cluster registration into the same Terraform-driven provisioning pipeline that creates the cluster itself?
3. How would you validate that a newly-registered cluster's generated Applications are genuinely healthy, not just present?

### Key Interview Signals
Correctly identifies missing cluster registration (a distinct, separate step from cluster provisioning) as the root cause, rather than assuming a defect in the `ApplicationSet` mechanism, and integrates the fix into automated provisioning to prevent recurrence.

### Hands-On Connection
[Lab 10 — GitOps with ArgoCD](../labs/lab-10-gitops-argocd/) and [Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).

---

## Question 97: The rollback that wasn't actually a rollback

### Scenario
Following a bad deployment, an engineer runs `git revert` on the offending commit and pushes it, expecting ArgoCD to roll the application back to its previous state. Instead, the application ends up in a state that's neither the old version nor the new one — some resources reverted, others didn't, due to the revert commit's interaction with an intervening, unrelated commit that had also touched some of the same files.

### Interview Question
Diagnose why a Git revert didn't produce a clean rollback, and design a more reliable rollback process.

### Strong Senior-Level Answer
**Initial assessment:** `git revert` is a source-control operation that reverses a specific commit's *diff* — if any intervening commit touched overlapping content, the revert's applied patch may not cleanly restore the exact prior state (potentially requiring manual conflict resolution, or, if force-pushed through without careful review, silently producing a merged, inconsistent result that's neither the old nor the fully-new state), which is exactly the ambiguity this scenario describes.

**Technical reasoning:** GitOps rollback via `git revert` is only clean and reliable when the commit being reverted is the *most recent* one affecting the relevant files, with no intervening changes — the moment other commits have since modified overlapping files, a revert's mechanical diff-reversal can produce a genuinely ambiguous or incorrect result, which Git itself may not even flag as a conflict if the textual merge happens to succeed syntactically while being semantically wrong.

**Investigation process:** review the actual Git history for the affected files between the offending commit and the revert, confirming the intervening, overlapping commit exists — this settles that the revert's ambiguous result was a predictable consequence of this history, not a GitOps-controller malfunction.

**Recommended solution:** for a genuinely clean rollback, the more reliable approach is not reverting a specific historical commit but instead directly setting the manifest to a known-good, explicit prior state (e.g., checking out or copying the exact manifest content from the last-known-good commit and committing *that* as a new, explicit commit) — avoiding the ambiguity of a mechanical diff-reversal against a history that's since diverged.

**Risk controls:** whichever rollback mechanism is used, always verify the *actual resulting rendered manifest* (`kustomize build`/`helm template` against the new commit) matches the intended prior known-good state exactly, rather than trusting that a `git revert` (or any other Git operation) necessarily produced the intended result without verification.

**Validation steps:** after correcting the rollback (via explicit known-good-state restoration), confirm the application's live state now genuinely matches the intended prior configuration, verified resource-by-resource if necessary given the confusion the initial attempt caused.

**Rollback or recovery strategy:** this *is* the rollback-recovery discussion — the corrected approach (explicit known-good-state restoration rather than mechanical revert) is itself the recommended recovery mechanism going forward.

**Long-term prevention:** document and train the team on the limitation of `git revert` for GitOps rollback specifically when intervening commits exist, and consider tooling/process that tags or snapshots known-good manifest states explicitly (making "restore to this exact known-good tagged state" a reliable, unambiguous operation) rather than relying on `git revert`'s general-purpose, diff-based mechanism for what is actually a "restore to an exact prior state" need.

### Step-by-Step Implementation
```bash
# Less reliable when intervening commits touched the same files
git revert <bad-commit-sha>

# More reliable: explicitly restore the exact known-good manifest content as a new commit
git show <last-known-good-sha>:path/to/manifest.yaml > path/to/manifest.yaml
git commit -am "Rollback: restore manifest to known-good state from <last-known-good-sha>"
git push
# Then explicitly verify the rendered output matches expectations before considering it done
```

### Under-the-Hood Explanation
`git revert` computes and applies the *inverse* of a specific commit's diff against the *current* state of the branch — if the current state has already diverged from what existed immediately after the original commit (due to intervening changes to the same content), the inverse diff may not cleanly or correctly restore the originally-intended prior state, since the reversal is purely mechanical/textual, with no semantic understanding of "what the file's content should end up being" beyond undoing one specific historical change in isolation.

### Common Weak Answer
"git revert always safely undoes a commit, so this must be an ArgoCD-specific issue."

### Why the Weak Answer Fails
This overstates what `git revert` actually guarantees — it's a mechanical, diff-based operation whose correctness depends on the absence of conflicting intervening changes, and the ambiguous result here is a predictable consequence of Git's own diff-reversal mechanics interacting with subsequent history, not anything specific to how ArgoCD consumes the resulting manifest.

### Follow-Up Questions
1. How would you design a tagging/snapshotting convention making "restore to an exact known-good state" a reliable, repeatable operation for future incidents?
2. What's the trade-off of this explicit-restoration approach versus `git revert` for genuinely simple cases with no intervening changes?
3. How would you verify a rollback's correctness beyond just "the sync status shows Synced"?

### Key Interview Signals
Understands `git revert`'s actual mechanical limitations (diff-reversal against potentially-diverged history) and designs a more reliable, explicit-restoration rollback approach rather than assuming a GitOps-tooling defect.

### Hands-On Connection
[Lab 10 — GitOps with ArgoCD](../labs/lab-10-gitops-argocd/) and [Lab 14 — Troubleshooting and Recovery](../labs/lab-14-troubleshooting-and-recovery/).

---

## Question 98: The GitOps repo access that outlived its purpose

### Scenario
A departed contractor's personal GitHub account still has write access to the organization's GitOps repository (granted for a project eight months ago, per the same lifecycle-management gap as the companion IRSA Question 30). A security review discovers this simultaneously with discovering that this same repository's branch protection allows direct pushes to `main` without a required PR review for anyone with write access.

### Interview Question
Diagnose the compounding risk here and design the fix.

### Strong Senior-Level Answer
**Initial assessment:** this combines two separate gaps that compound each other's severity — a stale access grant (the same access-lifecycle-management failure as Question 30, here applied to a GitOps repository instead of cluster RBAC) and a branch-protection gap (allowing direct, unreviewed pushes to the branch a GitOps controller reconciles from) — either alone is a real risk, but together they mean a former contractor's still-valid credentials could push an arbitrary, unreviewed change directly to the branch controlling every cluster's live state.

**Technical reasoning:** since ArgoCD/Flux reconciles cluster state directly from this Git branch (per [`docs/cicd-gitops.md`](../docs/cicd-gitops.md) §1), a direct, unreviewed push to `main` is not just a source-control concern — it's a direct path to modifying live production infrastructure across every cluster this repository manages, with no PR review, no CI validation, and no human sign-off required given the current branch-protection configuration.

**Investigation process:** confirm exactly what access the departed contractor's account currently retains (write access to this specific repository, and check whether they retain access to any other sensitive repository as well), and confirm the branch protection rule's exact current configuration (does it genuinely allow direct pushes, or require PR review with some other gap).

**Recommended solution:** immediately revoke the departed contractor's repository access; separately, and just as urgently, enable branch protection requiring PR review (and passing CI checks) before any merge to `main` — closing both the stale-access gap and the missing-review-gate gap, since either one alone leaves a real risk even if the other is fixed.

**Risk controls:** audit the repository's commit history for the entire period since the contractor's departure for any suspicious or unexpected direct pushes to `main` — given both gaps existed simultaneously, this warrants an actual forensic check, not just an assumption that nothing happened.

**Validation steps:** after fixing both gaps, confirm the departed contractor's account can no longer push to the repository at all, and confirm a test direct-push attempt (by an authorized account) to `main` is now correctly blocked, requiring a PR with passing checks instead.

**Rollback or recovery strategy:** if the forensic audit reveals an actual unauthorized/suspicious change was pushed during the exposure window, that specific change needs its own incident response (assess its actual effect on live cluster state, revert if necessary via the explicit known-good-state restoration process from Question 97).

**Long-term prevention:** establish a systematic offboarding process ensuring repository access (not just cluster RBAC/IAM, as in Question 30) is revoked immediately upon a contractor/employee's departure, and treat "require PR review before merge to any GitOps-reconciled branch" as a mandatory, non-negotiable baseline configuration for every such repository — never optional or something that can be silently disabled/forgotten, given how directly it maps to live infrastructure control.

### Step-by-Step Implementation
```bash
# Immediate: revoke stale access
gh api -X DELETE /repos/my-org/gitops-repo/collaborators/departed-contractor

# Immediate: enforce branch protection requiring PR review + passing checks
gh api -X PUT /repos/my-org/gitops-repo/branches/main/protection \
  -f required_pull_request_reviews.required_approving_review_count=1 \
  -f required_status_checks.strict=true \
  -f enforce_admins=true
```

### Under-the-Hood Explanation
A GitOps-reconciled repository's branch-protection configuration is the *only* thing standing between "anyone with write access" and "direct, unreviewed control over every cluster's live state" — without required PR review, write access alone (regardless of who holds it or how stale that grant might be) is functionally equivalent to unrestricted deployment authority, which is exactly why both the access-grant hygiene and the branch-protection configuration are independently necessary, non-substitutable controls for a repository with this much real-world leverage.

### Common Weak Answer
"Just revoke the contractor's access, that's the main issue."

### Why the Weak Answer Fails
This addresses only one of the two compounding gaps — even after revoking this specific stale access, the missing branch-protection requirement means *any* current, legitimate write-access holder could still push an unreviewed, unvalidated change directly to a branch controlling live production infrastructure across every managed cluster; both gaps need independent remediation.

### Follow-Up Questions
1. How would you design an automated, systematic offboarding check ensuring repository access is revoked promptly for every departing contractor/employee, not just this one discovered case?
2. What CI checks should be required (not just PR review) before any merge to a GitOps-reconciled branch, given its direct live-infrastructure impact?
3. How would you conduct the forensic audit of commit history efficiently across a repository with a long history?

### Key Interview Signals
Identifies and addresses both compounding gaps independently (stale access and missing branch protection), recognizing that a GitOps-reconciled repository's write access is functionally equivalent to direct infrastructure control, warranting the same rigor as any other highly-privileged access path in this repository series.

### Hands-On Connection
[Lab 10 — GitOps with ArgoCD](../labs/lab-10-gitops-argocd/) and [Lab 12 — CI/CD Pipeline](../labs/lab-12-cicd-pipeline/).
