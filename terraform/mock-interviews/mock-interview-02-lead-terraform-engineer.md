# Mock Interview 2: Lead Terraform Engineer

**Format**: 15 questions. **Focus**: Architecture, module design, governance, and CI/CD. **Level target**: Lead (score 4 on the rubric is the pass bar; 3 is underperforming for this level, 5 is exceptional).

---

## Question 1
**Interviewer asks:** "Your team ships what looks like a minor module update, and forty consumer repositories break within hours. How do you respond, and what changes structurally afterward?"

**Expected answer points:**
- Identifies both root causes: unconstrained consumer version pinning (`>= 4.0`) and a breaking change misclassified as non-major.
- Immediate fix: patch/yank the release or add a backward-compatible alias; don't just tell consumers to "wait."
- Structural fix: mandatory semver classification with CHANGELOG, contract testing against real consumer configs before any release, deprecation windows for removed interface elements.

**Follow-up questions:**
1. How would you retrofit proper version pinning across forty existing consumers?
2. What does your contract-test matrix actually look like in CI?
3. How do you handle a genuinely unavoidable breaking change with no possible alias?

**Red flags:** "We should test modules before releasing" with no specifics on *what* test or *why* this specific failure happened.

**Model answer:** *"Two things compounded: consumers weren't pinning tightly (`>= 4.0` floats onto anything), and a rename that should have been a major bump shipped as something smaller. Immediately, I'd patch a backward-compatible alias for the renamed input to unblock everyone, then cut the real change as a proper major with a migration guide. Structurally: every module PR gets a CHANGELOG entry classified by semver impact, and no major version ships without running its plan against a representative sample of real consumer configs first — that's what actually would have caught this before it reached production."*

**Full reference:** [Question 23](../interview-questions/03-modules.md#question-23-the-version-bump-that-broke-forty-repositories)

---

## Question 2
**Interviewer asks:** "Two of your platform modules — networking and security — have ended up with a circular dependency. How do you redesign it?"

**Expected answer points:**
- Recognizes this as a modeling problem, not something `depends_on` can fix.
- Identifies the specific tightly-coupled resource pair causing the cycle.
- Fix: extract the shared concern into a layer both depend on, or merge the modules if the coupling is pervasive.

**Follow-up questions:**
1. How would you have caught this during design review, before it was implemented?
2. When is merging two modules the right call versus extracting a third?
3. How do you verify no new cycle was introduced by the fix?

**Red flags:** Suggests `depends_on` as a fix for a genuine cycle.

**Model answer:** *"A real cycle can't be resolved with ordering hints — `depends_on` doesn't help if both modules genuinely need each other's output. I'd find the specific resource pair actually causing the mutual dependency, and either extract it into a third module both depend on from above, or merge the two modules entirely if the coupling turns out to be pervasive rather than isolated to one resource pair."*

**Full reference:** [Question 24](../interview-questions/03-modules.md#question-24-the-module-that-depended-on-itself)

---

## Question 3
**Interviewer asks:** "You inherit a module with fifty optional variables and a history of misconfiguration. Redesign philosophy?"

**Expected answer points:**
- Diagnoses this as a flexibility-over-opinion trade-off gone wrong for an application-facing module.
- Audit actual usage to find the small set of genuinely-varying inputs.
- Redesign around a small, opinionated core with a narrow, reviewed escape hatch, not a full re-expansion.

**Follow-up questions:**
1. How do you migrate existing consumers without a disruptive simultaneous cutover?
2. Is there ever a case a fully flexible module is still correct?
3. How would you prevent this drift back toward fifty variables over the next two years?

**Red flags:** "Add better documentation" as the complete answer.

**Model answer:** *"Fifty options with no real opinion pushes every correctness/security decision onto the consumer — that's the actual root cause of the misconfiguration history, not a documentation gap. I'd audit real usage to find what genuinely varies, redesign around a small opinionated core with safe defaults, and keep a narrow, reviewed escape hatch for real exceptions — then ship it as a major version with a migration guide, letting consumers move at their own pace rather than a forced cutover."*

**Full reference:** [Question 25](../interview-questions/03-modules.md#question-25-the-module-with-fifty-optional-variables)

---

## Question 4
**Interviewer asks:** "Your organization's forty internal modules are referenced via raw Git URLs with inconsistent tags. Would you move to a private registry, and how?"

**Expected answer points:**
- Yes — registries provide discoverability, version listing, and (in TFC/TFE) consumer usage visibility raw Git sourcing lacks.
- Migration is per-consumer, source/version-only, verified zero-diff — no resource impact.
- Migrate incrementally, low-risk consumers first.

**Follow-up questions:**
1. How do you handle modules that were never given proper semver tags?
2. What does the registry give you beyond nicer source strings?
3. How would you enforce no new ad hoc Git-URL usage going forward?

**Red flags:** "Just tell people to use the registry for new usage" — ignores the existing forty modules' visibility gap entirely.

**Model answer:** *"Yes, and the migration is low-risk because it's purely a source-address change — the module content and resource addressing don't change at all, so each consumer's migration should be a zero-diff plan. I'd validate the registry setup with a few low-risk consumers first, then roll out broadly, and afterward enforce via convention/lint that no new module consumption uses raw Git URLs — the whole point is the visibility the registry provides, which only pays off once consumers are actually on it."*

**Full reference:** [Question 29](../interview-questions/03-modules.md#question-29-retiring-the-ad-hoc-git-tag-module-sources)

---

## Question 5
**Interviewer asks:** "Design the Terraform architecture for an organization running 100 AWS accounts across three regions."

**Expected answer points:**
- Layered state (foundation/platform/application) with account+region-scoped provider aliasing/assume-role.
- Pipeline matrix parameterizing account/region against one tested module set, not hand-duplicated configs.
- Governance via SCPs (non-negotiable) plus policy-as-code (reviewable, testable) as complementary layers.
- Recognizes six-person platform teams need to scale via structure, not manual review.

**Follow-up questions:**
1. How do you roll out a foundation-layer change across all 100 accounts safely?
2. How would you handle one business unit needing different compliance requirements?
3. What's your account-vending story for the 101st account?

**Red flags:** "Use a for_each loop over the account list in one configuration" — recreates the monolithic-state blast-radius problem at even larger scale.

**Model answer:** *"This needs every architectural pattern working together, not one silver bullet: provider aliasing/assume-role for targeting, per-account-per-layer state separation for blast radius, a pipeline matrix so the module set stays single and tested rather than duplicated, and both SCPs (non-bypassable) and policy-as-code (reviewable, testable) for governance — because a six-person platform team can't manually review every change across 100 accounts; it has to scale through structure."*

**Full reference:** [Question 43](../interview-questions/05-aws-architecture.md#question-43-a-hundred-accounts-several-regions-one-terraform-estate)

---

## Question 6
**Interviewer asks:** "Your pipeline reviews a plan, gets approval, then re-runs `terraform plan` fresh at apply time instead of applying the saved artifact. What's wrong, even if it usually works fine?"

**Expected answer points:**
- Regenerating breaks the provable guarantee that what was reviewed is what's applied.
- State could have changed between review and apply (another pipeline, drift).
- Fix: always apply the exact saved plan file; rely on Terraform's own staleness check to fail loudly if state moved on.

**Follow-up questions:**
1. What's the actual Terraform mechanism enforcing this (serial/lineage)?
2. How do you handle the resulting "stale plan" failure operationally?
3. What's the cost of storing plan artifacts, and how do you manage it?

**Red flags:** "It's fine, the two plans almost always match" — misses that "usually" is the wrong bar for this guarantee.

**Model answer:** *"'Usually matches' isn't the same as 'provably identical,' and the entire point of a plan-review gate is the provable guarantee. If state changed between the reviewed plan and a freshly-regenerated one — another pipeline applied, drift occurred — a fresh plan silently applies something nobody actually reviewed. The fix is applying the exact saved plan artifact; Terraform's own serial/lineage check will then fail loudly and safely if state has moved on, which is exactly the behavior we want, not something to route around."*

**Full reference:** [Question 69](../interview-questions/08-cicd.md#question-69-the-apply-that-wasnt-quite-what-was-reviewed)

---

## Question 7
**Interviewer asks:** "How do you design environment protection and approval gates across dev, staging, and production?"

**Expected answer points:**
- Gates tighten by environment: auto-apply for dev, review for staging, mandatory named-reviewer approval for production.
- Approval must gate the exact previously-reviewed plan artifact.
- Approver list should be tied to an actively-maintained team/rotation, not a static hand-maintained list.

**Follow-up questions:**
1. How do you prevent the production approver list from silently growing to thirty people over two years?
2. What's the OIDC trust-policy detail that must match this gate for it to be meaningful?
3. How do you handle a genuine emergency needing to bypass this?

**Red flags:** Describes only "add a manual approval step" with no mention of artifact integrity or approver-list maintenance.

**Model answer:** *"Gates should tighten by environment — dev can auto-apply, staging gets a review, production requires a named reviewer approving the exact plan artifact that was generated and reviewed earlier, not a fresh one. I'd tie the production approver list to an actively-maintained on-call rotation or team, not a hand-maintained list, since those always drift — and I'd make sure the OIDC trust policy's environment claim actually matches this gate, or a workflow could assume the production role without ever passing through it."*

**Full reference:** [Question 73](../interview-questions/08-cicd.md#question-73-too-many-people-who-can-say-yes)

---

## Question 8
**Interviewer asks:** "Your organization is adopting policy-as-code for the first time on self-managed, open-source Terraform. A vendor pitches Sentinel as the obvious choice. Do you agree?"

**Expected answer points:**
- No — Sentinel's integration path assumes Terraform Cloud/Enterprise; Conftest/OPA fits a self-managed, any-CI-platform stack with no platform dependency.
- Decision should be platform-fit driven, not vendor-branding driven.
- Revisit if the organization later adopts TFC/TFE.

**Follow-up questions:**
1. What would change your answer?
2. How do you structure a growing Rego policy library so it stays maintainable?
3. How do you test the policies themselves, not just use them?

**Red flags:** "Sentinel is HashiCorp's own tool so it's the safest choice" — vendor-affiliation reasoning, not platform-fit reasoning.

**Model answer:** *"No — Sentinel's real integration value comes from being built into Terraform Cloud/Enterprise's run pipeline, which this organization doesn't use. Conftest evaluates plan JSON from any CI platform with zero dependency on which execution platform ran Terraform, which matches a self-managed, GitHub-Actions-based stack far better. I'd revisit this if the organization later adopts TFC/TFE, but the decision should be about actual platform fit, not which vendor pitched hardest."*

**Full reference:** [Question 67](../interview-questions/07-security.md#question-67-choosing-a-policy-engine-before-you-have-a-platform-for-it)

---

## Question 9
**Interviewer asks:** "An audit finds 30% of resources missing mandatory tags despite a year-old documented policy. Fix it."

**Expected answer points:**
- Documentation-only policy is a request, not a control.
- Structural fix: `default_tags` at the provider level (reduces reliance on memory) plus a policy-as-code deny gate (actual enforcement).
- Separate the retroactive remediation sweep from the forward-looking structural fix.

**Follow-up questions:**
1. How do you handle resource types that genuinely can't support the tag schema?
2. How would you extend enforcement to resources created outside Terraform?
3. What ongoing metric would you report to prove this doesn't regress?

**Red flags:** "Send a reminder to the engineering org" as the complete fix.

**Model answer:** *"A documented-but-unenforced policy predictably degrades — that's exactly what a year of drift to 30% shows. I'd add `default_tags` at the provider level so compliance becomes the default rather than a remembered step, and a policy-as-code gate denying any plan introducing an untagged resource as the actual enforcement. Then a one-time remediation sweep for the existing gap, plus ongoing tag-compliance percentage reporting so this doesn't silently recur."*

**Full reference:** [Question 111](../interview-questions/13-governance.md#question-111-tags-that-were-supposed-to-be-mandatory)

---

## Question 10
**Interviewer asks:** "A single state with 5,000 resources takes twenty minutes to plan and one lock serializes changes across completely unrelated systems. Redesign it."

**Expected answer points:**
- Recognizes child modules aren't state boundaries — the fix is separate root modules/backends.
- Split along ownership, change-frequency, and blast-radius lines (layered architecture).
- Migrate incrementally via `state mv`/`moved` blocks, verifying zero-diff at each step.

**Follow-up questions:**
1. How do you sequence which boundary to extract first?
2. How do teams get cross-boundary data after the split, if not via shared state?
3. How do you prevent this from re-accumulating?

**Red flags:** "Reorganize the code into more child modules" — doesn't address state/lock/blast-radius at all.

**Model answer:** *"Child modules don't create state boundaries, so reorganizing code alone wouldn't fix plan time, lock contention, or blast radius — all three are properties of the state itself. I'd design new boundaries around ownership, change frequency, and blast radius — likely a foundation/platform/per-application split — and migrate incrementally with `state mv`/`moved` blocks, verifying a zero-diff plan after every single resource before moving to the next, never a bulk migration."*

**Full reference:** [Question 15](../interview-questions/02-state-management.md#question-15-the-plan-that-took-twenty-minutes)

---

## Question 11
**Interviewer asks:** "How would you design CI concurrency controls, and why isn't the backend lock alone sufficient?"

**Expected answer points:**
- Backend lock is a correctness backstop, not a good UX — a losing pipeline just fails with a raw lock error.
- CI-level concurrency group per environment/state serializes runs before they even attempt the lock.
- `cancel-in-progress: false` is critical — cancelling an in-flight apply is worse than the lock error it's trying to avoid.

**Follow-up questions:**
1. What happens if you get `cancel-in-progress` wrong?
2. How does this scale to a matrix deploying to many accounts/regions?
3. How do you monitor if the queue itself becomes a bottleneck?

**Red flags:** "The backend lock already handles this, no CI-level change needed" — misses the UX/queueing distinction entirely.

**Model answer:** *"The backend lock is correct but blunt — the losing pipeline just fails with a raw error, which looks like a mysterious failure rather than expected contention. A CI-level concurrency group per environment queues the second run automatically instead, with the backend lock remaining as a defense-in-depth backstop for anything that bypasses the queue. `cancel-in-progress` has to stay false — cancelling an in-flight apply mid-run is a genuinely worse outcome than the lock error it would be trying to avoid."*

**Full reference:** [Question 72](../interview-questions/08-cicd.md#question-72-the-queue-nobody-could-see)

---

## Question 12
**Interviewer asks:** "You're about to release a major version of a widely-used RDS module changing several defaults. How do you prove it won't break your twenty-five consumers before shipping?"

**Expected answer points:**
- Module's own unit tests aren't sufficient — they don't reflect real consumer state.
- Contract testing: run the new version's plan against real (or representative) consumer configurations, checking specifically for unexpected replacement.
- Gate the release on this matrix passing cleanly.

**Follow-up questions:**
1. How do you keep the consumer fixture set representative over time?
2. What if one of twenty-five shows an unexpected replacement — does that block the whole release?
3. How does this scale to hundreds of consumers?

**Red flags:** "Run the module's test suite and ship if it passes" — conflates isolated unit testing with real-consumer-impact validation.

**Model answer:** *"The module's own tests validate its internal logic against synthetic fixtures, not whether real consumers' actual accumulated state reacts safely to the new version — that's a different question. I'd build a CI job pinning the new version against a representative sample of real consumer configurations, checking the resulting plan specifically for unexpected replacement operations, and block the release if any show up unexpectedly, investigating before proceeding."*

**Full reference:** [Question 30](../interview-questions/03-modules.md#question-30-proving-a-new-module-version-wont-break-anyone-before-you-ship-it)

---

## Question 13
**Interviewer asks:** "A legacy module was replaced two years ago but never formally deprecated, and a new hire just used it without knowing better. How do you fix this?"

**Expected answer points:**
- The failure is that deprecation was never visible at the point of discovery (the registry), only known informally.
- Add a real, prominent deprecation notice and sunset date; migrate the known consumers with a real deadline.
- Prevention: pair every future module replacement with a registry-level deprecation notice as standard practice.

**Follow-up questions:**
1. What if a consumer genuinely can't migrate by the sunset date?
2. How do you handle this if the legacy and replacement modules have very different underlying resources?
3. How do you build the habit organizationally so this doesn't recur?

**Red flags:** "Just tell people not to use it anymore" — the same informal-knowledge failure that already didn't work.

**Model answer:** *"The core failure is that nothing at the actual point of discovery — the registry — signaled this was deprecated; it was purely informal, team-internal knowledge a new hire had no access to. I'd add a prominent, registry-visible deprecation notice with a real sunset date and a migration guide, track the known consumers to completion, and establish as standing practice that every future module replacement ships with a deprecation notice on the old one in the same change, not as an afterthought."*

**Full reference:** [Question 34](../interview-questions/03-modules.md#question-34-sunsetting-the-module-nobody-was-supposed-to-still-be-using)

---

## Question 14
**Interviewer asks:** "A director asks why you can't just 'roll back Terraform' after a bad apply destroyed and recreated a production database, losing recent data. How do you explain this?"

**Expected answer points:**
- Terraform manages infrastructure shape, not data; reapplying old config creates a *new* resource, not a restoration.
- Quantify the actual data-loss window (last snapshot vs. incident time) to make the conversation concrete.
- Real recovery is a data-layer restoration (snapshot), separate from any config "rollback."
- Identify what should have prevented it (`prevent_destroy`, plan review) as the real preventive fix.

**Follow-up questions:**
1. How do you calibrate this expectation with stakeholders *before* an incident, not during one?
2. What's your actual recovery step here?
3. What's the durable prevention, not just the immediate fix?

**Red flags:** "We'll just revert the git commit and re-apply" presented as if it addresses the data loss.

**Model answer:** *"Terraform manages configuration, not data — reapplying the old config creates a new database with the old settings, it doesn't restore the specific rows that existed before. I'd frame this concretely for the director: here's the actual data-loss window between the last snapshot and the incident. The real recovery is restoring from that snapshot, and the actual prevention going forward is `prevent_destroy` on production stateful resources plus mandatory review of any plan showing an unexpected replace, not a 'rollback' that doesn't really exist for this class of change."*

**Full reference:** [Question 75](../interview-questions/08-cicd.md#question-75-cant-we-just-roll-it-back)

---

## Question 15
**Interviewer asks:** "Design an account-vending pipeline that turns a three-week manual account-provisioning process into something fast and consistent."

**Expected answer points:**
- Classifies manual steps as one-time/judgment (approve request) versus mechanical/repeatable (account creation, SCP attachment, state bootstrap, baseline IAM) — automates the latter.
- Deterministic, Terraform-driven pipeline producing an identical baseline every time.
- Automated conformance checks before handoff, not a human eyeballing it.

**Follow-up questions:**
1. How do you handle a business unit needing a different baseline?
2. What conformance checks specifically would you run?
3. How does this pipeline fail safely if it's interrupted partway?

**Red flags:** "Write a more detailed runbook so the manual steps are done consistently" — still fully manual, still inconsistent by construction.

**Model answer:** *"The three-week timeline and inconsistency are both symptoms of a fully manual process standing in for something deterministic. I'd separate genuinely one-time judgment calls (approving the request) from mechanical, repeatable steps (account creation, SCP attachment, state backend bootstrap, baseline IAM) and automate the latter entirely as one Terraform apply per new account, with automated conformance checks — not a human eyeballing it — gating handoff to the requesting team."*

**Full reference:** [Question 45](../interview-questions/05-aws-architecture.md#question-45-account-creation-shouldnt-be-a-ticket)

---

## Scoring Rubric Reference
- **3 (Senior):** Correct implementation, validation, rollback awareness — underperforming for this Lead-level interview if this is the ceiling.
- **4 (Lead):** Architecture trade-offs, team governance, scale awareness, preventive controls. **This is the passing bar for this interview.**
- **5 (Staff/Architect):** Connects to business risk, multi-team/account design, cost/compliance/HA/DR integration.

A candidate scoring 4+ consistently is ready for Lead Terraform Engineer roles. Consistent 5s suggest trying [Mock Interview 3](mock-interview-03-staff-platform-architect.md).
