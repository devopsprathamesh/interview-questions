# Category 8: CI/CD and Automation (AWX/Tower)

Questions 69–78 of 120. Category weight: 10 questions. Deep-dive reference: [`docs/cicd.md`](../docs/cicd.md) and [`docs/ansible-architecture.md`](../docs/ansible-architecture.md) Part B.

---

## Question 69: The Job Template that ran with too much power

### Scenario
An AWX Job Template used for routine, low-risk configuration tasks (updating a MOTD banner across the fleet) is configured with a credential that grants full, unrestricted `become` access and broad AWS IAM permissions — "since it's easier to have one credential that works for everything."

### Interview Question
Evaluate this credential design and propose the correct AWX credential architecture.

### Strong Senior-Level Answer
**Initial assessment:** a single, broad credential attached to every Job Template regardless of the actual task's risk/scope is exactly the shared-credential-for-convenience anti-pattern recurring throughout this repository series — a low-risk MOTD-update Job Template has no legitimate need for broad IAM permissions or unrestricted root, and giving it that access anyway means any accident or compromise of this specific, frequently-run, low-scrutiny Job Template carries a blast radius wildly disproportionate to its actual purpose.

**Technical reasoning:** AWX's credential model is specifically designed to support fine-grained, per-Job-Template credential assignment — credentials aren't required to be shared across every template, and AWX's own RBAC additionally controls which users/teams can even *use* a given credential, meaning the "one credential for everything" choice here is a convenience shortcut, not a technical limitation.

**Investigation process:** inventory every existing Job Template and its actual required scope (what specifically each one needs to touch/modify), identifying which currently share this overly broad credential unnecessarily.

**Recommended solution:** create scoped, purpose-specific credentials matched to each Job Template's actual need — the MOTD-update template gets a narrowly-scoped `become` credential (perhaps just permission to write to `/etc/motd` specifically, via a scoped sudoers entry per Question 67's pattern) with no AWS credential attached at all, since it doesn't need one; broader-scope templates retain broader credentials only where genuinely justified.

**Risk controls:** use AWX's credential-assignment RBAC to further restrict which users/teams can launch a Job Template using any particularly sensitive credential, adding a human-authorization layer on top of the technical credential-scoping.

**Validation steps:** confirm the MOTD-update template still functions correctly with its newly narrow credential, and confirm it genuinely lacks the broad IAM/root access it previously (unnecessarily) had.

**Rollback or recovery strategy:** if a template's newly-scoped credential is missing a permission it turns out to legitimately need, add that specific permission rather than reverting to a broad, shared credential.

**Long-term prevention:** establish "does this Job Template's assigned credential match its actual, minimum required scope" as a standard review item for every new or existing template, treating credential-sharing-for-convenience as a red flag requiring justification, not a default.

### Step-by-Step Implementation
```text
AWX credential design:
- motd-update-credential: scoped sudoers permission for /etc/motd only, no AWS credential
- aws-config-mgmt-credential: IRSA-equivalent, scoped to only the specific AWS actions
  genuinely needed for AWS-touching playbooks
Each Job Template assigned ONLY the credential matching its actual scope.
```

### Under-the-Hood Explanation
AWX credentials are first-class, independently-manageable objects, injected into a Job Template's execution environment only for that specific template's runs — there's no technical requirement forcing credential reuse across templates, meaning the "one credential for everything" pattern here is purely an organizational/convenience choice that directly increases blast radius for every low-risk template sharing it, with no corresponding technical benefit.

### Common Weak Answer
"Managing one credential is simpler than managing many scoped ones."

### Why the Weak Answer Fails
This convenience comes at the direct cost of blast-radius proportionality — every low-risk template sharing the broad credential inherits its full risk profile, and AWX's credential model doesn't actually require this trade-off, making the "simplicity" gained largely illusory relative to the risk accepted.

### Follow-Up Questions
1. How would you audit an existing AWX instance for Job Templates using disproportionately broad credentials relative to their actual task?
2. What's the AWX RBAC mechanism for further restricting who can launch a template using a particularly sensitive credential?
3. How does this compare to the companion EKS repository's node-IAM-role and IRSA least-privilege distinction?

### Key Interview Signals
Recognizes credential-sharing-for-convenience as a blast-radius risk disproportionate to a low-risk template's actual needs, and designs scoped, purpose-specific AWX credentials matched to each template's genuine requirement.

### Hands-On Connection
[Lab 12 — CI/CD Pipeline](../labs/lab-12-cicd-pipeline/).

---

## Question 70: The Survey that let anyone target production

### Scenario
An AWX Job Template uses a Survey to let requesters specify the target inventory group as a free-text field. A well-meaning engineer, intending to target `staging`, typos it as `production` (a group that genuinely exists), and the playbook runs against production unintentionally.

### Interview Question
Diagnose this input-validation gap and redesign the Survey.

### Strong Senior-Level Answer
**Initial assessment:** a free-text field for something as consequential as target-environment selection has no structural protection against exactly this kind of typo — the Survey accepted "production" as valid input because it *is* a valid, existing inventory group, with no distinction made between "syntactically valid" and "the requester's actual intended target."

**Technical reasoning:** AWX Surveys support constrained input types (a multiple-choice/dropdown list of specific, pre-approved values) instead of free text — using free text for a field this consequential accepts any syntactically-valid inventory group name as equally likely to be intentional, providing no structural safeguard against a simple typo matching a different, genuinely-existing group.

**Investigation process:** confirm exactly how this Survey field is currently configured (free text versus a constrained choice list) — this settles the diagnosis and directly informs the fix.

**Recommended solution:** change the Survey field to a multiple-choice/dropdown type, explicitly enumerating only the valid, intended target options (e.g., "dev," "staging," "production") — eliminating the possibility of a typo producing an unintended-but-valid value, since the requester can only select from the deliberately-curated list.

**Risk controls:** for the production option specifically, consider requiring additional approval (via AWX's workflow-approval-node feature, if using Workflow Templates) before a production-targeting run proceeds — an extra, deliberate confirmation step for the highest-risk target.

**Validation steps:** confirm the redesigned Survey only accepts the intended, curated set of target values, and confirm a deliberate attempt to submit an out-of-list value is correctly rejected.

**Rollback or recovery strategy:** for the immediate incident, assess and revert whatever change was unintentionally applied to production via the standard rollback path for that specific playbook's actions.

**Long-term prevention:** treat any Survey field controlling a consequential decision (target environment, destructive action toggle) as requiring a constrained-choice input type by default, reserving free text only for genuinely open-ended, low-consequence inputs (like a comment/reason field) — never for anything that could inadvertently match a valid-but-unintended value.

### Step-by-Step Implementation
```json
{
  "name": "target_environment",
  "type": "multiplechoice",
  "choices": ["dev", "staging", "production"],
  "required": true
}
```

### Under-the-Hood Explanation
AWX's Survey mechanism, when configured with a `multiplechoice` type, constrains the actual submitted value to exactly the enumerated choices — the underlying playbook variable is populated only from this fixed set, structurally eliminating the possibility of a typo producing an unintended value, unlike a free-text field which accepts any string the requester happens to type.

### Common Weak Answer
"Just ask requesters to double-check their input carefully before submitting."

### Why the Weak Answer Fails
This is the same "remember to be careful" reliance on individual diligence this repository series consistently flags as insufficient — a constrained-choice input structurally prevents the mistake regardless of how careful or distracted any individual requester happens to be at the moment of submission.

### Follow-Up Questions
1. How would you extend the approval-workflow-node pattern to other high-risk Job Template inputs beyond just target environment?
2. What's the trade-off of adding an approval step for every production-targeting run, in terms of operational velocity?
3. How would you audit existing Job Templates' Surveys for other free-text fields that should be constrained choices?

### Key Interview Signals
Identifies free-text input as a structural gap for a consequential decision and redesigns using AWX's constrained-choice Survey type, additionally considering an approval-workflow safeguard for the highest-risk target.

### Hands-On Connection
[Lab 12 — CI/CD Pipeline](../labs/lab-12-cicd-pipeline/).

---

## Question 71: The scheduled Job Template nobody remembered existed

### Scenario
An AWX Job Template is scheduled to run nightly, applying a security-hardening playbook. Eighteen months later, during an incident investigation, the team discovers this scheduled job had been silently failing every single night for the past four months (due to an inventory-source credential expiring), with no one noticing since no one was actively monitoring its execution history.

### Interview Question
Diagnose this silent-failure gap and design a monitoring/alerting fix.

### Strong Senior-Level Answer
**Initial assessment:** a scheduled automation job with no active failure-monitoring/alerting is exactly the same "silent gap" pattern recurring throughout this repository — AWX correctly recorded every failed run in its own job history, but nobody was watching that history, meaning the failure was fully visible in principle but entirely unnoticed in practice for four months.

**Technical reasoning:** AWX's own job-execution history and notification system (email, Slack, webhook notifications configurable per Job Template or Workflow) is specifically designed to surface exactly this kind of failure — but notifications must be explicitly configured and someone must actually act on them; the mere existence of a job-history log without active alerting provides no protection against silent, unnoticed failure.

**Investigation process:** confirm via AWX's job history exactly when the failures began and correlate with the inventory-source credential's expiration timestamp — this settles both the root cause and the actual duration of the undetected gap.

**Recommended solution:** configure AWX notification templates (Slack/email/webhook) on every scheduled Job Template, specifically triggering on failure, routed to a channel/team that will actually see and act on it — and separately, rotate/renew the expired inventory-source credential, following the same credential-lifecycle discipline established in earlier categories (never letting a credential silently expire unnoticed).

**Risk controls:** for genuinely critical scheduled jobs (like this security-hardening playbook), consider an additional, independent monitoring layer (per the companion EKS repository's "dead man's switch" pattern) — an external check confirming the job actually ran successfully within its expected window, independent of AWX's own notification system, in case AWX's notification delivery itself has an issue.

**Validation steps:** deliberately trigger a test failure and confirm the notification correctly fires and reaches the intended recipients, and confirm the credential renewal resolves the actual nightly hardening job's failures going forward.

**Rollback or recovery strategy:** assess what security-hardening drift accumulated over the four-month undetected gap (since the hardening playbook wasn't actually applying its intended changes) and remediate any resulting compliance gap across the affected fleet.

**Long-term prevention:** treat every scheduled automation job as requiring active, monitored failure notification by default (never a "set it and forget it" schedule with no alerting), and periodically audit scheduled jobs' actual recent success/failure history as a standing operational review practice, catching a silent failure pattern within days, not months.

### Step-by-Step Implementation
```text
AWX Job Template notification configuration:
- Notification Template: Slack (#platform-alerts)
- Trigger: On Failure (and optionally, on Success being unusually delayed/skipped)
- Applied to: every scheduled Job Template, not just this one
```

### Under-the-Hood Explanation
AWX's scheduler executes the Job Template according to its configured schedule regardless of whether the previous run succeeded or failed — without an explicitly-configured notification triggering on failure, a failing scheduled job simply accumulates failed run records in AWX's own history, visible only to someone who proactively checks, which is exactly why this failure persisted undetected for four months.

### Common Weak Answer
"AWX already logs every job run, so we have visibility into this."

### Why the Weak Answer Fails
Logging and active alerting are different things — a log that nobody actively monitors provides no real-time protection against a silent failure, exactly as this four-month gap demonstrates; genuine visibility requires active notification routed to someone who will actually see and act on it.

### Follow-Up Questions
1. How would you design the "dead man's switch" pattern specifically for AWX scheduled jobs, independent of AWX's own notification delivery?
2. What's the appropriate notification channel/escalation path for a failure in a security-critical scheduled job versus a routine one?
3. How would you audit all currently-scheduled AWX jobs for missing failure notifications right now, proactively?

### Key Interview Signals
Recognizes that job-history logging alone doesn't provide genuine failure visibility without active notification, and designs both AWX-native alerting and an independent "dead man's switch" backstop for genuinely critical scheduled automation.

### Hands-On Connection
[Lab 12 — CI/CD Pipeline](../labs/lab-12-cicd-pipeline/).

---

## Question 72: The plan Ansible never had

### Scenario
A new engineer, familiar with Terraform, asks: "before we apply this playbook to production, can we see a 'plan' of exactly what will change, like `terraform plan`, reviewed and approved before the actual apply runs the identical, already-reviewed set of changes?"

### Interview Question
Explain what Ansible actually offers here, and its genuine limitation compared to Terraform's plan/apply model.

### Strong Senior-Level Answer
**Initial assessment:** per [`docs/cicd.md`](../docs/cicd.md) §2, this is a genuine, honestly-acknowledged capability gap — Ansible's `--check --diff` mode provides a *preview* of intended changes, but critically, it is not a *saved artifact* that a subsequent `ansible-playbook` run without `--check` is guaranteed to apply identically; between the preview and the real run, the target hosts' actual state (and any dynamically-resolved values) can change, meaning the real run isn't provably identical to what was reviewed.

**Technical reasoning:** Terraform's plan is a saved, deterministic artifact — applying that exact plan file guarantees the applied changes match precisely what was reviewed, since the plan captures a specific, frozen set of intended actions. Ansible's `--check` mode re-evaluates conditionals/facts/module logic live, without persisting a frozen intended-action set — a second, real run re-derives its actions fresh, and while usually consistent with the preview, there's no structural guarantee of exact identity between preview and apply the way Terraform's plan-file mechanism provides.

**Investigation process:** not applicable — this is a conceptual/capability clarification, not an incident to investigate.

**Recommended solution:** the closest practical mitigation for genuinely high-stakes changes is minimizing the time gap between `--check` review and the real run (ideally reviewing and applying in immediate succession, in the same pipeline execution, against the same pinned commit/image/inventory state) — reducing, though not eliminating, the window in which target-host state could drift between preview and apply; additionally, pinning the exact playbook commit and Execution Environment image version used for both the check and the real run (per [`docs/cicd.md`](../docs/cicd.md) §2's specific mitigation) further tightens this gap.

**Risk controls:** be explicit and honest with the team (and stakeholders, if relevant) about this being a genuine, structural difference from Terraform's guarantees, not something to paper over — false confidence that Ansible's `--check` provides Terraform-plan-equivalent guarantees is itself a risk.

**Validation steps:** for a genuinely high-stakes change, consider running the real `ansible-playbook` execution immediately after the reviewed `--check` run, in the same pipeline invocation, minimizing (not eliminating) the drift window.

**Rollback or recovery strategy:** not applicable to this conceptual question.

**Long-term prevention:** document this specific, honest capability gap for the team (exactly as [`docs/cicd.md`](../docs/cicd.md) §2 does) so expectations are correctly calibrated — Ansible's `--check --diff` is a valuable, real preview tool, but it is not a substitute for Terraform's stronger plan-artifact guarantee, and pretending otherwise risks a false sense of security for high-stakes changes.

### Step-by-Step Implementation
```yaml
# CI pipeline - minimize the check-to-apply gap for high-stakes changes
- name: Preview changes (check mode)
  run: ansible-playbook site.yml --check --diff -i production
  # Manual review/approval gate here

- name: Apply (same pinned commit/EE image, run immediately after approval)
  run: ansible-playbook site.yml -i production
```

### Under-the-Hood Explanation
`--check` mode short-circuits most modules' actual state-changing calls while still evaluating conditionals and templating against the *current* live facts/state of the target hosts — since this evaluation happens fresh each time (not from a saved, frozen artifact), any change to the target environment between the check run and the real run (a fact changing, a file being modified by something else, a race with another process) means the real run's actual behavior isn't structurally guaranteed to match what was previewed, unlike Terraform's plan file, which is applied as a literal, saved set of intended actions.

### Common Weak Answer
"ansible-playbook --check is basically the same as terraform plan, just use that."

### Why the Weak Answer Fails
This overstates the guarantee `--check` actually provides — presenting it as equivalent to Terraform's plan/apply model risks the team trusting a false sense of applied-matches-reviewed certainty that Ansible's architecture doesn't structurally provide, exactly the honest gap this repository's own documentation calls out explicitly.

### Follow-Up Questions
1. What practical steps would you take to minimize (even if not eliminate) the check-to-apply drift window for a genuinely high-stakes production change?
2. How would you communicate this capability difference honestly to a team or stakeholder expecting Terraform-equivalent guarantees?
3. How does this connect to the broader theme of Ansible's architectural differences from Terraform discussed throughout this repository?

### Key Interview Signals
Gives an honest, technically precise explanation of why Ansible's `--check` mode is a genuine but structurally weaker guarantee than Terraform's plan/apply model, rather than overstating the similarity for false reassurance.

### Hands-On Connection
[Lab 12 — CI/CD Pipeline](../labs/lab-12-cicd-pipeline/).

---

## Question 73: The Execution Environment that drifted from every developer's laptop

### Scenario
A team's playbooks behave inconsistently between a developer's local `ansible-playbook` run (using whatever Ansible/collection versions happen to be installed on their laptop) and AWX's own execution, which uses a pinned Execution Environment image — occasionally, a module behaves differently or a collection isn't even available locally, causing confusing, hard-to-reproduce discrepancies.

### Interview Question
Diagnose this consistency gap and design the fix.

### Strong Senior-Level Answer
**Initial assessment:** per [`docs/ansible-architecture.md`](../docs/ansible-architecture.md) Part A, this is exactly the reproducibility problem Execution Environments exist to solve — a developer's laptop, with its own independently-installed Ansible/collection versions, is an uncontrolled, drifting environment relative to AWX's pinned EE image, and any discrepancy between the two is expected, not surprising, given they're genuinely different, unsynchronized environments.

**Technical reasoning:** without developers also using the same Execution Environment (via `ansible-navigator`, which runs playbooks inside the same container image AWX uses) for local development/testing, there's no structural guarantee their local runs reflect the same module/collection versions as production AWX execution — this is the same "works on my machine" gap the companion EKS repository's Question 40-adjacent guidance addresses for developer/CI consistency generally.

**Investigation process:** confirm the specific version discrepancies causing the reported behavioral differences (which collection/module version differs between a specific developer's laptop and the AWX EE image) — this concretely demonstrates the drift's real impact.

**Recommended solution:** require developers to use `ansible-navigator` (or an equivalent EE-aware execution wrapper) referencing the *same* Execution Environment image AWX uses, for all local development and testing — eliminating the laptop-vs-AWX environment drift entirely by having both use the identical, pinned image.

**Risk controls:** ensure the EE image build process (via `ansible-builder`) is itself version-controlled and its build definition reviewed like any other infrastructure-as-code artifact, so the "single source of truth" EE image is itself reproducible and auditable.

**Validation steps:** after developers switch to `ansible-navigator`-based local execution, confirm previously-inconsistent playbook behavior now matches consistently between local and AWX execution.

**Rollback or recovery strategy:** not applicable — this is an environment-consistency improvement, not a change with its own rollback consideration.

**Long-term prevention:** treat "does local development use the same Execution Environment as production automation" as a standard onboarding/tooling requirement for the team, exactly mirroring the companion EKS repository's guidance on using the same container image/tooling across CI and local development to avoid "works on my machine" discrepancies.

### Step-by-Step Implementation
```bash
# Developer local execution - using the SAME EE image as AWX
ansible-navigator run site.yml --eei my-registry/ansible-ee:v3.2.0 -m stdout
```

### Under-the-Hood Explanation
`ansible-navigator` executes playbooks inside a container built from the same Execution Environment image definition (`ansible-builder`-produced) that AWX itself uses for job execution — this means both local development and production automation are running against byte-for-byte identical Ansible core, collection, and Python dependency versions, structurally eliminating the class of version-drift discrepancy a locally-and-independently-installed Ansible setup would otherwise introduce.

### Common Weak Answer
"Just tell developers to keep their local Ansible/collection versions up to date manually."

### Why the Weak Answer Fails
Manual version-matching across every developer's independently-managed laptop environment is exactly the kind of unenforceable, drift-prone process this repository series consistently identifies as insufficient — the EE-based approach removes the version-matching burden from individual developers entirely by having everyone use the identical, pinned image.

### Follow-Up Questions
1. How would you manage the EE image's own version-update process to keep it current without breaking developer workflows unexpectedly?
2. What's the onboarding process for a new developer to correctly set up `ansible-navigator`-based local execution from day one?
3. How does this compare to the companion EKS repository's container-image-consistency guidance for CI/CD pipelines generally?

### Key Interview Signals
Correctly diagnoses the laptop-vs-AWX environment drift as the root cause of inconsistent playbook behavior, and fixes it by having both environments use the identical, pinned Execution Environment image rather than relying on manual version-matching.

### Hands-On Connection
[Lab 12 — CI/CD Pipeline](../labs/lab-12-cicd-pipeline/).

---

## Question 74: The workflow template that half-succeeded

### Scenario
An AWX Workflow Template chains three Job Templates sequentially: provision infrastructure (via a Terraform-invoking Job Template), configure it (an Ansible playbook), then run smoke tests. The middle step fails partway through (a transient network blip), but the workflow's failure-handling isn't configured, so the smoke-test step runs anyway against a partially-configured target, producing confusing, misleading test failures.

### Interview Question
Diagnose this workflow-failure-handling gap and redesign it.

### Strong Senior-Level Answer
**Initial assessment:** AWX Workflow Templates require explicit configuration of what happens on a given node's failure (proceed to a specific "on failure" path, or halt the workflow entirely) — without this configured, the default behavior may not match the team's actual intent, and here, allowing the smoke-test step to proceed against a known-partially-configured target produces exactly the confusing, misleading result described.

**Technical reasoning:** AWX Workflow Templates model execution as a directed graph with explicit "on success" and "on failure" edges between nodes — if the configuration edge for the middle step's failure path isn't set to halt (or route to a remediation/notification node) rather than falling through to the next node's default "on success" path, the workflow can continue in a state the team never actually intended.

**Investigation process:** review the Workflow Template's actual node-to-node edge configuration for the configuration step — confirming whether its failure path was left unconfigured/defaulting to unintended continuation, versus a genuine AWX bug (unlikely, but worth ruling out per the postmortem-rigor discipline from the companion EKS repository).

**Recommended solution:** explicitly configure the configuration step's failure edge to halt the workflow (rather than proceeding to smoke tests) and route to a failure-notification node — ensuring a failed configuration step never allows a misleading smoke-test run against a known-bad target state.

**Risk controls:** for any multi-step workflow with real dependencies between steps (as here — smoke tests are meaningless against unconfigured infrastructure), explicitly design and test every failure-path edge, not just the happy-path success chain.

**Validation steps:** deliberately inject a failure into the configuration step in a test workflow and confirm the smoke-test step correctly does NOT run, with a clear failure notification instead.

**Rollback or recovery strategy:** for the specific incident, re-run the configuration step (or the full workflow) once the transient network issue has cleared, and disregard the misleading smoke-test results from the broken run.

**Long-term prevention:** treat explicit failure-path configuration as a mandatory design element for every AWX Workflow Template with sequential, dependent steps — never relying on default/unconfigured behavior for what happens when an intermediate step fails.

### Step-by-Step Implementation
```text
AWX Workflow Template node configuration:
Node 1 (Provision) --on success--> Node 2 (Configure)
Node 2 (Configure)  --on success--> Node 3 (Smoke Test)
Node 2 (Configure)  --on FAILURE--> Node 4 (Notify + Halt)  <- explicitly configured,
                                                                not left as default
```

### Under-the-Hood Explanation
AWX Workflow Templates only execute a subsequent node if the appropriate edge condition (success/failure/always) from the preceding node is met and explicitly wired — a node with no explicitly-configured failure edge simply doesn't have a defined path for that outcome, and depending on the specific workflow structure, this can result in either the workflow correctly halting (if no edge exists at all for that path) or, in a more complex/branching workflow, an unintended node still executing via a different, unrelated edge condition that wasn't intended to fire in this failure scenario — exactly the kind of design gap requiring explicit, deliberate configuration rather than reliance on default behavior.

### Common Weak Answer
"AWX must have a bug allowing a later step to run after an earlier one failed."

### Why the Weak Answer Fails
This assumes a platform defect before checking whether the workflow's own failure-path edges were actually configured as intended — in the overwhelming majority of cases, this is a workflow-design gap (missing or incorrect edge configuration), not an AWX malfunction, exactly the same "check configuration before blaming the platform" discipline established in the companion EKS repository's postmortem-rigor guidance.

### Follow-Up Questions
1. How would you test every failure-path edge in a complex, multi-node Workflow Template systematically before relying on it in production?
2. What's the right notification/escalation design for a halted workflow, ensuring someone actually responds to the failure?
3. How does this compare to the companion EKS repository's ArgoCD sync-wave health-check gap (Question 94) — both cases of an unconfigured or missing gating condition allowing unintended progression?

### Key Interview Signals
Diagnoses a missing or incorrectly-configured failure-path edge as the root cause rather than assuming a platform defect, and redesigns the workflow with explicit, tested failure handling for every dependent step.

### Hands-On Connection
[Lab 12 — CI/CD Pipeline](../labs/lab-12-cicd-pipeline/).

---

## Question 75: The drift-detection job that never detected anything

### Scenario
A scheduled AWX Job Template runs a playbook in `--check` mode nightly, intended to detect configuration drift across the fleet by reporting on any tasks that would report `changed: true`. For the past year, it has reported "no drift" every single night — but a manual audit reveals significant, real drift has accumulated (several packages manually upgraded outside Ansible's management, a few config files hand-edited during past incidents).

### Interview Question
Diagnose why the automated drift-detection job missed real, existing drift.

### Strong Senior-Level Answer
**Initial assessment:** a drift-detection job can only detect drift in *exactly what the playbook's tasks actually check and manage* — if the playbook doesn't have a task explicitly covering a given package/file/configuration item, drift in that specific, unmanaged item is entirely invisible to the check, regardless of how real and significant it is.

**Technical reasoning:** `--check` mode's "no changes" result reflects "nothing the playbook's tasks would change," not "the system matches some broader, complete definition of correct configuration" — if the manually-upgraded packages and hand-edited config files were never brought under this playbook's explicit management (no corresponding task exists for them at all), the check mode has genuinely nothing to compare against for those specific items, producing a false sense of "no drift" that's really "no drift in what we're actually checking."

**Investigation process:** review the playbook's actual task coverage against the full, real configuration surface of the managed hosts — identifying exactly which packages/files/settings exist on the hosts but have no corresponding Ansible task managing them at all (the manually-upgraded packages and hand-edited files from the audit).

**Recommended solution:** expand the playbook's task coverage to explicitly manage every configuration item that matters for compliance/consistency purposes (bringing the previously-unmanaged, manually-modified items under Ansible's management), so drift in those areas becomes genuinely detectable going forward; for the already-existing drift, decide deliberately whether to reconcile it back to the intended baseline or update the baseline to reflect a legitimately-needed change that was made manually.

**Risk controls:** recognize that "our drift-detection reports clean" is only ever as trustworthy as the actual scope of what's being checked — treat this as a standing caveat whenever relying on a drift-detection job's clean result as evidence of genuine configuration consistency.

**Validation steps:** after expanding task coverage, confirm the drift-detection job now correctly reports drift for a deliberately-reintroduced test discrepancy in one of the newly-covered areas, proving the expanded coverage genuinely works.

**Rollback or recovery strategy:** not applicable — this is a coverage-expansion fix, not a change requiring rollback.

**Long-term prevention:** periodically audit the actual scope of what a drift-detection playbook manages against the full, real configuration surface of the hosts it's meant to be validating, specifically looking for manually-introduced changes that have never been brought under any task's management — treating "clean drift report" and "genuinely fully consistent configuration" as two different claims that shouldn't be conflated.

### Step-by-Step Implementation
```text
Periodic audit process: compare the playbook's actual task coverage
(what files/packages/settings it explicitly manages) against a broader,
independent inventory of the host's actual installed packages/modified
files (e.g., via a package-manager history diff, or a file-integrity-
monitoring tool's change log) - flagging anything present on the host
but absent from the playbook's management scope as a coverage gap.
```

### Under-the-Hood Explanation
`--check` mode evaluates exactly the tasks present in the playbook against the current live state of whatever those specific tasks target — it has no independent, broader awareness of the host's full configuration surface beyond what the playbook's authors chose to include as tasks; anything genuinely outside that scope (a package installed by a different process, a file edited by a human directly) simply never enters the check's evaluation at all, producing a "clean" result that only reflects the narrow scope actually being checked.

### Common Weak Answer
"If the drift check reports no changes, the fleet must be fully consistent."

### Why the Weak Answer Fails
This conflates "no drift detected within the playbook's actual, limited task coverage" with "no drift exists anywhere on the system" — exactly the false confidence this manual audit exposed, since real, significant drift existed entirely outside what the playbook was ever checking in the first place.

### Follow-Up Questions
1. How would you systematically identify configuration items that matter for compliance but currently have no corresponding Ansible task managing them?
2. What's the trade-off of expanding task coverage to manage every possible configuration item versus focusing on genuinely important ones?
3. How does this relate to the companion EKS repository's "prevent plus independently detect" layered-defense pattern for untagged/unmanaged infrastructure?

### Key Interview Signals
Correctly distinguishes "no drift within our checked scope" from "no drift anywhere," recognizing that a clean drift-detection result is only as meaningful as the actual coverage of what's being checked, and expands coverage accordingly.

### Hands-On Connection
[Lab 6 — Error Handling and Safe Refactoring](../labs/lab-06-error-handling-and-refactoring/) and [Lab 12 — CI/CD Pipeline](../labs/lab-12-cicd-pipeline/).

---

## Question 76: The pipeline that couldn't tell success from silence

### Scenario
A CI pipeline stage running `ansible-playbook` against a large inventory completes with exit code 0 (success), but a review of the actual output shows several hosts were silently skipped (via an inventory pattern mismatch, similar to the earlier "zero hosts matched" pattern) — the playbook succeeded for the hosts it did match, masking the fact that a meaningful subset of the intended fleet was never touched at all.

### Interview Question
Diagnose why a partial, incomplete run still reported overall pipeline success.

### Strong Senior-Level Answer
**Initial assessment:** `ansible-playbook`'s exit code reflects whether the tasks that *did* run completed without failure — it has no inherent concept of "did this run cover the full, intended scope of hosts," meaning a play that correctly succeeds against a smaller-than-intended host set (due to an inventory pattern mismatch) reports the same success exit code as a play that correctly covered the full intended fleet.

**Technical reasoning:** this is the CI-pipeline-visibility manifestation of the same "zero/partial hosts matched" silent-gap pattern from earlier in this repository — the pipeline's own success/failure signal (exit code) is an incomplete proxy for "did the intended work actually happen everywhere it should have," and without an explicit host-count verification step, this gap goes unnoticed exactly as described.

**Investigation process:** review the specific inventory pattern used and compare the actual matched host count against the expected, full intended host count for this run — confirming the mismatch's scope and root cause (likely a stale/incorrect pattern, similar to earlier inventory-pattern-mismatch scenarios).

**Recommended solution:** add an explicit post-run verification step to the CI pipeline comparing the playbook's actual `PLAY RECAP`-reported host count against an independently-derived expected count (e.g., querying the dynamic inventory source directly for how many hosts *should* match the intended target group) — failing the pipeline explicitly if these counts don't reconcile, rather than trusting the bare exit code alone.

**Risk controls:** treat any playbook run against a large, dynamically-resolved inventory as requiring this kind of independent host-count verification by default, given how easy an inventory-pattern mismatch is to introduce unnoticed (a typo, a tag rename, a filter change).

**Validation steps:** after adding the verification step, deliberately introduce a test inventory-pattern mismatch and confirm the pipeline now correctly fails rather than reporting silent, incomplete success.

**Rollback or recovery strategy:** for the specific incident, identify exactly which hosts were missed and re-run the playbook targeting them specifically, once the inventory pattern is corrected.

**Long-term prevention:** treat "does our CI pipeline's success signal actually reflect complete, intended-scope coverage, not just successful completion of whatever subset happened to match" as a standard verification requirement for any large-fleet automation pipeline — exit code 0 alone is an insufficient success signal whenever dynamic inventory resolution is involved.

### Step-by-Step Implementation
```yaml
# CI pipeline - explicit host-count verification, not trusting exit code alone
- name: Run playbook
  run: ansible-playbook site.yml -i inventory/aws_ec2.yml --limit production_web | tee run.log

- name: Verify actual host count matches expected
  run: |
    ACTUAL=$(grep -c "^ok=\|^changed=" run.log)  # simplified; real check parses PLAY RECAP
    EXPECTED=$(ansible-inventory -i inventory/aws_ec2.yml --list | jq '.production_web.hosts | length')
    if [ "$ACTUAL" -lt "$EXPECTED" ]; then
      echo "Host count mismatch: expected $EXPECTED, playbook covered $ACTUAL"
      exit 1
    fi
```

### Under-the-Hood Explanation
`ansible-playbook`'s process exit code is determined purely by whether any task failed among the hosts actually included in the run — it carries no information about whether the *set* of hosts included was itself correct or complete relative to the operator's actual intent, which is exactly why an independent, explicit count-verification step is needed to catch a silent, partial-coverage gap that the bare exit code cannot reveal.

### Common Weak Answer
"Exit code 0 means the pipeline succeeded, that should be sufficient."

### Why the Weak Answer Fails
This conflates "no task failed for the hosts that were included" with "the intended, complete scope of hosts was actually covered" — precisely the gap this scenario demonstrates, where a real, meaningful subset of the fleet was silently excluded while the pipeline still reported clean success.

### Follow-Up Questions
1. How would you design the expected-host-count derivation to be genuinely independent of the same inventory resolution the playbook itself uses (to avoid the verification sharing the same blind spot)?
2. How would you extend this pattern to detect a similar issue in a Kubernetes-targeting Ansible task, rather than just VM-fleet inventory?
3. How does this connect to the earlier "zero hosts matched" and "silent gap" patterns established elsewhere in this repository?

### Key Interview Signals
Recognizes that exit code 0 doesn't guarantee complete, intended-scope coverage for a dynamically-resolved inventory, and designs an explicit, independent host-count verification step closing this specific silent-gap risk.

### Hands-On Connection
[Lab 3 — Dynamic Inventory](../labs/lab-03-dynamic-inventory/) and [Lab 12 — CI/CD Pipeline](../labs/lab-12-cicd-pipeline/).

---

## Question 77: The concurrent AWX runs that collided

### Scenario
Two engineers, unaware of each other, launch the same Job Template against overlapping subsets of the fleet within a minute of each other. Both runs proceed concurrently, and one host ends up in an inconsistent state, having been mid-modification by one run when the second run's task began executing against it.

### Interview Question
Diagnose this concurrency risk and design a prevention mechanism.

### Strong Senior-Level Answer
**Initial assessment:** per [`docs/cicd.md`](../docs/cicd.md)'s fleet-level-concurrency-controls guidance, Ansible/AWX has no built-in, automatic per-inventory locking preventing two independent runs from targeting overlapping hosts simultaneously — unlike Terraform's state-locking mechanism (which structurally prevents concurrent operations against the same state), AWX requires this concurrency protection to be explicitly configured.

**Technical reasoning:** AWX supports a **Job Template concurrency setting** ("Prevent Simultaneous Job Runs" / instance-group-level concurrency limits) that, if not enabled, allows exactly this kind of overlapping, concurrent execution against the same hosts — without it, two independently-launched runs proceed entirely unaware of and uncoordinated with each other, exactly as happened here.

**Investigation process:** confirm the Job Template's current concurrency configuration — very likely, "Prevent Simultaneous Job Runs" was not enabled, allowing this collision to occur.

**Recommended solution:** enable AWX's "Prevent Simultaneous Job Runs" setting for this Job Template (and audit others for the same gap), ensuring a second launch attempt while one is already running is either queued (waiting for the first to complete) or rejected, rather than proceeding concurrently against potentially-overlapping hosts.

**Risk controls:** for the specific host left in an inconsistent state, run the playbook again against it specifically (now protected by the concurrency setting) to bring it to a fully consistent, known-correct state.

**Validation steps:** after enabling the setting, deliberately attempt to launch the same Job Template twice in quick succession and confirm the second attempt is correctly queued/rejected rather than running concurrently.

**Rollback or recovery strategy:** not applicable beyond the specific host's remediation.

**Long-term prevention:** treat "Prevent Simultaneous Job Runs" (or an equivalent concurrency-limiting mechanism) as a standard, default-on configuration for any Job Template that mutates shared infrastructure state, exactly mirroring the concurrency-control discipline this repository's own `docs/cicd.md` establishes for CI/CD pipelines generally.

### Step-by-Step Implementation
```text
AWX Job Template settings:
[x] Prevent Simultaneous Job Runs

# Ensures a second launch while one is active is queued, not run concurrently
```

### Under-the-Hood Explanation
Without "Prevent Simultaneous Job Runs" enabled, AWX treats each Job Template launch as an entirely independent execution, scheduled onto available capacity with no coordination against other currently-running instances of the same template — enabling this setting adds an explicit, AWX-enforced serialization constraint, queuing subsequent launch attempts until the currently-running instance completes.

### Common Weak Answer
"Just ask engineers to check with each other before launching a Job Template manually."

### Why the Weak Answer Fails
This relies on informal, easily-forgotten human coordination rather than a structural, enforced constraint — exactly the "remember to be careful" non-control this repository series consistently identifies as insufficient; AWX's own concurrency setting provides a genuine, enforced guarantee instead.

### Follow-Up Questions
1. How would you audit all existing Job Templates for missing concurrency protection, given how easy this is to overlook per-template?
2. What's the trade-off of queuing versus rejecting a concurrent launch attempt, and which is more appropriate for different types of playbooks?
3. How does this compare to Terraform's built-in state-locking mechanism — why doesn't Ansible have an equivalent by default?

### Key Interview Signals
Identifies AWX's "Prevent Simultaneous Job Runs" as the specific, structural fix for this concurrency gap, correctly noting that Ansible/AWX lacks Terraform's automatic state-locking and requires this protection to be explicitly configured.

### Hands-On Connection
[Lab 12 — CI/CD Pipeline](../labs/lab-12-cicd-pipeline/).

---

## Question 78: The AWX instance that was a single point of failure for everything

### Scenario
A single AWX instance (non-HA, single node) manages configuration for the organization's entire production fleet across all environments. During a routine OS patch of the AWX host itself, it goes down for 45 minutes — during which an unrelated production incident occurs, and the team's only remediation playbook (which would normally be run via this same AWX instance) can't be executed at all.

### Interview Question
Diagnose this architectural single point of failure and design the fix.

### Strong Senior-Level Answer
**Initial assessment:** a single, non-HA AWX instance responsible for all automation across the entire fleet is exactly the "recovery/remediation tool sharing fate with what it's meant to recover" risk pattern established in [`docs/ha-dr.md`](../docs/ha-dr.md) §1 — when AWX itself is down (for any reason, routine maintenance or genuine failure), every automation capability depending on it, including incident remediation, becomes unavailable at potentially the worst possible moment.

**Technical reasoning:** the Ansible Automation Platform (AWX's commercially-supported counterpart) supports genuine multi-node HA clustering (multiple AWX/task-execution nodes, an HA PostgreSQL backend) specifically to eliminate this single point of failure — a single-node AWX deployment forgoes this resilience entirely, meaning any AWX-host-level disruption (patching, an unrelated infrastructure issue, a genuine failure) takes down the entire automation capability simultaneously.

**Investigation process:** confirm the organization's current AWX deployment topology (single-node, as described) and assess the actual criticality of automation availability during exactly the kind of moment (an active incident) this scenario demonstrates matters most.

**Recommended solution:** migrate to a multi-node, HA AWX/Automation Platform deployment (with an HA PostgreSQL backend, per [`docs/ha-dr.md`](../docs/ha-dr.md) §1) — eliminating the single-node dependency, so routine maintenance (or even a node-level failure) doesn't take down the entire automation capability.

**Risk controls:** in the interim, before HA migration is complete, schedule any AWX-host-level maintenance (patching, upgrades) during genuinely low-risk windows, and ensure a documented, tested manual fallback exists for genuinely critical remediation playbooks (e.g., the ability to run the specific remediation playbook directly via `ansible-playbook` from a backup control node, bypassing AWX entirely, if AWX itself is unavailable during a real emergency) — a break-glass path for exactly this scenario.

**Validation steps:** after HA migration, deliberately take one node down (in a controlled test) and confirm automation capability (including the ability to launch a Job Template) remains available via the remaining node(s).

**Rollback or recovery strategy:** for the immediate incident described, the actual recovery was presumably manual (running the remediation directly, or waiting out the 45-minute AWX outage) — exactly the kind of situation the HA migration and break-glass fallback are meant to prevent recurring.

**Long-term prevention:** treat AWX's own availability architecture with the same rigor as any other critical platform component discussed throughout this repository — a single point of failure for the organization's entire automation capability is a standing risk worth prioritizing for HA remediation, and a tested break-glass fallback (direct `ansible-playbook` execution bypassing AWX) should exist regardless, exactly mirroring the companion EKS repository's GitOps-controller-availability-during-DR lesson.

### Step-by-Step Implementation
```text
Migrate to multi-node AWX/Automation Platform:
- Multiple AWX/task-execution nodes behind a load balancer
- HA PostgreSQL backend (the most critical piece per docs/ha-dr.md §1)
- Break-glass fallback: a documented, tested process for running critical
  remediation playbooks directly via ansible-playbook from a backup
  control node, bypassing AWX entirely, for use only if AWX itself is down
```

### Under-the-Hood Explanation
AWX/Automation Platform's HA architecture distributes both the web/API layer and task-execution capacity across multiple nodes, backed by a genuinely HA PostgreSQL database (the actual source of truth for job history, credentials, inventory, and templates) — a single-node deployment collapses all of this onto one host, meaning any disruption to that host (routine or otherwise) removes the entire automation capability simultaneously, exactly the single-point-of-failure risk multi-node HA is designed to eliminate.

### Common Weak Answer
"Just schedule AWX maintenance during off-hours to minimize the risk."

### Why the Weak Answer Fails
This reduces the *likelihood* of a maintenance-window collision with a real incident but does nothing about the more fundamental risk — a genuine, unplanned AWX failure (not just scheduled maintenance) can occur at any time, including during an active incident, and only a genuinely HA architecture (plus a tested break-glass fallback) actually closes this gap rather than just reducing one specific trigger's probability.

### Follow-Up Questions
1. How would you design and test the break-glass fallback process for running critical remediation playbooks if AWX itself is unavailable?
2. What's the migration path/complexity for moving from a single-node AWX deployment to a full HA Automation Platform cluster?
3. How does this scenario mirror the companion EKS repository's GitOps-controller-availability-during-a-regional-DR-event lesson?

### Key Interview Signals
Recognizes a single-node AWX deployment as a genuine, high-impact single point of failure for the organization's entire automation capability, and designs both a proper HA architecture and a tested break-glass fallback for exactly the "the tool you need during an incident is itself down" scenario.

### Hands-On Connection
[Lab 12 — CI/CD Pipeline](../labs/lab-12-cicd-pipeline/) and [Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).
