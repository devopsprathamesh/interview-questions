# Mock Interview 1: Senior DevOps Engineer

**Format**: 15 questions, 60 minutes. **Focus**: Terraform operations and troubleshooting. **Level target**: Senior (score 3 on the rubric is a pass; 4-5 is exceeding expectations for this specific level).

Use the [Scoring Rubric](#scoring-rubric-reference) at the end for every question. Run this cold — resist the urge to look up answers mid-interview; that defeats the purpose of a mock.

---

## Question 1
**Interviewer asks:** "Two of your pipelines both try to apply against the same Terraform state within the same minute. Walk me through exactly what happens."

**Expected answer points:**
- One acquires the backend lock first; the second is rejected immediately with a clear error (lock holder, timestamp, operation).
- This is *not* corruption — it's the lock working correctly.
- The real risk is a process dying *while holding* the lock (stale lock), which needs human-verified `force-unlock`, never a reflexive one.
- Mentions CI-level concurrency groups as the better UX fix (queue instead of fail).

**Follow-up questions:**
1. What if the second pipeline's job doesn't retry — what would you build to fix that?
2. How would you tell a genuinely stale lock apart from a slow-but-still-running apply?
3. Does a saved plan file interact with lock timing at all?

**Red flags:** Says the state will get "corrupted" or "merged" — factually wrong. Suggests routinely using `-lock=false` to "avoid the hassle."

**Model answer:** *"Whichever operation acquires the lock first proceeds; the second fails fast with an error identifying who holds it. That's correct, safe behavior — it's not corruption. The actual risk is a process that dies while holding the lock, leaving it stale; recovering from that means confirming via CI job status that the original process is truly dead before running `force-unlock`, never on elapsed time alone. For the day-to-day annoyance of two pipelines racing, I'd add a CI-level concurrency group per environment so the second run queues cleanly instead of hitting a raw lock error."*

**Full reference:** [Question 11](../interview-questions/02-state-management.md#question-11-two-pipelines-one-state)

---

## Question 2
**Interviewer asks:** "A `terraform plan` against production shows a resource being replaced — destroyed and recreated — and nobody changed the configuration. What do you do?"

**Expected answer points:**
- Do not apply. Read the plan's `# forces replacement` annotation to find the specific attribute.
- Check if this followed a provider version bump (`init -upgrade`) — provider schema/ForceNew changes are the most common cause with no config change.
- Cross-reference the provider's CHANGELOG for that resource type.
- Pin back to the last-known-good provider version if this is unplanned and close to a release window.

**Follow-up questions:**
1. What if the CHANGELOG mentions nothing about this — what's your next step?
2. How would this differ if the resource were a database versus a stateless compute resource?
3. How do you prevent this from surprising you again on the next provider bump?

**Red flags:** Immediately applies "since Terraform must know what it's doing." Doesn't mention checking the provider version/CHANGELOG at all.

**Model answer:** *"First, I don't apply it. I read the plan's replacement reason for the specific attribute forcing it. If this followed a recent `init -upgrade`, that's my leading hypothesis — provider version bumps can change which attributes are ForceNew with zero change to my own config. I'd check the provider's CHANGELOG for that resource type, and if it's genuinely a new, intentional provider behavior, I'd test it in non-prod first before ever letting it touch a real database."*

**Full reference:** [Question 38](../interview-questions/04-providers.md#question-38-the-upgrade-that-arrived-at-the-worst-possible-time)

---

## Question 3
**Interviewer asks:** "When would `count` cause you a real problem that `for_each` wouldn't?"

**Expected answer points:**
- `count` uses positional identity; removing an item from the middle of a list shifts every subsequent index.
- This causes cascading destroy/recreate for every resource after the removed one, not just the one intended.
- `for_each` uses the map key as identity — removing one key only affects that one resource.
- Correctly identifies the legitimate use of `count` (the 0/1 conditional idiom).

**Follow-up questions:**
1. How would you migrate an existing `count`-based resource set to `for_each` without recreating anything?
2. Is there a case where `count` is still the right choice?
3. What's the actual mechanism inside Terraform that causes the shift?

**Red flags:** Says "just always use for_each, count is bad" without explaining the actual mechanism or the 0/1 idiom exception.

**Model answer:** *"`count` gives each instance a positional index as its identity. If I remove the first item from a six-item list, index 0 doesn't get destroyed and the rest left alone — every index shifts down, so Terraform thinks the configuration for every one of those addresses changed, and replaces all of them. `for_each` keys by a stable identifier instead, so removing one key only touches that one resource. I still use `count` for the 0/1 conditional-resource pattern, where there's no real identity question at all."*

**Full reference:** [Question 1](../interview-questions/01-terraform-core.md#question-1-the-subnet-that-shifted)

---

## Question 4
**Interviewer asks:** "Walk me through what actually happens, internally, between running `terraform plan` and `terraform apply`."

**Expected answer points:**
- Plan: load config, build the dependency graph, refresh state (read real-world values), diff against config, produce a plan (possibly saved to a file).
- Apply: re-validates a saved plan's state serial/lineage if provided; walks the graph, calling provider RPCs in dependency order, with independent branches in parallel; writes state incrementally after each resource operation.
- Mentions unknown values propagating for anything depending on a not-yet-created resource.

**Follow-up questions:**
1. What happens if I apply a saved plan file against a state that changed in the meantime?
2. Why does state get written after every resource instead of once at the end?
3. What determines how many resources apply in parallel?

**Red flags:** Describes it as "top to bottom" execution with no mention of the graph or parallelism.

**Model answer:** *"Plan builds a dependency graph from the config, refreshes existing resources' real state, and diffs that against the desired config to produce create/update/destroy/no-op decisions per resource — with unknown values propagating for anything depending on a resource not created yet. Apply walks that same graph, executing independent branches in parallel up to the parallelism limit, and writes state after each individual resource operation succeeds — that incremental write is exactly why a killed apply still leaves an accurate picture of what succeeded."*

**Full reference:** [`docs/terraform-internals.md`](../docs/terraform-internals.md)

---

## Question 5
**Interviewer asks:** "Your CI pipeline fails with a state lock error and the message says the lock has been held for six hours, but your applies normally take ten minutes. What now?"

**Expected answer points:**
- Confirm via CI job history that the process that acquired the lock actually terminated/failed.
- Cross-reference the elapsed time against typical apply duration as corroborating (not sole) evidence.
- Only then `terraform force-unlock <ID>`.
- Plan (not apply) immediately after, to check for a partial-apply situation.

**Follow-up questions:**
1. What if the CI job actually shows as still running — what would that mean?
2. Why is forcing an unlock on a genuinely-active process dangerous?
3. How do you prevent this exact situation recurring?

**Red flags:** Jumps straight to `force-unlock` with no verification step at all.

**Model answer:** *"Six hours against a normal ten-minute apply is strong evidence of a stale lock, but I verify before acting — check the CI platform's job history for that specific run to confirm it actually died rather than assuming from the time alone. Once confirmed, I force-unlock using the exact lock ID from the error, and immediately run plan — not apply — to check whether the interrupted run left anything half-applied that needs investigation before proceeding."*

**Full reference:** [Question 12](../interview-questions/02-state-management.md#question-12-the-lock-that-would-not-die)

---

## Question 6
**Interviewer asks:** "You discover an S3 bucket in AWS that matches your naming convention but isn't in Terraform state at all. How do you handle it?"

**Expected answer points:**
- Confirm it's genuinely unmanaged, not a state-loss situation (check `state list`).
- Use an `import` block (with `-generate-config-out` if no matching config exists) rather than hand-writing config and importing blind.
- Never let `apply` proceed against config that would try to create a duplicate.
- Validate with a zero-diff plan after import.

**Follow-up questions:**
1. What if the bucket's actual settings don't match any existing module's assumptions?
2. How do you find the correct import ID format for a resource type you've never imported before?
3. What's your prioritization if there are fifty such orphaned resources, not one?

**Red flags:** Suggests deleting and recreating it "to get it under Terraform properly."

**Model answer:** *"First I confirm it's genuinely unmanaged — check state list, don't assume. Then I use an import block, ideally with `-generate-config-out` if I don't already have matching configuration, so Terraform drafts the config for me instead of me guessing at its current settings. After importing, I run plan and expect zero changes — any diff there means either my drafted config is wrong or there's drift I need to understand before calling this done."*

**Full reference:** [Question 92](../interview-questions/10-troubleshooting.md#question-92-the-import-that-needed-three-tries-to-get-the-id-right)

---

## Question 7
**Interviewer asks:** "A production RDS instance has `prevent_destroy = true`. The application it serves is being decommissioned and the database genuinely needs to go. Walk me through it."

**Expected answer points:**
- `prevent_destroy` is a Terraform-Core plan-time guard only — no AWS-side effect.
- Never bypass via `state rm` + manual deletion.
- Two-step: remove the lifecycle guard in one reviewed commit (no-op plan), then remove/`removed`-block the resource in a second step, verifying the plan shows exactly the intended destroy.
- Take a final snapshot before applying the destroy.

**Follow-up questions:**
1. Why does removing `prevent_destroy` alone not immediately destroy anything?
2. What if another team's Terraform references this database's endpoint?
3. What's genuinely irreversible about this action even with a snapshot?

**Red flags:** Suggests `terraform state rm` followed by a manual console delete as the fix.

**Model answer:** *"`prevent_destroy` only blocks Terraform's own plan/apply from proposing a destroy — it has zero effect on a manual deletion, which is exactly why I'd never route around it that way. The safe path is two separate, reviewed steps: first remove the lifecycle guard alone and confirm the plan is a no-op, then remove the resource block (or use a removed block) and confirm the plan shows exactly the one intended destroy. I'd also take a final manual snapshot immediately before applying, since this is irreversible regardless of how careful the process is."*

**Full reference:** [Question 3](../interview-questions/01-terraform-core.md#question-3-decommissioning-a-prevent_destroy-protected-resource)

---

## Question 8
**Interviewer asks:** "What's the difference between using `terraform_remote_state` and reading another team's output via an SSM parameter, and when would you use each?"

**Expected answer points:**
- `terraform_remote_state` requires direct read access to the producer's entire state object; couples the consumer to the producer's backend/access model.
- SSM (or similar) decouples entirely — the producer publishes specific, stable values; the consumer never touches the producer's state at all.
- `terraform_remote_state` is more acceptable within the same team/tightly-coupled configs; SSM (or equivalent) is preferred across team/ownership boundaries.

**Follow-up questions:**
1. What's the actual failure mode `terraform_remote_state` introduces that SSM avoids?
2. How would you version a breaking change to a published SSM parameter?
3. Is there a scale at which `terraform_remote_state` becomes clearly wrong even within one team?

**Red flags:** Doesn't know what `terraform_remote_state` actually requires access-wise, or treats them as interchangeable with no trade-off.

**Model answer:** *"`terraform_remote_state` means the consumer needs direct read access to the producer's entire state object, and any interruption to that — an access change, a backend outage — breaks every consumer's plan even if nothing they need actually changed. Publishing specific values to SSM Parameter Store instead means consumers never touch the producer's state at all; the producer can restructure its own state freely as long as the published parameters stay stable. I'd use SSM across any real team/ownership boundary, and reserve remote_state for tightly-coupled configs within the same team."*

**Full reference:** [Question 16](../interview-questions/02-state-management.md#question-16-the-outage-that-started-in-someone-elses-state)

---

## Question 9
**Interviewer asks:** "A teammate meant to apply to staging but their local AWS profile was still pointed at production, and the apply succeeded there instead. What actually happened, and how do you prevent it?"

**Expected answer points:**
- Terraform's target is entirely determined by resolved credentials at run time, not intent or workspace name.
- Immediate: assess what was created in production, don't assume it's benign.
- Structural fix: production applies should be unreachable from any locally-available credential — OIDC-only, CI-only role trust.
- Reminders/"be careful" is not a fix.

**Follow-up questions:**
1. Why isn't a workspace-based setup sufficient to prevent this?
2. What would you check first to assess the blast radius?
3. How would you retrofit this fix across every environment, not just this one?

**Red flags:** Answer is "we should remind people to double check their AWS profile."

**Model answer:** *"Terraform doesn't know what the engineer intended — it just uses whatever credentials are resolved at run time, so a stale local profile silently redirects the whole apply. First I'd assess exactly what got created in production and whether it's safely reversible. But the real fix isn't a reminder — it's making production unreachable from any human-assumable credential at all, only reachable via OIDC from the CI pipeline. That makes this class of mistake structurally impossible, not just less likely."*

**Full reference:** [Question 89](../interview-questions/10-troubleshooting.md#question-89-the-apply-that-hit-the-wrong-account)

---

## Question 10
**Interviewer asks:** "An apply is killed halfway through by a CI runner failure. What's your recovery process?"

**Expected answer points:**
- State is written incrementally, so it accurately reflects what succeeded — but verify, don't assume.
- Resolve any stale lock first.
- `state list` + cloud console cross-check against what the original apply intended.
- `plan` first, read it carefully, then apply — never blind-retry.

**Follow-up questions:**
1. Why might state and cloud reality still briefly disagree even with incremental writes?
2. What would make you decide NOT to just resume the apply?
3. How would you prevent this class of interruption from being this disruptive in the future?

**Red flags:** "Just re-run the pipeline, Terraform will figure it out" with no verification step.

**Model answer:** *"State is written after every successful resource operation, so it should accurately reflect what completed — but I verify that rather than assume it, especially given a killed process is exactly the scenario most likely to expose a rare edge case. I'd resolve any stale lock first, compare state list and the cloud console against what the original apply intended, then run a fresh plan and read it carefully before applying — a partial apply often resumes cleanly, but I want to see that in the plan, not assume it."*

**Full reference:** [Question 7](../interview-questions/01-terraform-core.md#question-7-the-apply-that-died-halfway-through-a-data-migration)

---

## Question 11
**Interviewer asks:** "You bump the AWS provider version as routine maintenance and suddenly a load balancer target group wants to be replaced. Nothing in your `.tf` files changed. Explain what's happening."

**Expected answer points:**
- Provider version bumps can change ForceNew markings, defaults, or normalization for specific attributes, independent of any config change.
- Investigate via the plan's replacement reason plus the provider's CHANGELOG for that resource type and version range.
- Pin back if this wasn't planned/tested, especially near a release window.

**Follow-up questions:**
1. How would you test a provider upgrade safely before it ever reaches production?
2. What's the actual mechanism that lets a provider bump change replacement behavior?
3. Should routine `init -upgrade` even be part of "maintenance," or something else?

**Red flags:** Assumes it must be a bug and reports it upstream without investigating first.

**Model answer:** *(See Question 2 above — same underlying mechanism.)* "This is a provider schema change, not a config change — a version bump can alter which attributes are ForceNew or how a value is normalized. I'd check the CHANGELOG for that specific resource type between the two versions, and treat any provider bump as its own reviewed change with a full plan-diff review in non-prod, never bundled silently into routine maintenance."

**Full reference:** [Question 38](../interview-questions/04-providers.md#question-38-the-upgrade-that-arrived-at-the-worst-possible-time)

---

## Question 12
**Interviewer asks:** "Your team has started using `-target` on almost every apply because the full plan is slow. What's your take?"

**Expected answer points:**
- `-target` narrows Terraform's evaluated graph — it doesn't just apply faster, it evaluates *less*, silently missing pending changes elsewhere.
- Legitimate for narrow emergency use, always followed by a full plan to confirm nothing was missed.
- The actual problem (slow plans) needs a real fix — profiling, narrowing slow data sources, or state splitting — not a permanent workaround.

**Follow-up questions:**
1. What would you actually check to speed up the full plan instead?
2. What accumulates silently if a team keeps doing this for months?
3. When is `-target` actually the right tool?

**Red flags:** "`-target` is fine as long as you know what you're targeting" — misses the hidden-inconsistency risk entirely.

**Model answer:** *"Routine `-target` use is a red flag — it's not just a faster version of a full plan, it's an incomplete one, since it never evaluates whatever's outside the targeted resource's dependency chain. Used routinely, that accumulates hidden inconsistency that eventually surfaces as a confusing incident. I'd fix the actual slow-plan problem instead — profile where the time is going, since it's often one or two slow data sources or a state that's outgrown its boundaries — and reserve `-target` for genuine narrow emergencies, always followed immediately by a full plan."*

**Full reference:** [Question 106](../interview-questions/12-performance-scale.md#question-106-the--target-habit-nobody-wanted-to-break)

---

## Question 13
**Interviewer asks:** "A configuration with about 600 resources takes four minutes to plan even for a one-line tag change. What do you check first?"

**Expected answer points:**
- Profile before prescribing a fix — don't jump straight to state-splitting.
- Look for a small number of disproportionately slow data sources or resource types, not assume it's evenly distributed across all 600.
- Only escalate to architectural state-splitting if profiling rules out a narrower fix.

**Follow-up questions:**
1. What tool/flag would you actually use to profile this?
2. At what point would you conclude state-splitting really is warranted?
3. Would you ever recommend `-refresh=false` as a fix here?

**Red flags:** Jumps immediately to "split the state" without any profiling step.

**Model answer:** *"I wouldn't jump straight to splitting the state — I'd profile first, since plan time is often dominated by a small number of unusually slow data sources or resource types, not evenly spread across all 600. `TF_LOG=debug` timing analysis usually reveals the actual bottleneck. If it turns out the slowness really is evenly distributed and resource count is the genuine driver, that's when a state redesign becomes the right call — but I'd rule out the cheaper fix first."*

**Full reference:** [Question 105](../interview-questions/12-performance-scale.md#question-105-the-one-line-change-that-took-four-minutes-to-plan)

---

## Question 14
**Interviewer asks:** "Your remote state backend's bucket had an outage mid-write and now `terraform plan` fails to parse the state file. Walk me through recovery."

**Expected answer points:**
- Don't hand-edit the JSON.
- Preserve the corrupted version for forensics first.
- Restore the last known-good version from the backend's own version history (S3 versioning).
- Plan carefully afterward — a restored-but-slightly-stale state is expected to show some diff; reconcile deliberately.

**Follow-up questions:**
1. What if versioning wasn't enabled on the bucket?
2. How do you confirm the restored version is genuinely the right one, not just the most recent?
3. What's the very first thing you check before doing anything else?

**Red flags:** "Open the file and fix the JSON by hand."

**Model answer:** *"First, I preserve the corrupted state for forensics rather than touching it further. Then I check the bucket's version history for the last version that parses as valid JSON — restoring from there rather than attempting a manual repair, since a hand-fixed file might parse successfully but be semantically wrong. After restoring, I run plan and expect it to show whatever real work happened since that version — that's normal, and I'd reconcile it deliberately rather than being alarmed by it."*

**Full reference:** [Question 13](../interview-questions/02-state-management.md#question-13-the-state-file-that-stopped-making-sense)

---

## Question 15
**Interviewer asks:** "You've just joined a team and inherited a Terraform codebase with zero documentation, no README, and the person who wrote most of it has left. What's your first week look like?"

**Expected answer points:**
- Read before touching: understand existing conventions, don't assume they're wrong just because undocumented.
- Audit for acute risk first (state security, credentials) — separate from broader understanding.
- Build your own understanding via `terraform state list`, `terraform graph`, and reading actual applied history (`git log`), not guesswork.
- Don't rewrite/restandardize immediately — earn context first.

**Follow-up questions:**
1. What's the very first command you'd run against this codebase?
2. How would you tell which conventions are load-bearing versus accidental?
3. What would make you decide something genuinely needs fixing right away versus waiting?

**Red flags:** "I'd rewrite it properly using best practices" without any discovery/audit phase first.

**Model answer:** *"I wouldn't start rewriting — I'd start reading. `terraform state list` and `git log` on the actual configuration tell me what's really there and how it evolved, which is more reliable than assuming from the code alone. In parallel, I'd audit specifically for acute risk — state bucket security, any long-lived credentials — since those are worth fixing regardless of broader conventions. Only once I understand what's load-bearing versus accidental would I propose any real changes, and even then, incrementally."*

**Full reference:** [Question 118](../interview-questions/15-leadership-design.md#question-118-youre-the-first-terraform-hire)

---

## Scoring Rubric Reference
- **1 (Beginner):** Definitions only, no production experience, no failure handling.
- **2 (Intermediate):** Understands normal implementation, limited troubleshooting, weak security/scale awareness.
- **3 (Senior):** Explains production implementation, covers validation and rollback, understands state/security/maintainability. **This is the passing bar for this interview.**
- **4 (Lead):** Explains architecture trade-offs, covers team governance and scale, anticipates failure modes, offers preventive controls.
- **5 (Staff/Architect):** Connects technical choices to business risk, designs for multiple teams/accounts, covers blast radius/security/cost/compliance/HA/DR.

For this Senior-level mock, a candidate consistently scoring 3+ across all 15 questions is interview-ready for Senior DevOps Engineer roles. Consistent 4s suggest readiness for Lead-level interviews — try [Mock Interview 2](mock-interview-02-lead-terraform-engineer.md) next.
