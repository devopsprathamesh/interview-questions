# Category 8: CI/CD and Automation

Questions 69–78 of 120. Category weight: 10 questions. Deep-dive reference: [`docs/cicd.md`](../docs/cicd.md).

---

## Question 69: The apply that wasn't quite what was reviewed

### Scenario
Your pipeline reviews a `terraform plan`, posts it as a PR comment, gets human approval, then — instead of applying the saved plan artifact — the apply job re-runs `terraform plan` fresh and immediately applies that fresh plan with `-auto-approve`.

### Interview Question
What's wrong with this design, even if it "usually" produces the same result?

### Strong Senior-Level Answer
**Initial assessment:** this breaks the fundamental guarantee that what a human approved is what actually gets applied — regenerating the plan at apply time means the approved plan and the applied plan are two different objects that merely *usually* agree, not the same object.

**Technical reasoning:** between the reviewed plan and the apply-time fresh plan, state could have changed (another pipeline applied, drift occurred, someone ran a manual `-refresh-only` apply) — in the vast majority of cases nothing changed and the two plans agree, but "usually agrees" is a materially weaker guarantee than "provably identical," and the entire point of a plan-review gate is the provable guarantee.

**Investigation process:** check how often, historically, this pipeline's apply-time fresh plan has actually differed from what was reviewed (if audit logs/artifacts from past runs exist) — even a low historical divergence rate doesn't justify the design, since the failure mode when it does diverge is exactly "something was applied that nobody actually reviewed."

**Recommended solution:** change the apply job to consume the saved plan artifact from the review step (`terraform apply tfplan`, using the exact binary plan file generated and reviewed earlier), never regenerating a plan at apply time — this makes Terraform itself enforce the guarantee via the serial/lineage staleness check (see [Question 10 in category 1](01-terraform-core.md#question-10-the-workflow-gap-between-plan--out-and-a-later-apply)), rather than relying on the pipeline's own logic to keep the two in sync.

**Risk controls:** if the saved plan is stale by the time apply runs (state changed in between), the apply should fail loudly and route back to a fresh review cycle — never silently regenerate and proceed.

**Validation steps:** test this by deliberately applying an unrelated change to the state between plan and apply steps in a non-prod pipeline run, confirming the apply-with-saved-plan-artifact approach correctly fails with a stale-plan error, while the old fresh-plan-plus-auto-approve approach would have silently applied the new, unreviewed diff.

**Rollback or recovery strategy:** not applicable to this fix directly — it's a pipeline correctness change with no infrastructure impact of its own.

**Long-term prevention:** treat "does the apply step consume the exact reviewed plan artifact" as a mandatory pipeline-design review item for every Terraform CI/CD system in the organization, not just this one pipeline.

### Step-by-Step Implementation
```yaml
# Correct: plan job produces and uploads the artifact; apply job downloads and applies it
plan:
  steps:
    - run: terraform plan -out=tfplan
    - uses: actions/upload-artifact@v4
      with: { name: tfplan, path: tfplan }

apply:
  needs: plan
  environment: production   # manual approval gate
  steps:
    - uses: actions/download-artifact@v4
      with: { name: tfplan }
    - run: terraform apply tfplan   # exact reviewed plan, not a fresh one
```

### Under-the-Hood Explanation
`terraform apply <saved-plan-file>` re-reads the current backend state before proceeding and compares its serial/lineage against what's embedded in the plan file, refusing to proceed if they've diverged (see [`terraform-internals.md` §10](../docs/terraform-internals.md#10-state-serial-lineage-and-reconciliation-during-apply)) — this staleness check exists specifically to prevent exactly the class of "applied something different from what was reviewed" gap that a fresh-plan-then-auto-approve pipeline design reintroduces by construction, since it never gives Terraform the opportunity to compare against a fixed, previously-reviewed baseline at all.

### Common Weak Answer
"It's fine, the two plans almost always match anyway."

### Why the Weak Answer Fails
"Almost always" is precisely the wrong bar for a control whose entire purpose is a provable guarantee — the rare case where they diverge is exactly the case this control exists to catch, and a design that only works in the common case provides no real protection in the case that actually matters.

### Follow-Up Questions
1. How would you retrofit this fix into an existing pipeline without disrupting ongoing deployments?
2. What's the operational cost of using saved plan artifacts (artifact storage, retention policy) compared to regenerating plans, and how do you manage that?
3. How does this guarantee change if the apply job runs on a different CI runner/environment than the plan job — what needs to stay consistent?

### Key Interview Signals
Confirms the candidate treats "provably identical" as a materially different and necessary bar from "usually agrees," and can articulate the underlying Terraform mechanism (serial/lineage check) that the correct design relies on.

### Hands-On Connection
[Lab 12 — CI/CD Pipeline](../labs/lab-12-cicd-pipeline/).

---

## Question 70: The plan artifact that got a second opinion

### Scenario
A security review asks: "what stops someone with access to our CI artifact storage from swapping the reviewed plan artifact for a different one before the approved apply job runs?"

### Interview Question
Answer the question — is this a real risk in your pipeline, and how would you close the gap?

### Strong Senior-Level Answer
**Initial assessment:** yes, this is a real risk if artifact storage access isn't tightly scoped — a plan artifact is just a binary file; anyone able to write to the artifact storage location the apply job reads from could substitute a different plan, and unless something validates the artifact's integrity/provenance, the apply job has no way to know.

**Technical reasoning:** the defense has two layers: restricting *who/what* can write to the artifact storage location in the first place (the CI platform's own artifact access controls, scoped so only the specific plan-generating job in the specific pipeline run can write it), and, where available, verifying the artifact's provenance (checksums, or CI-platform-native artifact integrity/attestation features) before the apply job trusts it.

**Investigation process:** check your specific CI platform's artifact storage model — most (GitHub Actions, GitLab CI) scope uploaded artifacts to the specific workflow run that created them by default, meaning a different, unrelated job/run cannot simply overwrite another run's artifact through normal usage; the actual risk is usually narrower than "anyone can swap it" — it's more precisely "does anyone with elevated CI-platform administrative access, or a compromised runner within the same job, have a path to tamper with it."

**Recommended solution:** rely on the CI platform's native artifact scoping (each run's artifacts are isolated to that run by default in modern platforms) as the primary control, and add a checksum verification step as defense-in-depth — the plan job computes and stores a checksum of the plan file (or the CI platform's built-in artifact digest feature, where available) alongside the upload, and the apply job verifies the downloaded artifact's checksum matches before applying, failing loudly on any mismatch.

**Risk controls:** restrict CI-platform administrative access (anyone who could, in principle, manipulate artifact storage directly, bypassing normal job scoping) to the same small, audited set of people who'd have equivalent access to production credentials generally — this is the actual residual risk surface after normal job-level artifact scoping is accounted for.

**Validation steps:** deliberately test tampering in a non-prod pipeline (attempt to substitute a different plan file for the artifact between plan and apply jobs) and confirm the checksum verification step catches it.

**Rollback or recovery strategy:** not applicable — this is a preventive control; if tampering is ever actually detected via the checksum check, treat it as a security incident requiring investigation of how the substitution occurred, not just a pipeline retry.

**Long-term prevention:** document and periodically re-verify the artifact-scoping and checksum-verification controls as part of your standard CI/CD security review, since CI platform features/defaults can change over time.

### Step-by-Step Implementation
```yaml
plan:
  steps:
    - run: terraform plan -out=tfplan
    - run: sha256sum tfplan > tfplan.sha256
    - uses: actions/upload-artifact@v4
      with: { name: tfplan-bundle, path: [tfplan, tfplan.sha256] }

apply:
  needs: plan
  environment: production
  steps:
    - uses: actions/download-artifact@v4
      with: { name: tfplan-bundle }
    - run: sha256sum -c tfplan.sha256   # fails loudly if the artifact was tampered with
    - run: terraform apply tfplan
```

### Under-the-Hood Explanation
Modern CI platforms (GitHub Actions, GitLab CI) scope uploaded artifacts to the specific workflow run/pipeline that created them, storing them in a namespace tied to that run's identity — a different workflow run generally cannot simply overwrite another run's artifact through the normal artifact API, meaning the realistic tampering surface is narrower than "any CI user" and closer to "someone with elevated platform-administrative access or a compromised runner within the exact same job." The checksum-verification step doesn't rely on trusting the platform's scoping model alone — it gives the apply job an independent, cryptographic way to detect any modification to the artifact's bytes between the two jobs, regardless of how the modification occurred.

### Common Weak Answer
"CI platforms are trusted infrastructure, so this isn't really a concern."

### Why the Weak Answer Fails
"Trusted infrastructure" isn't the same as "no residual risk" — CI-platform administrative access, misconfigured permissions, or a compromised runner are all realistic threat vectors worth a concrete, verifiable control (checksum verification) rather than an assumption that the platform's default behavior is sufficient without confirming it.

### Follow-Up Questions
1. How would you extend this integrity check to also verify the plan artifact came from the specific commit/PR that was actually reviewed, not just that its bytes are unmodified since upload?
2. What CI-platform-native artifact attestation features (if any) could replace the manual checksum step, and what would you need to verify about them?
3. How does this risk change for a self-hosted CI runner versus a fully managed CI platform?

### Key Interview Signals
Confirms the candidate takes a security review question seriously with a concrete technical answer (artifact scoping plus checksum verification) rather than dismissing it as covered by platform trust alone.

### Hands-On Connection
[Lab 12 — CI/CD Pipeline](../labs/lab-12-cicd-pipeline/).

---

## Question 71: The hotfix that skipped the line

### Scenario
During an outage, an engineer with direct push access pushes a fix straight to `main`, bypassing the PR-review branch protection rule (which they're permitted to override in an emergency, per your org's existing break-glass policy). The change applies automatically to production per your pipeline's normal main-branch trigger, with no plan review by anyone else.

### Interview Question
Was this handled correctly? What controls would you want here even for a legitimate emergency bypass?

### Strong Senior-Level Answer
**Initial assessment:** an emergency bypass of normal review during an active outage can be entirely legitimate — speed matters during an incident — but "no review by anyone" and "no record that a bypass occurred" are two different things, and only the first is potentially acceptable under time pressure; the second is a gap regardless of the emergency.

**Technical reasoning:** even a bypassed PR-review step should still produce an auditable trail (who bypassed it, when, why) and, ideally, the applied plan should still be visible/reviewable *after the fact*, even if that review couldn't happen before the apply given the urgency.

**Investigation process:** confirm whether your branch-protection bypass mechanism actually logs who used it and why (most platforms log an audit event for a protected-branch bypass by an authorized admin) — if it doesn't produce a retrievable record, that's the first gap to fix, independent of this specific incident.

**Recommended solution:** for any pipeline serving production infrastructure, structure the emergency-bypass path so that even when the *pre*-apply human review is skipped, the actual applied plan is still captured and posted somewhere reviewable (a Slack channel, an audit log, a follow-up PR) for **mandatory retroactive review** — the incident isn't considered closed until someone other than the original engineer has reviewed what was actually applied, even though it already happened.

**Risk controls:** restrict who has genuine bypass authority to a small, defined on-call set, and require every use of the bypass to be logged with a linked incident ticket, exactly analogous to the incident-time out-of-band change tracking from [Question 68 in category 7](07-security.md#question-68-the-debug-rule-nobody-remembered-to-close).

**Validation steps:** confirm the retroactive review actually happened and the change was either accepted-as-is or promptly corrected — a "we'll review it later" step that never actually happens provides no more protection than no review at all.

**Rollback or recovery strategy:** if the retroactive review reveals an issue with the emergency change, treat correcting it as its own properly-reviewed follow-up PR — not another emergency bypass, since the urgency that justified the first bypass has presumably passed.

**Long-term prevention:** make "mandatory retroactive review of any emergency bypass" a standing, tracked step in your incident postmortem template (alongside the out-of-band-change tracking from Question 68), so bypasses remain fast when genuinely needed without becoming a permanent, unreviewed blind spot.

### Step-by-Step Implementation
```yaml
# Pipeline still posts the applied plan for retroactive review even when the pre-apply
# gate was bypassed, tagging it clearly as an emergency/bypassed change
- name: Post retroactive review notice
  if: steps.check_bypass.outputs.was_bypassed == 'true'
  run: |
    echo "EMERGENCY BYPASS APPLIED - retroactive review required" 
    # post plan.json + incident ticket link to #platform-reviews channel
```
```markdown
<!-- Incident postmortem template addition -->
## Emergency changes applied without prior review
- [ ] Was normal PR review bypassed during this incident? If yes, link the applied plan here.
- [ ] Has a second engineer retroactively reviewed the applied change?
- [ ] Incident is not closed until the above is checked.
```

### Under-the-Hood Explanation
Branch protection bypass is typically an explicit, logged administrative action at the Git-hosting-platform level (e.g., a repository admin's push succeeding despite required-review rules, with the platform's audit log recording that a protection rule was overridden and by whom) — this audit trail exists independent of Terraform itself, but its value depends entirely on someone actually consulting it as part of incident closure, which is precisely the process gap the recommended solution addresses.

### Common Weak Answer
"Emergency bypasses shouldn't be allowed at all — everything should always go through full review."

### Why the Weak Answer Fails
This is unrealistic for genuine production outages where minutes matter, and organizations that don't provide any legitimate fast path tend to see engineers work around controls in less visible, less auditable ways instead — the better answer is making the legitimate fast path retain accountability (retroactive review, logging) rather than eliminating it.

### Follow-Up Questions
1. How would you design the retroactive-review step so it doesn't just become a rubber stamp that nobody meaningfully engages with?
2. What's the right scope for who's authorized to use a branch-protection bypass — should it be broader or narrower than your general on-call rotation?
3. How does this change for a bypass affecting a resource with `prevent_destroy` or similar guardrails — should those still be respected even during an emergency bypass?

### Key Interview Signals
Confirms the candidate doesn't reflexively ban emergency bypasses (unrealistic) but designs for accountability (audit trail, mandatory retroactive review) as the actual control that matters when speed is genuinely necessary.

### Hands-On Connection
[Lab 12 — CI/CD Pipeline](../labs/lab-12-cicd-pipeline/).

---

## Question 72: The queue nobody could see

### Scenario
Two PRs targeting the same production state merge within the same minute. Both pipelines start their apply jobs; the second fails with a Terraform state-lock error, which — with no additional pipeline-level messaging — looks to the engineer like a mysterious failure requiring investigation, rather than an expected, benign queuing situation.

### Interview Question
This is technically working correctly (per [Question 11 in category 2](02-state-management.md#question-11-two-pipelines-one-state)) — so what's actually wrong here, and how would you fix the experience?

### Strong Senior-Level Answer
**Initial assessment:** the underlying locking mechanism is functioning exactly as intended (see [`state-management.md` §3](../docs/state-management.md#3-state-locking)) — the actual problem is a UX/pipeline-design gap: a benign, expected queuing situation is presenting as an unexplained failure, causing unnecessary investigation time and eroding trust in the pipeline ("it randomly fails sometimes").

**Technical reasoning:** a CI-level concurrency group (see [`cicd.md` §6](../docs/cicd.md#6-concurrency-controls)) converts this exact scenario from "second job fails with a cryptic lock error" into "second job visibly queues behind the first and runs automatically once it's done" — same underlying safety guarantee, dramatically better operator experience.

**Investigation process:** confirm the pipeline currently has no concurrency group configured for this environment/state (likely true, given the reported symptom) — this is a simple, checkable configuration gap, not a deeper architectural problem.

**Recommended solution:** add a `concurrency: { group: terraform-production, cancel-in-progress: false }` (or the equivalent for your CI platform) to the relevant workflow, so the second pipeline run automatically waits for the first to complete rather than racing it and hitting a raw backend lock error.

**Risk controls:** explicitly set `cancel-in-progress: false` — cancelling an in-flight apply mid-run reintroduces the interrupted-apply problem (see [Question 7 in category 1](01-terraform-core.md#question-7-the-apply-that-died-halfway-through-a-data-migration)), which is strictly worse than the current benign-if-confusing lock error.

**Validation steps:** merge two PRs within the same minute in a non-prod test and confirm the second pipeline run now shows a clear "queued, waiting for terraform-production" status rather than a lock-error failure.

**Rollback or recovery strategy:** not applicable — this is a non-disruptive pipeline configuration addition.

**Long-term prevention:** apply this concurrency-group pattern to every environment's pipeline as a standard, default configuration for any Terraform CI/CD setup in the organization, not just the one that happened to surface the confusing symptom.

### Step-by-Step Implementation
```yaml
name: terraform-production
on:
  push:
    branches: [main]

concurrency:
  group: terraform-production
  cancel-in-progress: false

jobs:
  plan-and-apply:
    # ... existing steps, now automatically serialized per environment
```

### Under-the-Hood Explanation
A CI-platform concurrency group is enforced entirely at the pipeline-orchestration layer, before any Terraform command runs at all — the second workflow run is held in a queued state by the CI platform itself until the first with the same group key completes, meaning it never even attempts to acquire the Terraform backend lock while the first run holds it; the backend lock (DynamoDB/S3 conditional write) remains as a correctness backstop for any path that somehow bypasses the CI-level queue (a manual local apply, for instance), but the queue is what makes the *common* case (two PRs merging close together) a clean, visible experience rather than a race.

### Common Weak Answer
"Tell engineers the lock error is normal and to just re-run the pipeline."

### Why the Weak Answer Fails
This treats a fixable UX problem as an acceptable permanent inconvenience — every future occurrence still requires an engineer to recognize "oh, this is just the normal lock-contention thing" and manually retry, when a concurrency group makes the correct behavior (wait, then proceed automatically) the default, requiring no manual intervention or tribal knowledge at all.

### Follow-Up Questions
1. How would you handle a case where the queue grows long (several merges in quick succession) — is FIFO queuing always the right behavior?
2. What's the difference in concurrency-group design needs between a single production state and a matrix pipeline deploying to many accounts/regions?
3. How would you monitor/alert if the queue itself becomes a bottleneck (e.g., applies consistently taking long enough that a backlog builds up)?

### Key Interview Signals
Confirms the candidate distinguishes "the underlying mechanism is correct" from "the operator experience is bad," and fixes the actual UX/pipeline-design gap rather than just telling people to tolerate confusing failures.

### Hands-On Connection
[Lab 3 — Concurrent Execution and Locking](../labs/lab-03-state-locking/) and [Lab 12 — CI/CD Pipeline](../labs/lab-12-cicd-pipeline/).

---

## Question 73: Too many people who can say yes

### Scenario
A review of your production environment's approval gate finds that thirty-two people across the engineering organization are currently listed as valid approvers — a list that's grown organically over two years as people changed teams, with nobody ever removed.

### Interview Question
Is this a problem, and how would you fix it without creating an approval bottleneck?

### Strong Senior-Level Answer
**Initial assessment:** yes — a 32-person approver list for production is effectively no meaningful gate at all; the point of a manual-approval requirement is that the approver has current context and accountability for the specific change, and a list this large almost certainly includes people who no longer have either.

**Technical reasoning:** the fix isn't simply shrinking the list arbitrarily — it's aligning the approver list with who actually has current operational ownership and context for this specific production environment, which is a much smaller, actively-maintained set than "everyone who was ever added."

**Investigation process:** cross-reference the current 32-person list against the actual current team roster(s) responsible for this environment, and check approval history — how many of the 32 have actually approved anything in the last six months? A long tail of people who've never once approved a change is strong evidence the list has drifted from actual ownership.

**Recommended solution:** shrink the approver list to the actual current on-call/platform-ownership rotation for this environment (likely single-digit to low-teens, not 32), and — critically — tie list membership to an automated, periodic process (e.g., synced from the on-call rotation tool or team-membership system) rather than a manually-maintained list that will drift again over the next two years exactly as it did this time.

**Risk controls:** ensure the shrunk list still has adequate coverage across time zones/on-call shifts to avoid creating an approval bottleneck (the concern the question explicitly raises) — this is a real trade-off against the security benefit of a smaller list, and the right answer balances both, not just "smaller is always better."

**Validation steps:** after the change, monitor approval-wait-time metrics for a few weeks to confirm the smaller list doesn't introduce meaningful delay compared to before, and confirm the automated-sync mechanism (if implemented) correctly adds new team members and removes departed ones without manual intervention.

**Rollback or recovery strategy:** if the smaller list does create a bottleneck, expand it deliberately (adding specific, justified people) rather than reverting to an unmanaged, organically-grown list — the goal is a *maintained* right-sized list, not necessarily the smallest possible one.

**Long-term prevention:** the automated-sync mechanism (from team roster/on-call tool) is the actual long-term fix — a manually-maintained approver list will always drift over a long enough time horizon; automation is what prevents this exact audit finding from recurring in another two years.

### Step-by-Step Implementation
```yaml
# GitHub Environment protection rules — required reviewers synced from a team, not an ad hoc list
# (conceptual; actual sync mechanism depends on platform/IdP integration)
environments:
  production:
    reviewers:
      teams: ["platform-oncall"]   # membership managed via the team/IdP, not a hardcoded list
```
```bash
# Periodic audit script: flag approvers who haven't approved anything in 6 months
gh api repos/my-org/platform-infra/deployments --paginate | \
  jq '[.[] | select(.environment == "production")] | group_by(.creator.login) | map({user: .[0].creator.login, count: length})'
```

### Under-the-Hood Explanation
Most CI platforms' environment-protection "required reviewers" configuration supports referencing a team (backed by your identity provider or the platform's own team feature) rather than only a hardcoded list of individual usernames — pointing the configuration at a team means the effective approver list is always exactly the team's current membership, with additions/removals handled by whatever process already manages team membership (which is presumably already kept reasonably current for other reasons), rather than requiring separate, manual upkeep of the approval-gate list specifically.

### Common Weak Answer
"Just remove people who don't seem active anymore."

### Why the Weak Answer Fails
A one-time manual pruning fixes today's drift but does nothing to prevent the exact same organic growth from recurring over the next two years — the actual fix needs to be structural (tie the list to a maintained source of truth like team membership or an on-call rotation), not another one-time manual cleanup that will need repeating indefinitely.

### Follow-Up Questions
1. How would you handle a genuinely cross-functional change needing approval from people outside the core platform on-call rotation (e.g., a security-relevant change also needing security-team sign-off)?
2. What metrics would you track to know if the approver list has become too small and is now a bottleneck?
3. How would you audit for this same "list grew organically and was never pruned" pattern across other approval gates in your organization (not just this one production environment)?

### Key Interview Signals
Confirms the candidate fixes the structural cause (unmaintained list) rather than just performing a one-time cleanup, and weighs the security/bottleneck trade-off explicitly rather than treating "smaller list" as an unconditional good.

### Hands-On Connection
[Lab 12 — CI/CD Pipeline](../labs/lab-12-cicd-pipeline/).

---

## Question 74: The drift alert everyone learned to ignore

### Scenario
Your scheduled drift-detection pipeline runs every hour against every environment and posts an alert to a shared Slack channel any time `terraform plan -detailed-exitcode` returns exit code 2. After several months, the channel has hundreds of unread alerts, and a genuine, actionable drift incident was missed for two days because it was buried among routine noise.

### Interview Question
Diagnose why this alerting system failed and redesign it.

### Strong Senior-Level Answer
**Initial assessment:** classic alert fatigue — a detection mechanism that's technically working (drift is genuinely being detected) has become operationally useless because it can't distinguish routine, expected diffs from genuinely actionable ones, and floods a channel that people have learned to stop reading carefully.

**Technical reasoning:** the root cause is almost certainly that a meaningful fraction of "drift" being detected isn't really drift at all in the actionable sense — it's expected, benign noise (a data source producing a slightly different computed value each run, a resource with a known, intentionally-`ignore_changes`-exempted external owner that's still somehow showing in the diff due to an incomplete ignore scope, or a provider normalization quirk) that should never have been alerting in the first place.

**Investigation process:** audit a sample of recent alerts and categorize each as genuine actionable drift versus known-benign noise — this almost always reveals a small number of specific resources/configurations responsible for the majority of alert volume.

**Recommended solution:** fix the specific sources of benign noise at the root (correct `ignore_changes` scoping, address any provider-normalization quirks per [Question 39 in category 4](04-providers.md#question-39-the-tag-that-wouldnt-stay-put)) so the *detection* itself becomes accurate rather than just suppressing its output. Then redesign the alerting tier: route genuinely actionable drift to a paged, on-call-visible channel (not a general Slack channel that accumulates unread noise), and route low-priority/informational drift (if any legitimately remains) to a dashboard or digest, not an interrupt-driven alert channel at all.

**Risk controls:** any change that reduces alert volume must be validated against not accidentally suppressing genuine future drift — the fix is making detection *accurate*, not making it *quieter* by loosening what counts as drift.

**Validation steps:** after the fix, monitor alert volume and, more importantly, alert *precision* (what fraction of alerts over the following month were genuinely actionable) — the goal is a channel where every alert warrants attention, not just a lower raw count.

**Rollback or recovery strategy:** not applicable — this is a detection/alerting design fix; separately, investigate the two-day-missed incident specifically (was it genuinely buried in noise, or was there also a detection gap) to confirm the alert-fatigue theory is the complete explanation.

**Long-term prevention:** treat alert precision as an ongoing metric to monitor, not a one-time fix — as environments evolve, new sources of benign noise can creep in, and periodic review of what's actually driving alert volume should be a standing practice, not a one-time cleanup triggered only after a near-miss.

### Step-by-Step Implementation
```bash
# Audit recent alerts, categorize by root cause
grep -c "exit code 2" drift-detection-logs/*.log | sort -t: -k2 -rn | head -20
# Investigate the top offenders' actual diffs to distinguish genuine drift from noise
```
```yaml
# Redesigned alerting: severity-tiered routing instead of one noisy channel
- name: Classify drift severity
  run: |
    if grep -q "aws_security_group\|aws_iam" plan.json; then
      echo "severity=high" >> $GITHUB_OUTPUT   # paged to on-call
    else
      echo "severity=low" >> $GITHUB_OUTPUT    # daily digest only
    fi
```

### Under-the-Hood Explanation
`terraform plan -detailed-exitcode` returning 2 is a binary, coarse-grained signal ("some diff exists") with no built-in severity classification — Terraform itself has no concept of "this drift is routine and expected" versus "this drift is a security-relevant configuration change"; that classification has to be layered on top by the pipeline (inspecting the plan JSON for which resource types/attributes changed) if the alerting is going to be precise enough to remain trustworthy over time.

### Common Weak Answer
"Just mute the Slack channel notifications so people aren't overwhelmed."

### Why the Weak Answer Fails
Muting notifications doesn't fix the underlying precision problem — it just makes the noise silent instead of loud, which is exactly how the two-day-missed genuine incident happened in the first place; the fix has to improve signal-to-noise, not further suppress the (already-being-ignored) signal.

### Follow-Up Questions
1. How would you design the severity classification to avoid becoming its own source of false negatives (genuinely important drift misclassified as low-severity)?
2. What's your process for periodically re-auditing alert precision as environments evolve?
3. How would you handle a resource type where "drift" is expected and benign 95% of the time but occasionally genuinely significant — is a binary severity tier sufficient?

### Key Interview Signals
Confirms the candidate diagnoses alert fatigue as a precision/signal-to-noise problem (not just a volume problem) and fixes the underlying detection accuracy rather than only adjusting notification settings.

### Hands-On Connection
[Lab 14 — Drift, Failure, and Recovery](../labs/lab-14-drift-and-recovery/).

---

## Question 75: "Can't we just roll it back?"

### Scenario
Following a bad production apply that replaced an RDS instance (destroying and recreating it, losing recent data not yet captured in the latest snapshot), a director asks why the team can't "just roll back Terraform" the way they'd roll back an application deployment.

### Interview Question
How do you explain this clearly to a non-Terraform-specialist stakeholder, and what should have prevented this in the first place?

### Strong Senior-Level Answer
**Initial assessment:** this is as much a communication challenge as a technical one — the director's mental model (application rollback: redeploy the previous container image, traffic shifts back, done) doesn't map onto infrastructure changes involving stateful resource replacement, and explaining the actual limitation clearly is itself a senior-level skill.

**Technical reasoning:** "rolling back Terraform" by reapplying the previous configuration would create a **new** RDS instance matching the old configuration — it would not and cannot restore the specific data that existed in the destroyed instance at the moment of destruction, since that data isn't part of Terraform's configuration at all; Terraform manages infrastructure shape, not data content (see [`cicd.md` §9](../docs/cicd.md#9-rollback-limitations)).

**Investigation process:** determine exactly what data was actually lost — check the most recent automated snapshot's timestamp against the destruction time to quantify the actual gap (this frames the conversation in concrete terms: "we lost approximately X hours of data between the last snapshot and the incident," not an abstract "we can't roll back").

**Recommended solution:** restore the RDS instance from the most recent available snapshot (this is the actual, correct "recovery" action, distinct from a config rollback) and communicate the real data-loss window transparently to the director and any affected stakeholders. Separately and importantly, explain what *should* have prevented the destructive replacement in the first place — likely a missing `prevent_destroy` on the resource, or a plan-review step that should have caught and questioned an unexpected `-/+` on a production database before it was ever applied (see [Question 3 in category 1](01-terraform-core.md#question-3-decommissioning-a-prevent_destroy-protected-resource) and [`terraform-internals.md` §8](../docs/terraform-internals.md#8-resource-replacement-taint-and-force-new-attributes) on investigating unexpected replacements).

**Risk controls:** add `prevent_destroy` to every production stateful resource where accidental destruction would cause genuine data loss, going forward, and mandate that any plan showing a `-/+` (replace) on such a resource requires explicit, named sign-off in the PR before merge, not just a generic approval click.

**Validation steps:** confirm the RDS restoration completed successfully and the application is functioning against the restored instance; separately, confirm `prevent_destroy` is now in place and a test plan attempting to replace the resource is correctly blocked.

**Rollback or recovery strategy:** the RDS snapshot restoration *is* the recovery strategy here — this incident is itself the argument for why "rollback" and "recovery" are different concepts for stateful infrastructure, exactly the distinction the director needs explained.

**Long-term prevention:** run a blameless postmortem covering both the technical gap (missing `prevent_destroy`, missed plan review) and the communication gap (stakeholders' mental model of "rollback" needing calibration) — both are real findings worth addressing.

### Step-by-Step Implementation
```bash
# Quantify the actual data-loss window
aws rds describe-db-snapshots --db-instance-identifier prod-db --query 'DBSnapshots[-1].SnapshotCreateTime'
# Compare against the destruction timestamp from CloudTrail
```
```hcl
# Prevention: add prevent_destroy to every production stateful resource
resource "aws_db_instance" "prod" {
  # ...
  lifecycle {
    prevent_destroy = true
  }
}
```
```markdown
<!-- Stakeholder communication framing -->
"Terraform manages infrastructure configuration, not data. Reapplying the previous
config creates a *new* database matching the old settings — it does not restore
the specific data that existed at the moment of loss. Our actual recovery path is
restoring from the most recent snapshot, which means we lost approximately
[X hours] of data between that snapshot and the incident."
```

### Under-the-Hood Explanation
Terraform's state tracks the *last observed configuration* of a resource, not its data content — for a database, "the resource" from Terraform's perspective is the RDS instance's settings (engine, instance class, storage size, parameter group, etc.), while the actual row data lives entirely within the database engine itself, invisible to and unmanaged by Terraform. Reapplying an old configuration after a destructive replacement creates a new RDS instance with the same *settings*, but AWS provisions a genuinely new, empty (or restored-from-whatever-snapshot-you-specify) database instance — there is no mechanism by which reapplying Terraform configuration could reconstitute data that existed in a since-destroyed instance.

### Common Weak Answer
"We'll just re-run apply with the previous git commit checked out."

### Why the Weak Answer Fails
Presented as a complete answer to the director's question, this doesn't address the actual data-loss problem at all — it would create a new database with the old configuration but none of the lost data, giving a false impression that "rolling back" solves the actual concern (recovering the lost data), when only a snapshot restoration (or equivalent data-layer recovery) can do that.

### Follow-Up Questions
1. How would you design your alerting/plan-review process to make an unexpected production database replacement structurally very hard to apply unnoticed in the first place?
2. What's your snapshot/backup retention policy, and is it aligned with your actual RPO tolerance for this specific database?
3. How would you explain the difference between infrastructure rollback and data recovery to a stakeholder in a way that sets accurate expectations *before* an incident, not just during one?

### Key Interview Signals
Confirms the candidate can translate a technical limitation (Terraform manages infrastructure, not data) into clear, non-jargon stakeholder communication, while also identifying the concrete preventive controls (`prevent_destroy`, mandatory replace-review) that should have stopped the incident.

### Hands-On Connection
[Lab 14 — Drift, Failure, and Recovery](../labs/lab-14-drift-and-recovery/).

---

## Question 76: Moving house without losing the keys

### Scenario
Your organization is migrating its Terraform CI/CD from a self-hosted Jenkins setup (using long-lived AWS IAM user credentials stored in Jenkins credentials) to GitHub Actions. Leadership wants this to also be the moment you adopt OIDC-based authentication, eliminating the long-lived credentials entirely.

### Interview Question
Design this migration so state locking and access guarantees are never weakened during the transition.

### Strong Senior-Level Answer
**Initial assessment:** two changes are happening simultaneously (CI platform migration, and credential model migration) — treat them as related but separately verifiable, since conflating "did the platform migrate correctly" with "did the OIDC trust policy get scoped correctly" makes it harder to isolate an issue if something goes wrong.

**Technical reasoning:** the state backend itself (S3, locking mechanism) doesn't need to change at all for this migration — only *what calls it* changes (GitHub Actions runners instead of Jenkins agents), so the migration can be scoped narrowly to the CI/authentication layer without touching state architecture.

**Investigation process:** inventory every existing Jenkins pipeline's actual AWS permissions usage (via the same CloudTrail-based approach as [Question 63 in category 7](07-security.md#question-63-the-ci-role-that-could-do-almost-anything)) to derive the correct least-privilege policy for the new OIDC-federated role, rather than assuming the old Jenkins credential's permission set (which may itself have been overly broad) is the right target.

**Recommended solution:** set up the GitHub OIDC identity provider and a new IAM role with a correctly-scoped trust policy (repository/environment-conditioned, per [Question 37 in category 4](04-providers.md#question-37-the-assume-role-trust-policy-that-trusted-too-much)) and least-privilege permissions, run the new GitHub Actions pipeline in parallel with the existing Jenkins pipeline for a defined validation period (both targeting the same state, but only one actually applying at any given time — coordinate manually during this window to avoid the exact concurrent-apply scenario from [Question 11 in category 2](02-state-management.md#question-11-two-pipelines-one-state)), confirm plans match between the two systems for several cycles, then cut over fully to GitHub Actions and decommission Jenkins and its long-lived credentials (deactivate and delete the IAM user access keys immediately upon cutover, not "eventually").

**Risk controls:** during the parallel-running validation period, only Jenkins actually applies (GitHub Actions runs plan-only) or vice versa — never both applying against the same state concurrently, which would reintroduce exactly the lock-contention scenario this whole architecture is designed to handle safely but which adds unnecessary risk during a migration window if avoidable.

**Validation steps:** confirm the new OIDC-based pipeline's plans match Jenkins's plans for the same commits across several cycles before cutting over, and confirm state locking/concurrency controls work correctly under the new pipeline via a deliberate test (two runs racing, per [Lab 3](../labs/lab-03-state-locking/)) before relying on it for production.

**Rollback or recovery strategy:** keep the Jenkins pipeline (and its credentials, though ideally passworded/rotated rather than left fully live) available but inactive for a short grace period after cutover, in case an unexpected GitHub Actions-specific issue surfaces — but commit to a firm decommission date to avoid this becoming a permanent "keep both systems around" situation.

**Long-term prevention:** document the OIDC trust-policy scoping and least-privilege derivation process used here as the standard template for any future CI-platform migration, so this doesn't need to be re-derived from scratch next time.

### Step-by-Step Implementation
```bash
# Derive least-privilege policy from Jenkins's actual historical usage
aws accessanalyzer start-policy-generation \
  --policy-generation-details principalArn=arn:aws:iam::...:user/jenkins-terraform \
  --cloud-trail-details '{"trails":[...],"startTime":"...","endTime":"..."}'
```
```json
// New OIDC trust policy, scoped correctly from day one
{
  "Condition": {
    "StringEquals": {
      "token.actions.githubusercontent.com:sub": "repo:my-org/platform-infra:environment:production",
      "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
    }
  }
}
```
```bash
# Parallel validation: GitHub Actions plan-only, Jenkins still applies, for N cycles
# Compare plan.json outputs between the two systems for the same commit
diff <(jq -S . jenkins-plan.json) <(jq -S . gha-plan.json)
```
```bash
# Cutover: Jenkins decommissioned, credentials deleted immediately
aws iam delete-access-key --access-key-id AKIA... --user-name jenkins-terraform
aws iam delete-user --user-name jenkins-terraform
```

### Under-the-Hood Explanation
Because the state backend and its locking mechanism are entirely independent of which CI platform calls Terraform, this migration doesn't touch state architecture at all — it's purely an authentication and orchestration-layer change. The actual risk during migration is a *process* risk (two systems both capable of applying against the same state during the transition window) rather than a *technical* one, which is why the parallel-validation period explicitly designates only one system as the "real" applier at any given time, using the other in plan-only mode until cutover is fully validated.

### Common Weak Answer
"Just switch the pipeline over to GitHub Actions and set up OIDC at the same time."

### Why the Weak Answer Fails
Doing both changes simultaneously with no parallel-validation period makes it much harder to isolate the cause if something goes wrong (is it the new platform, or the new trust policy, or a permissions gap in the least-privilege derivation?) — and skips the concrete verification (plans matching across systems) that actually proves the migration preserved correct behavior before removing the safety net of the old system.

### Follow-Up Questions
1. How would you handle Jenkins-specific pipeline logic (e.g., custom Groovy scripting) that doesn't have a direct GitHub Actions equivalent?
2. What's your plan if the parallel-validation period reveals the new OIDC role's least-privilege policy is missing a permission Jenkins's broader credential had been silently relying on?
3. How would you extend this same migration pattern to GitLab CI instead of GitHub Actions?

### Key Interview Signals
Confirms the candidate separates the platform migration and credential migration as related-but-distinct changes, derives least privilege empirically rather than assuming the old credential's scope was already correct, and designs a genuine parallel-validation period rather than a risky simultaneous cutover.

### Hands-On Connection
[Lab 12 — CI/CD Pipeline](../labs/lab-12-cicd-pipeline/).

---

## Question 77: The scanner that took down every deployment

### Scenario
Your pipeline's mandatory security-scanning step (a third-party SaaS API called from CI) experiences a multi-hour outage. Every Terraform pipeline across the organization is now blocked, including a genuinely urgent production hotfix that has nothing to do with the specific resource types the scanner checks.

### Interview Question
Was this dependency correctly designed? How would you make the pipeline resilient to this without simply removing the security gate?

### Strong Senior-Level Answer
**Initial assessment:** a mandatory external dependency with no fallback behavior for its own outage is itself a design gap — the security-scanning gate's value shouldn't come at the cost of making every single deployment (including unrelated emergency fixes) hostage to a third-party SaaS's uptime.

**Technical reasoning:** the fix isn't removing the gate — it's designing an explicit, deliberate fallback behavior for exactly this failure mode: a scanner-availability outage should trigger a distinct, narrow emergency path (not a silent bypass), rather than either blocking everything indefinitely or silently skipping security scanning without anyone noticing.

**Investigation process:** confirm the scanner outage was genuinely on the vendor's side (not a misconfiguration/network issue on your end that would have a different, faster fix), and check whether any local/offline scanning capability (e.g., running Checkov or Trivy locally in CI, not dependent on an external SaaS API at all) could serve as a fallback for at least the most critical check categories even during a SaaS outage.

**Recommended solution:** add an explicit "security scan unavailable" detection and fallback path: if the primary scanner is unreachable after a reasonable retry/timeout, fall back to a locally-run, CI-native scanner (Checkov/Trivy running as a container in the CI job itself, no external API dependency) covering at least the same critical rule categories, so the gate degrades to "still meaningfully checked, just via a different tool" rather than "completely bypassed" or "completely blocking." For the specific urgent hotfix scenario, this fallback path should be sufficient on its own; a manual override should still exist as a last resort (requiring the same accountability/logging as the emergency-bypass pattern from [Question 71](#question-71-the-hotfix-that-skipped-the-line)), not eliminated, but should be rarely needed once a working fallback exists.

**Risk controls:** whichever fallback path is used, it should still produce a clear artifact/log showing what was and wasn't checked, so a later audit can see exactly which scan ran for any given deployment, including during the outage window.

**Validation steps:** test the fallback path deliberately (simulate the primary scanner being unreachable in a non-prod pipeline run) and confirm the local scanner correctly takes over and still blocks/passes based on its own findings.

**Rollback or recovery strategy:** not applicable directly — this is a pipeline resilience design; separately, once the vendor's outage resolves, consider re-running the primary scanner retroactively against anything that deployed via the fallback path during the outage, to confirm no gap in coverage occurred that the fallback tool's rule set might have missed.

**Long-term prevention:** treat any mandatory external CI dependency (security scanner, policy engine, artifact registry) as needing an explicit, tested fallback/degraded-mode behavior as a standard pipeline-design requirement, not just for this one scanner after this one outage.

### Step-by-Step Implementation
```yaml
security-scan:
  steps:
    - name: Attempt primary SaaS scanner
      id: primary
      continue-on-error: true
      run: ./scripts/call-vendor-scanner.sh
    - name: Fallback to local scanner if primary unavailable
      if: steps.primary.outcome == 'failure'
      run: |
        echo "::warning::Primary scanner unavailable, falling back to local Checkov scan"
        docker run --rm -v $(pwd):/tf bridgecrew/checkov -d /tf --compact
    - name: Record which scan path was used
      run: echo "scan_path=${{ steps.primary.outcome == 'success' && 'primary' || 'fallback' }}" >> scan-audit.log
```

### Under-the-Hood Explanation
This is purely a CI pipeline resilience/design question, not a Terraform mechanism — the relevant engineering principle is that any external dependency your deployment pipeline treats as mandatory becomes, by construction, a single point of failure for every deployment that depends on it, regardless of how unrelated a given change is to what that dependency actually checks; a well-designed pipeline degrades gracefully (a documented, still-meaningful fallback) rather than failing completely open (silent bypass) or completely closed (indefinite block) when a mandatory external dependency has an outage.

### Common Weak Answer
"Just add a manual override to bypass the scanner when it's down."

### Why the Weak Answer Fails
A bare bypass with no fallback scanning at all means every deployment during the outage window ships with zero security scanning coverage, which is a much larger gap than necessary — a local-scanner fallback preserves meaningful coverage even during a third-party outage, and a manual override should be the last resort for cases the fallback itself can't handle, not the primary answer.

### Follow-Up Questions
1. How would you decide which specific rule categories the local fallback scanner needs to cover to be an adequate (if not identical) substitute for the primary SaaS scanner?
2. How would you handle a policy-as-code (OPA/Conftest) gate having the same kind of external dependency, if its rule definitions are fetched from a remote source?
3. What's your process for retroactively re-scanning anything deployed via the fallback path once the primary scanner's outage resolves?

### Key Interview Signals
Confirms the candidate designs graceful degradation for mandatory external CI dependencies rather than a binary "block everything" or "bypass everything" response, and thinks about retroactive verification once the primary system recovers.

### Hands-On Connection
[Lab 10 — Terraform Security Pipeline](../labs/lab-10-security-validation/) and [Lab 12 — CI/CD Pipeline](../labs/lab-12-cicd-pipeline/).

---

## Question 78: The plan from a stranger

### Scenario
Your repository accepts pull requests from external contributors (forks), and your current pipeline runs `terraform plan` (with real cloud credentials) automatically on every PR, including from forks, to give fast feedback.

### Interview Question
Is this safe? Redesign the pipeline if not.

### Strong Senior-Level Answer
**Initial assessment:** running a plan with real cloud credentials automatically against a fork's PR is a genuine risk — a PR from an external/untrusted fork is attacker-controlled code (the `.tf` files themselves, or a malicious module source, or a workflow-file change if your CI configuration itself is checked out from the fork), and `terraform plan` executes provider code and can, depending on configuration, make real API calls beyond pure read-only inspection (e.g., a malicious `local-exec` provisioner, or a data source designed to exfiltrate data via a crafted external API call).

**Technical reasoning:** most CI platforms (GitHub Actions specifically) already provide a safer event type for fork PRs (`pull_request` without write/secret access for fork-originated runs, versus `pull_request_target`, which does have secret access but requires deliberately checking out only trusted, reviewed code before granting it) — the risk arises specifically when a pipeline is misconfigured to grant fork-originated PR runs access to real credentials/secrets without that safeguard.

**Investigation process:** confirm exactly how your current pipeline is configured — is it using `pull_request_target` (or an equivalent that grants secrets to fork-originated code) while checking out and running the fork's own, unreviewed `.tf`/workflow files directly? That combination is the actual vulnerability, not "running plan on PRs" in general.

**Recommended solution:** for fork-originated PRs, run `terraform plan` (and `validate`/`fmt`/static scanning) with **no real cloud credentials at all** — either genuinely read-only, scoped-down credentials with tightly limited blast radius (e.g., only allowed to read specific non-sensitive resources for feedback purposes) or skip the live-cloud plan step entirely for fork PRs, relying on `terraform validate` plus static/policy scanning (which don't need cloud credentials) for fast fork-PR feedback, and requiring a maintainer to explicitly trigger a full credentialed plan (via a manual `/plan` comment-triggered workflow, common in many open-source Terraform repositories) only after reviewing the fork's diff for anything suspicious.

**Risk controls:** never use `pull_request_target` with a fork's checked-out code and real secrets together without an explicit human review step gating that combination — this is the specific, well-known GitHub Actions security anti-pattern this question is testing for.

**Validation steps:** test the redesigned pipeline against both a same-repo PR (should get full credentialed plan automatically, as trusted) and a fork PR (should get validate/lint/static-scan feedback automatically, but require explicit maintainer trigger for a real credentialed plan) to confirm the split behaves as intended.

**Rollback or recovery strategy:** not applicable — this is a pipeline security hardening change; if a prior fork PR is discovered to have already run with real credentials under the old configuration, audit what that plan actually did/queried and whether anything suspicious occurred.

**Long-term prevention:** treat "does this workflow grant real credentials to code checked out from a fork without an explicit trust/review gate" as a standard security review item for every public or externally-contributable repository running Terraform CI.

### Step-by-Step Implementation
```yaml
# Fork PRs: safe, credential-free feedback only
on:
  pull_request:   # NOT pull_request_target — no secrets available to fork-originated runs
jobs:
  validate:
    steps:
      - run: terraform fmt -check
      - run: terraform validate
      - run: checkov -d .   # static scan, no cloud credentials needed
```
```yaml
# Same-repo PRs and maintainer-triggered fork review: full credentialed plan
on:
  issue_comment:
    types: [created]
jobs:
  plan-on-demand:
    if: github.event.issue.pull_request && contains(github.event.comment.body, '/plan') && 
        github.event.comment.author_association == 'MEMBER'   # only maintainers can trigger
    steps:
      - uses: actions/checkout@v4
        with: { ref: refs/pull/${{ github.event.issue.number }}/merge }
      - uses: aws-actions/configure-aws-credentials@v4
        with: { role-to-assume: ${{ vars.PLAN_ROLE_ARN }} }
      - run: terraform plan
```

### Under-the-Hood Explanation
GitHub Actions' `pull_request` event, for PRs originating from forks, runs with a restricted `GITHUB_TOKEN` and, critically, does **not** expose repository secrets to the workflow by default — this is the platform's own built-in safeguard against exactly this risk. `pull_request_target`, by contrast, runs in the context of the *base* repository (with full secret access) regardless of where the PR comes from, specifically so maintainers can build automation that needs credentials; using it while also checking out the *fork's* code (rather than the base branch's trusted workflow/action definitions) is the specific, well-documented anti-pattern that reunites untrusted code with trusted secrets, which is exactly the combination this question's redesign avoids.

### Common Weak Answer
"Just don't run CI on fork PRs at all, to be safe."

### Why the Weak Answer Fails
This overcorrects — it removes the fast feedback loop entirely for external contributors (bad for open-source-style collaboration) when a much more targeted fix (credential-free validation/scanning automatically, full credentialed plan only via explicit maintainer trigger) preserves both safety and a reasonable contributor experience.

### Follow-Up Questions
1. How would you extend the maintainer-triggered `/plan` pattern to also support a full `apply` for a genuinely trusted, reviewed external contribution?
2. What other GitHub Actions-specific risks (beyond `pull_request_target`) would you check for in a public repository's CI configuration?
3. How would this design change for a private repository where all contributors are trusted employees, versus a public repository accepting truly external contributions?

### Key Interview Signals
Confirms the candidate knows the specific `pull_request` vs. `pull_request_target` security distinction (a well-known but frequently-missed GitHub Actions risk) and designs a targeted fix rather than either ignoring the risk or overcorrecting by disabling fork CI entirely.

### Hands-On Connection
[Lab 12 — CI/CD Pipeline](../labs/lab-12-cicd-pipeline/).
