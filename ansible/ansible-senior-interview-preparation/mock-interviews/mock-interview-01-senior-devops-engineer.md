# Mock Interview 1: Senior DevOps Engineer

**Format**: 15 questions, 60 minutes. **Focus**: Ansible operations and troubleshooting. **Level target**: Senior (score 3 on the rubric is a pass; 4-5 is exceeding expectations for this specific level).

Use the [Scoring Rubric](#scoring-rubric-reference) at the end for every question. Run this cold — resist the urge to look up answers mid-interview; that defeats the purpose of a mock.

---

## Question 1
**Interviewer asks:** "A playbook using `command: mkdir /opt/app` reports `changed: true` on every single run, even though the directory already exists after the first run. What's going on, and how do you fix it?"

**Expected answer points:**
- `command`/`shell` are not idempotent by design — Ansible has no way to know a `mkdir` "succeeded because it was already done" versus "did real work."
- The correct fix is the purpose-built `ansible.builtin.file` module (`state: directory`), which is idempotent natively.
- If `command`/`shell` is genuinely unavoidable, `creates:`/`changed_when` are the fallback guards.

**Follow-up questions:**
1. Why does Ansible ship `command`/`shell` at all if they're not idempotent?
2. What's the risk of over-relying on `changed_when: false` as a blanket fix?
3. How would you audit an existing playbook library for this exact pattern?

**Red flags:** Says "just add `ignore_errors: true`" — treats the symptom, not the cause, and hides real failures too.

**Model answer:** *"Idempotency in Ansible is a contract you write, not something the platform guarantees for every module — `command` and `shell` execute a literal command with no before/after state comparison, so Ansible can't know whether `mkdir` did anything or was a no-op. The fix here is `ansible.builtin.file` with `state: directory`, which checks actual state first and only acts if needed. If I genuinely need `command`, I'd add `creates: /opt/app` so it skips entirely once the target exists."*

**Full reference:** [Question 1](../interview-questions/01-ansible-core.md#question-1-the-playbook-that-broke-on-the-second-run)

---

## Question 2
**Interviewer asks:** "A handler notified by an early task never seems to run when a later task in the same play fails. Why, and how do you fix it?"

**Expected answer points:**
- Handlers are deferred and only flushed at the end of the play (or an explicit `meta: flush_handlers`).
- If an earlier task fails before the play reaches its end, queued handlers never fire at all.
- Fix: add an explicit `meta: flush_handlers` immediately after the notifying task if the handler's effect is time-sensitive, or restructure task ordering.

**Follow-up questions:**
1. What's the risk of flushing handlers too aggressively (after every single task)?
2. How would you test for this specific failure mode before it hits production?
3. Does `serial` change this behavior at all?

**Red flags:** Says handlers run "immediately" after being notified — fundamentally wrong about the deferred-execution model.

**Model answer:** *"Handlers are queued, not executed immediately — they only run once, at the end of the play, or at an explicit `meta: flush_handlers`. If a later task in the same play fails first, the play stops before reaching that flush point, and the queued handler simply never runs — with no error indicating it was skipped. If the handler's effect is time-sensitive, I'd add an explicit flush right after the task that notifies it, rather than trusting the end-of-play default timing."*

**Full reference:** [Question 2](../interview-questions/01-ansible-core.md#question-2-the-restart-that-never-happened)

---

## Question 3
**Interviewer asks:** "Your team debates `for_each`-equivalent looping with `loop` versus `with_items` — but more importantly, a loop over a list of dicts silently processes half the expected items after a recent change. What's your first diagnostic step?"

**Expected answer points:**
- Check whether the loop variable itself was replaced (not merged) by a higher-precedence source — a common Ansible list-variable trap.
- List variables fully replace, never merge, across precedence levels — unlike dict variables' `hash_behaviour` (which itself defaults to replace too, but is a separate, common confusion).
- Fix: confirm the actual source of truth for the loop's list at the point of execution via `ansible.builtin.debug`.

**Follow-up questions:**
1. How does this differ from how dictionary variables combine across precedence levels?
2. What's `hash_behaviour` and why is changing it globally risky?
3. How would you defensively guard against this in a shared role?

**Red flags:** Assumes lists merge across `group_vars`/`host_vars` levels by default — they don't, and this misconception is exactly the bug's root cause.

**Model answer:** *"List variables fully replace at the winning precedence level — they never merge across `group_vars`/`host_vars`/role defaults. If a more specific variable source defines a shorter version of the same list, that shorter list simply wins outright, and the loop silently processes only what's in it. I'd debug-print the actual resolved variable right before the loop runs to confirm which source is winning, rather than assuming the full list I expect is what's actually there."*

**Full reference:** [Question 3](../interview-questions/01-ansible-core.md#question-3-the-loop-that-quietly-skipped-half-its-work)

---

## Question 4
**Interviewer asks:** "You need to run a fleet-wide patch across 2,000 hosts, and it's currently taking 40 minutes for a change that should take seconds per host. What do you check first?"

**Expected answer points:**
- `forks` (default 5) is almost certainly the bottleneck — low default concurrency against a large fleet.
- Increase `forks` substantially, informed by control-node capacity testing.
- Secondary levers: execution strategy (`linear` vs `free`), fact-gathering scope, SSH pipelining.

**Follow-up questions:**
1. How would you determine a safe upper bound for `forks`?
2. What's the relationship between `forks` and execution strategy?
3. What else besides `forks` would you check if increasing it alone didn't fully explain the slowness?

**Red flags:** Jumps straight to "optimize the playbook's tasks" without checking concurrency first — for this symptom pattern, `forks` is nearly always the dominant factor.

**Model answer:** *"With 2,000 hosts and the default `forks=5`, Ansible is processing the fleet in roughly 400 sequential batches of 5 — that alone explains a disproportionate runtime for a trivial per-host change. I'd increase `forks` substantially, validated incrementally against the control node's actual capacity, and I'd also check whether fact-gathering is unnecessarily broad and whether SSH pipelining is enabled — both compound at this scale."*

**Full reference:** [Question 8](../interview-questions/01-ansible-core.md#question-8-the-fleet-that-took-forty-minutes-to-patch-one-line)

---

## Question 5
**Interviewer asks:** "A `block`/`rescue` structure catches a failure and the play reports success — but a teammate says something 'serious' happened. How do you reconcile this?"

**Expected answer points:**
- A completing `rescue` block makes the play report success, *regardless of how serious the original failure was* — Ansible has no concept of "serious" vs. "benign" failure unless the rescue logic explicitly checks.
- Fix: inspect `ansible_failed_result` inside `rescue` and only continue gracefully for the specific, expected failure; re-raise anything else via `ansible.builtin.fail`.

**Follow-up questions:**
1. Why doesn't Ansible expose failure severity as a first-class concept?
2. How would you test that a rescue block only catches what it's meant to?
3. What's the risk of a rescue block that's too narrowly scoped?

**Red flags:** Says "rescue means it's handled, so it's fine" — misses that this is exactly the danger the question is probing.

**Model answer:** *"A `rescue` completing successfully makes the whole play report success, even if the underlying failure was genuinely serious — Ansible has no built-in distinction between an expected, benign failure and a critical one; that's entirely up to what the rescue logic itself checks. I'd inspect `ansible_failed_result.msg` inside the rescue and only continue gracefully for the one specific, anticipated failure string, explicitly re-raising anything else with `ansible.builtin.fail` so it can't be silently swallowed."*

**Full reference:** [Question 6](../interview-questions/01-ansible-core.md#question-6-the-block-that-recovered-silently)

---

## Question 6
**Interviewer asks:** "`ansible-playbook --check --diff` shows no changes, but a real run against the same hosts shows several. How is that possible?"

**Expected answer points:**
- Check mode has a well-known blindness for `command`/`shell` and any module that doesn't explicitly support check mode — it can't simulate their effect, so it may report nothing or a misleading result.
- Some modules also behave differently under check mode for genuinely conditional logic.
- Never treat a clean `--check` as proof nothing will change for a playbook using `command`/`shell` extensively.

**Follow-up questions:**
1. How would you identify which specific tasks in a playbook are check-mode-unsafe?
2. What's `check_mode: no` used for, and is it ever appropriate?
3. How would you build confidence in a risky change without fully trusting `--check`?

**Red flags:** Says "check mode always accurately previews reality" — this is the exact misconception the question is testing for.

**Model answer:** *"Check mode's biggest blind spot is `command`/`shell` tasks — Ansible has no way to simulate what an arbitrary shell command would actually do, so it either skips reasoning about it or reports something that doesn't reflect real execution. I never treat a clean `--check --diff` as proof of no changes for any playbook using `command`/`shell` — I'd specifically audit which tasks fall into that category and validate those separately, maybe in a non-production dry run instead."*

**Full reference:** [Question 7](../interview-questions/01-ansible-core.md#question-7-the-check-mode-run-that-lied)

---

## Question 7
**Interviewer asks:** "A play targeting a specific tag-based host group matches zero hosts, with no error. What happened, and how do you prevent it from happening silently again?"

**Expected answer points:**
- A typo'd tag name, a renamed tag, or a filter mismatch produces a legitimate, silent zero-host match — not an Ansible bug.
- `ansible-inventory --graph` is the definitive check for what a given pattern actually resolves to.
- Prevention: an explicit `assert` guarding against a zero-host match before any mutating task runs.

**Follow-up questions:**
1. How would you build this guard into every playbook systematically, not just this one?
2. What's the difference between this and a `--limit` typo?
3. How would this scenario be different against a static versus dynamic inventory?

**Red flags:** Assumes Ansible would automatically error on a zero-host match — it doesn't, by default, and that's precisely the danger.

**Model answer:** *"A zero-host match is a legitimate, silent outcome — Ansible doesn't treat it as an error by default, it just runs the play against nothing. The likely cause is a stale or mistyped tag reference, easily confirmed with `ansible-inventory --graph` to see exactly what the pattern resolves to right now. Going forward, I'd add a standard, reusable guard — an `assert` checking the target group has at least one host — as an early task in any pattern-targeted play, so this fails loudly instead of silently doing nothing."*

**Full reference:** [Question 11](../interview-questions/02-inventory-variables.md#question-11-the-play-that-matched-zero-hosts)

---

## Question 8
**Interviewer asks:** "A role's behavior is different than documented, and you find the actual value comes from the role's own `vars/main.yml`, not `defaults/main.yml`, which nobody could override from the calling playbook. Why does this happen?"

**Expected answer points:**
- `vars/main.yml` has *higher* precedence than role `defaults/main.yml` — a common, easy-to-miss confusion.
- `defaults` are meant to be the overridable interface; `vars` are role-internal constants.
- Fix: move genuinely-overridable values to `defaults`, reserving `vars` for values that should never be overridden lightly.

**Follow-up questions:**
1. Where does `-e` (extra-vars) sit relative to both of these?
2. How would you document this distinction for a team new to role design?
3. What's `argument_specs.yml`'s role in preventing this confusion?

**Red flags:** Assumes `defaults` always wins over `vars` — exactly backwards, and the root of the bug in this scenario.

**Model answer:** *"Role `vars/main.yml` sits at a higher precedence than role `defaults/main.yml` — the opposite of what the naming intuitively suggests. `defaults` is the intended, overridable interface; anything in `vars` will silently win over a calling playbook's `group_vars`/`host_vars` attempt to override it. The fix is moving the value that's meant to be configurable into `defaults`, and reserving `vars` only for genuinely role-internal constants that shouldn't be casually overridden."*

**Full reference:** [Question 12](../interview-questions/02-inventory-variables.md#question-12-the-role-that-couldnt-be-overridden)

---

## Question 9
**Interviewer asks:** "You need to make an existing, widely-used role support a new optional feature without breaking any of its current thirty consumers. How do you design the change?"

**Expected answer points:**
- Add the new capability behind a new variable with a safe, backward-compatible default (off/unchanged behavior).
- Never rename an existing variable outright without a deprecation-aliasing period.
- Validate against a representative sample of existing consumers before publishing the new version.

**Follow-up questions:**
1. How would you communicate this change to the thirty consuming teams?
2. What's a deprecation-aliasing pattern look like in practice?
3. How would Molecule testing factor into validating this change is genuinely non-breaking?

**Red flags:** Proposes renaming/restructuring existing variables directly "since it's cleaner" — ignores the blast radius across thirty consumers.

**Model answer:** *"I'd add the new capability as an entirely new, optional variable defaulting to the current, unchanged behavior — so every existing consumer's behavior is completely unaffected unless they deliberately opt in. If this ever required renaming something existing, I'd use a deprecation-aliasing pattern instead of a hard rename — accepting both the old and new variable names for a transition period, with a warning on the old one. Before publishing, I'd validate against a representative sample of real consumer configurations, not just my own test scenario."*

**Full reference:** [Question 32](../interview-questions/03-roles-collections.md#question-32-adding-a-feature-without-breaking-anyone)

---

## Question 10
**Interviewer asks:** "A playbook run against a large, dynamically-resolved AWS inventory takes 90 seconds just to resolve inventory, before any task runs. What's your diagnosis?"

**Expected answer points:**
- Without caching, every account/region combination is queried fresh on every single invocation.
- Enable inventory-level caching (`cache: true`) with an appropriate TTL.
- Consider scoping the inventory source itself if the playbook never needs the full breadth resolved.

**Follow-up questions:**
1. What's the staleness risk of enabling caching, and how would you balance it?
2. How would you distinguish this from a genuine AWS API throttling issue?
3. What's the relationship between this and the `--limit` flag?

**Red flags:** Assumes the playbook's own tasks are slow without first checking whether inventory resolution (a separate phase) is the actual bottleneck.

**Model answer:** *"This is very likely inventory resolution itself, not the playbook's tasks — without caching, every account/region combination in the dynamic inventory source gets queried fresh on every single run, and that compounds quickly across many combinations. I'd enable inventory-level caching with a TTL matched to how quickly the underlying fleet actually changes, and if this playbook only ever targets a narrow subset, I'd also consider scoping the inventory source itself rather than resolving everything just to `--limit` down afterward."*

**Full reference:** [Question 49](../interview-questions/05-aws-cloud-integration.md#question-49-the-inventory-query-that-got-throttled)

---

## Question 11
**Interviewer asks:** "A team stores their Ansible Vault password in a plaintext file committed to a private repository, arguing the repo's own access control is sufficient protection. Do you agree?"

**Expected answer points:**
- No — repository access control is a coarser, less auditable protection than a genuine secrets manager, and Git history retains the password even after a later removal.
- Correct fix: a vault-password script dynamically fetching from AWS Secrets Manager (or equivalent), never a static committed file.
- Treat an already-exposed password as compromised, requiring rotation.

**Follow-up questions:**
1. What specifically does a vault-password script provide that a static file doesn't?
2. How would you determine if a Git-history purge is warranted versus just rotating going forward?
3. How would you audit for other instances of this same anti-pattern?

**Red flags:** Agrees that "private repo" is sufficient — this is precisely the flawed reasoning the question is testing for.

**Model answer:** *"No — 'the repo is private' conflates repository-hosting access control with genuine secrets management. Anyone with repo access, now or historically (since Git retains history even after a file is removed), has full access to every vault-encrypted secret. I'd replace the static file with a vault-password script fetching dynamically from AWS Secrets Manager, and treat the already-exposed password as compromised — rotating it and re-encrypting, not just fixing the process going forward."*

**Full reference:** [Question 61](../interview-questions/07-security-vault.md#question-61-the-vault-password-that-was-itself-the-vulnerability)

---

## Question 12
**Interviewer asks:** "A `no_log: true` task's failure still shows a sensitive token in plaintext in the error output. Is `no_log` broken?"

**Expected answer points:**
- No — `no_log` suppresses Ansible's own normal task-result output; it doesn't control what a module's own internally-constructed exception message includes.
- This is a scoped limitation, not a bug — verify via a deliberate failure test, don't assume complete coverage.
- Fix: for a custom module, avoid embedding sensitive values in exception messages; for a third-party module, check for a fix or add a log-aggregation-level redaction backstop.

**Follow-up questions:**
1. What's the actual mechanism by which `no_log` suppresses output?
2. How would you test every sensitive-data-handling task's failure path as standard practice?
3. What's a reasonable defense-in-depth backstop beyond `no_log` alone?

**Red flags:** Insists `no_log` is broken/buggy rather than recognizing its scoped, documented limitation.

**Model answer:** *"`no_log` isn't broken — it's scoped to Ansible's own normal result/logging output, substituted with a 'censored' placeholder at the framework layer. It has no control over a module's own internally-raised exception message if that module embeds a sensitive value directly into an error string — a different code path entirely. I'd never assume `no_log` alone is sufficient for a genuinely sensitive task without deliberately testing its failure path specifically."*

**Full reference:** [Question 62](../interview-questions/07-security-vault.md#question-62-the-no_log-that-logged-anyway)

---

## Question 13
**Interviewer asks:** "Your team's drift-detection playbook, running nightly in `--check` mode, has reported 'no drift' for a year — but a manual audit finds significant real drift. What's going on?"

**Expected answer points:**
- `--check` mode's 'no changes' result only reflects what the playbook's own tasks actually manage — anything outside that scope (manually-installed packages, hand-edited files never brought under management) is entirely invisible to the check.
- Fix: expand task coverage to explicitly manage whatever matters for compliance, and treat 'clean drift report' as scoped, not absolute.

**Follow-up questions:**
1. How would you systematically identify what's currently unmanaged but should be?
2. What's the difference between this and a genuinely broken check-mode task?
3. How does this affect your confidence in any drift-detection job generally?

**Red flags:** Concludes "the fleet must be fully consistent" from a clean drift report alone, without questioning the report's actual scope.

**Model answer:** *"A clean `--check` result only proves 'nothing the playbook's own tasks manage has drifted' — it says nothing about configuration entirely outside that scope, like a manually-installed package or a hand-edited file the playbook never had a task for in the first place. I'd review the playbook's actual task coverage against the real, full configuration surface of the hosts, and bring anything that matters for compliance under explicit management — treating a clean drift report as scoped to what's actually checked, never as absolute proof of consistency."*

**Full reference:** [Question 75](../interview-questions/08-cicd-automation.md#question-75-the-drift-detection-job-that-never-detected-anything)

---

## Question 14
**Interviewer asks:** "A pod-equivalent scenario: your team wants to write an Ansible role that continuously reconciles application state on a Kubernetes cluster, on a schedule. Good idea?"

**Expected answer points:**
- No — this reinvents, poorly, what a GitOps controller (ArgoCD/Flux) already does natively and continuously.
- Ansible has no persistent, event-driven reconciliation loop; a scheduled playbook leaves a drift window between runs.
- Ansible's legitimate role is bootstrapping the cluster/foundational add-ons, then handing off ongoing management.

**Follow-up questions:**
1. Where does Ansible's role legitimately end once Kubernetes is involved?
2. What's the actual difference in guarantee between a scheduled playbook and a GitOps controller?
3. How would you communicate this to a team wanting to use a familiar tool?

**Red flags:** Endorses the idea "since the team already knows Ansible" without weighing the structural gap against a purpose-built GitOps controller.

**Model answer:** *"I'd push back — a scheduled Ansible playbook reinvents, less effectively, what a GitOps controller already does as a continuous, event-driven reconciliation loop with built-in drift correction and sync-status visibility. Ansible has no persistent process watching cluster state between runs, so there's always a drift window up to the full schedule interval. Ansible's legitimate role here is bootstrapping the cluster and its foundational add-ons — ongoing application deployment should hand off to a real GitOps controller."*

**Full reference:** [Question 53](../interview-questions/06-kubernetes-containers.md#question-53-the-playbook-that-wanted-to-run-the-whole-platform)

---

## Question 15
**Interviewer asks:** "You're new to a team and inherit a large Ansible codebase with no documentation and the original author gone. What's your first week look like?"

**Expected answer points:**
- Read and audit before rewriting — understand existing conventions before assuming they're wrong.
- Prioritize acute-risk audit first (vault password management, become privileges) separate from broader understanding.
- Use `ansible-inventory --graph`, git history, and actual recent run logs to build real understanding, not guesswork.

**Follow-up questions:**
1. What's the very first command you'd run against this codebase?
2. How would you distinguish load-bearing conventions from accidental ones?
3. What would justify an immediate fix versus something that can wait?

**Red flags:** "I'd rewrite it properly using best practices" with no discovery phase — mirrors the same mistake this entire category of question is designed to catch.

**Model answer:** *"I wouldn't start rewriting — I'd start reading and auditing. `ansible-inventory --graph` and git log on the actual playbook history tell me what's really there and how it evolved. In parallel, I'd specifically audit for acute risk — how the vault password is managed, whether `become` privileges are properly scoped — since those are worth fixing immediately regardless of broader conventions. Only after understanding what's load-bearing versus accidental would I propose structural changes, and even then, incrementally."*

**Full reference:** [Question 118: The tool debate that stalled a platform decision](../interview-questions/15-leadership-design.md#question-118-the-tool-debate-that-stalled-a-platform-decision)

---

## Scoring Rubric Reference
- **1 (Beginner):** Definitions only, no production experience, no failure handling.
- **2 (Intermediate):** Understands normal implementation, limited troubleshooting, weak security/scale awareness.
- **3 (Senior):** Explains production implementation, covers validation and rollback, understands idempotency/security/maintainability. **This is the passing bar for this interview.**
- **4 (Lead):** Explains architecture trade-offs, covers team governance and scale, anticipates failure modes, offers preventive controls.
- **5 (Staff/Architect):** Connects technical choices to business risk, designs for multiple teams/environments, covers blast radius/security/cost/compliance/HA/DR.

For this Senior-level mock, a candidate consistently scoring 3+ across all 15 questions is interview-ready for Senior DevOps Engineer roles. Consistent 4s suggest readiness for Lead-level interviews — try [Mock Interview 2](mock-interview-02-lead-ansible-engineer.md) next.
