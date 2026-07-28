# Category 13: Governance and Policy as Code

Questions 111–114 of 120. Category weight: 4 questions. Deep-dive reference: [`docs/security.md`](../docs/security.md) and [`docs/testing.md`](../docs/testing.md).

---

## Question 111: The lint pass that let a policy violation through

### Scenario
A team relies on `ansible-lint` as their sole automated governance gate for playbook quality. A PR introducing a task that disables a host's firewall entirely (a genuine security-policy violation, but syntactically and stylistically valid Ansible) passes `ansible-lint` cleanly and merges.

### Interview Question
Explain why `ansible-lint` didn't catch this, and design the correct governance layer.

### Strong Senior-Level Answer
**Initial assessment:** `ansible-lint` is fundamentally a **style and best-practice** checker (proper module usage, `FQCN` naming, avoiding deprecated syntax, `changed_when` discipline) — it has no built-in concept of organizational security *policy* (like "firewalls must never be disabled"), and expecting it to catch this class of violation is asking it to do a job it was never designed for.

**Technical reasoning:** catching genuine security-policy violations requires a purpose-built policy engine capable of expressing organization-specific rules against actual task content/parameters (e.g., "no task may set `firewalld` state to `disabled`" or "no task may set a security group's ingress to `0.0.0.0/0`") — a fundamentally different tool category from `ansible-lint`'s style-focused rule set.

**Investigation process:** confirm `ansible-lint`'s actual rule categories currently enabled, verifying none of them cover organization-specific security policy (they don't, by design) — settling that this is a governance-tooling gap, not an `ansible-lint` malfunction or misconfiguration.

**Recommended solution:** implement a dedicated policy-as-code layer specifically for organizational security rules — either custom `ansible-lint` rules (which does support custom, organization-specific rule plugins, a legitimate extension point) or a separate policy engine (like Conftest/OPA, evaluating rendered task content against Rego policies, mirroring the companion Terraform repository's policy-as-code approach) — explicitly checking for known-dangerous patterns like firewall-disabling tasks.

**Risk controls:** immediately audit for and remediate the already-merged firewall-disabling task, treating this as a genuine security gap requiring prompt remediation, not just a process-improvement opportunity.

**Validation steps:** after implementing the policy layer, confirm it correctly rejects a deliberately-reintroduced test version of the same firewall-disabling task, while correctly passing legitimate, policy-compliant playbook changes.

**Rollback or recovery strategy:** revert or fix the merged task that disabled the firewall, restoring the intended security posture.

**Long-term prevention:** treat style/best-practice linting (`ansible-lint`) and security-policy enforcement (a dedicated policy engine) as two distinct, complementary governance layers — never expecting one to substitute for the other, exactly the same "understand precisely what each control actually checks" discipline established throughout this repository series.

### Step-by-Step Implementation
```python
# Custom ansible-lint rule (or equivalent Conftest/OPA policy) specifically
# checking for organization security-policy violations
class NoFirewallDisableRule(AnsibleLintRule):
    id = "custom-001"
    description = "Tasks must not disable the host firewall"
    def matchtask(self, task, file=None):
        return (task["action"]["__ansible_module__"] == "ansible.posix.firewalld"
                and task["action"].get("state") == "disabled")
```

### Under-the-Hood Explanation
`ansible-lint`'s rule engine evaluates playbook/task structure against its own built-in (and optionally custom) rule set — its default rules focus entirely on Ansible-idiomatic style and common mistake patterns, with no built-in awareness of any specific organization's security policy; catching organization-specific security violations requires either extending `ansible-lint` with custom rules or layering a separate, purpose-built policy engine specifically designed for this class of check.

### Common Weak Answer
"ansible-lint should have caught this, it must be misconfigured."

### Why the Weak Answer Fails
This assumes `ansible-lint`'s scope includes organization-specific security policy, which it fundamentally does not by design — the actual fix requires a different or additional tool, not a configuration adjustment to `ansible-lint` itself.

### Follow-Up Questions
1. How would you decide which security policies belong in custom `ansible-lint` rules versus a separate policy engine like Conftest/OPA?
2. How would you audit the existing merged codebase for other, similar already-present policy violations `ansible-lint` never would have caught?
3. How does this compare to the companion EKS repository's OPA/Kyverno-versus-native-scanning distinction for security enforcement layers?

### Key Interview Signals
Correctly identifies `ansible-lint`'s actual, limited scope (style/best-practice, not security policy) and designs a separate, purpose-built policy-enforcement layer rather than expecting the linter to cover a category of check it was never designed for.

### Hands-On Connection
[Lab 13 — Policy as Code](../labs/lab-13-policy-as-code/).

---

## Question 112: The policy that only existed in one person's head

### Scenario
A senior engineer has, over years, developed a strong, consistent mental model of "things our playbooks should never do" (disable SELinux, use `command` instead of a proper module for package management, hardcode credentials) — but none of this is written down as an enforced policy; it's only caught during that engineer's own manual PR reviews.

### Interview Question
Diagnose the risk in this arrangement and design a fix.

### Strong Senior-Level Answer
**Initial assessment:** this is the same bus-factor risk established in the companion Category 11's Question 108 DR-drill scenario, here applied to code-review governance specifically — the organization's actual security/quality standards exist only in one person's memory and manual review habits, meaning the moment that engineer is unavailable (vacation, different project, departure), every one of these unwritten rules becomes unenforced with no one else even aware they exist.

**Technical reasoning:** manual review by a knowledgeable individual is exactly the kind of "remember to be careful" non-control this repository series consistently identifies as fragile — it works only as long as that specific person is reviewing every relevant PR, personally remembers every rule every time, and never has an off day; none of these are structural guarantees.

**Investigation process:** interview this engineer to explicitly enumerate every "thing we should never do" rule currently living only in their head — converting tacit, personal knowledge into an explicit, documented, and ultimately automatable rule set.

**Recommended solution:** codify every identified rule as an actual, automated check — custom `ansible-lint` rules or policy-engine rules (per Question 111's pattern) for anything expressible that way, and explicit, written review-checklist items for anything not yet automatable — removing the dependency on this one engineer's continued personal involvement in every single review.

**Risk controls:** roll out each newly-codified rule in a non-blocking, audit/warning mode first (mirroring the standard policy-rollout discipline established throughout this repository series) to catch any false positives or overly-broad rule definitions before making them build-blocking.

**Validation steps:** confirm the newly-automated rules correctly catch deliberately-reintroduced test violations of each specific pattern this engineer previously caught manually, proving the codification genuinely captures their tacit expertise.

**Rollback or recovery strategy:** if an automated rule proves overly strict or produces false positives, refine its specific logic rather than reverting to relying solely on the original engineer's manual review again.

**Long-term prevention:** treat any organization's accumulated "unwritten rules that one senior person catches manually" as a standing risk requiring active, deliberate extraction and codification — not just for this specific engineer, but as an ongoing practice whenever a team's collective, tacit quality/security knowledge is discovered to be concentrated in one individual's memory rather than structural, automated enforcement.

### Step-by-Step Implementation
```text
Process: interview the engineer, enumerate every "we should never do X" rule,
then for each one:
1. If automatable (custom ansible-lint rule / policy-engine rule) -> codify it,
   roll out in audit mode first, then enforce.
2. If not yet automatable -> add as an explicit, written review-checklist
   item visible to EVERY reviewer, not just this one engineer.
```

### Under-the-Hood Explanation
This is fundamentally a knowledge-management and process-durability problem, not a technical one — the actual fix (interviewing to extract tacit knowledge, then codifying into automated or explicitly-documented checks) applies the same underlying principle as any other bus-factor mitigation covered throughout this repository series: institutional knowledge concentrated in one person's memory is a standing organizational risk regardless of how good that person's judgment currently is.

### Common Weak Answer
"As long as this engineer keeps reviewing every PR carefully, we're fine."

### Why the Weak Answer Fails
This accepts an indefinite, unaddressed single point of failure for the organization's entire quality/security standard — the moment this engineer is unavailable for any reason, every one of these unwritten rules goes unenforced with nobody else even aware they existed, exactly the bus-factor risk this repository series consistently flags as requiring active mitigation, not passive acceptance.

### Follow-Up Questions
1. How would you prioritize which of the extracted rules to automate first versus which can remain manual-checklist items initially?
2. How would you structure the interview process to comprehensively extract tacit knowledge without missing important, less-obvious rules?
3. How does this connect directly to Category 11's Question 108 (the DR drill's bus-factor risk) as the same underlying pattern applied to code review instead of disaster recovery?

### Key Interview Signals
Recognizes concentrated, undocumented tacit knowledge as a genuine bus-factor risk for organizational governance, and designs a systematic extraction-and-codification process rather than accepting indefinite reliance on one individual's continued availability and memory.

### Hands-On Connection
[Lab 13 — Policy as Code](../labs/lab-13-policy-as-code/).

---

## Question 113: The policy exception that ate the whole policy

### Scenario
A Conftest/OPA policy enforcing "no playbook may use the `command` module without a `changed_when` guard" (per Category 1's idempotency discipline) is initially rolled out correctly. Over eighteen months, so many individual, one-off exceptions have been added to the policy's exclusion list (one per team, each added under time pressure to unblock a specific PR) that the policy now effectively excludes the majority of the codebase, providing minimal real enforcement.

### Interview Question
Diagnose this exception-accumulation erosion and design a healthier process.

### Strong Senior-Level Answer
**Initial assessment:** this is the exact same lint-rule-erosion pattern from Category 9's Question 81, here manifesting in a Conftest/OPA policy's exclusion list instead of `ansible-lint`'s `skip_list` — each individually-reasonable, time-pressured exception compounds into a policy that, in aggregate, no longer meaningfully enforces its original intent across most of the codebase.

**Technical reasoning:** an exclusion list has no built-in mechanism limiting how large it can grow or flagging when its accumulated scope has eroded the policy's practical enforcement value — each addition is evaluated (if at all) only against its own, immediate justification, with nobody stepping back to assess the exclusion list's cumulative effect on overall policy coverage.

**Investigation process:** review the full exclusion list's actual current scope against the total codebase — quantifying exactly what percentage of playbooks/tasks are currently excluded, and reviewing each exclusion's original justification (if documented at all) for whether it still reflects a genuine, still-valid exception versus convenience-driven scope creep that was never properly addressed.

**Recommended solution:** for each exclusion, either fix the underlying violation (the correct default response for anything that was truly just time-pressure-driven convenience) or, for genuinely justified, permanent exceptions, keep them but with an explicit, documented rationale and a defined re-review date — exactly mirroring Category 9's Question 81 fix for `ansible-lint` rule erosion, applied here to a policy-engine exclusion list.

**Risk controls:** establish a hard cap or a mandatory review trigger (e.g., "any exclusion list exceeding N entries or M% of the codebase requires an explicit governance review") preventing this same silent accumulation from recurring after remediation.

**Validation steps:** after remediation, confirm the policy's actual, aggregate enforcement coverage across the codebase has genuinely improved (not just that the exclusion list looks smaller on paper), and confirm new PRs introducing a genuine `changed_when`-guard violation are now correctly caught rather than silently excluded.

**Rollback or recovery strategy:** if fixing a specific violation reveals a genuinely legitimate need for an exception (rare, but possible), restore that specific exclusion with an explicit, documented justification and review date rather than reverting the broader remediation effort.

**Long-term prevention:** require any new addition to the policy's exclusion list to go through the same review/approval process as any other governance-relevant change (never a unilateral, unreviewed addition made under time pressure to unblock a single PR), and periodically audit the exclusion list's aggregate size/scope as a standing governance health-check — exactly the same discipline established for `ansible-lint` rule erosion in Category 9.

### Step-by-Step Implementation
```text
Remediation process (mirrors Category 9's Question 81):
1. Audit full exclusion list against total codebase - quantify actual coverage erosion
2. For each exclusion: fix the violation (default) or document a genuine,
   dated, re-reviewed justification (exception)
3. Require future exclusion additions to go through governance review,
   never a unilateral, time-pressured addition
4. Periodically audit exclusion-list size/scope as a standing health-check
```

### Under-the-Hood Explanation
An OPA/Conftest policy's exclusion mechanism (however implemented — a `deny` rule with a `not input.exception_list[...]` condition, for instance) has no self-limiting property; its aggregate scope is purely a function of how many entries have accumulated over time, with no automatic signal indicating when that accumulation has eroded the policy's practical value, exactly mirroring `ansible-lint`'s `skip_list` in this respect.

### Common Weak Answer
"Exceptions are normal and expected, this is just how policies evolve over time."

### Why the Weak Answer Fails
Some exceptions are indeed legitimate, but unchecked, unreviewed accumulation — exactly what happened here — represents genuine, compounding erosion of the policy's actual protective value, not healthy, expected evolution; the distinction matters, and this repository series consistently treats unchecked accumulation as a real risk requiring active management.

### Follow-Up Questions
1. How would you prioritize remediation across a large accumulated exclusion list with limited engineering time?
2. What governance/approval process would you establish for any future exclusion-list addition?
3. How does this connect directly to Category 9's Question 81 (the lint rule everyone disabled instead of fixing) as the identical underlying erosion pattern?

### Key Interview Signals
Recognizes policy-exclusion-list accumulation as the same erosion pattern already established for lint-rule disabling, and designs the identical remediation discipline (fix by default, document genuine exceptions, require review for future additions).

### Hands-On Connection
[Lab 13 — Policy as Code](../labs/lab-13-policy-as-code/).

---

## Question 114: Governance for a fleet nobody could agree how to govern

### Scenario
Twenty independent teams contribute roles to a shared, internal Ansible Galaxy-equivalent registry. Each team has different opinions about acceptable practices (some insist on strict `ansible-lint` compliance, others prioritize shipping speed over style compliance), and there's currently no organization-wide standard, leading to wildly inconsistent quality and, occasionally, genuine security issues slipping through in roles with looser standards.

### Interview Question
Design a governance model balancing team autonomy against necessary organization-wide minimum standards.

### Strong Senior-Level Answer
**Initial assessment:** this requires distinguishing between genuinely non-negotiable organization-wide minimums (security-relevant checks, per Question 111/113's policy layer) and team-specific style/workflow preferences (which reasonably vary and shouldn't be forced into uniformity) — a governance model conflating these two categories either over-constrains legitimate team autonomy or under-protects genuine security requirements.

**Technical reasoning:** a two-tier governance model — a mandatory, organization-wide, non-negotiable policy layer (security-relevant checks, à la Question 111, that every role must pass regardless of team) plus each team's own additional, optional style/workflow preferences layered on top (à la their own `ansible-lint` configuration choices) — allows genuine team autonomy where it doesn't compromise organization-wide security/quality minimums, while still closing the actual security gaps the current inconsistency has produced.

**Investigation process:** work with representatives from a cross-section of the twenty teams to define the actual, genuinely non-negotiable minimum bar (informed by the specific security issues that have already slipped through) — distinguishing this from each team's own stylistic preferences that don't need organization-wide uniformity.

**Recommended solution:** implement the mandatory minimum bar as a required, non-bypassable check in the shared registry's publication pipeline (any role failing the organization-wide security policy simply cannot be published/updated in the shared registry, regardless of team) — while leaving each team free to layer additional, stricter standards on top of this floor for their own roles if they choose, without requiring uniformity beyond the mandatory minimum.

**Risk controls:** ensure the mandatory minimum bar is kept genuinely minimal and well-justified (security-relevant, not stylistic) — an overly broad "mandatory" layer risks the same team-autonomy friction this governance model is meant to avoid, and risks teams finding workarounds to bypass an overly restrictive gate.

**Validation steps:** confirm the mandatory gate correctly rejects a deliberately-crafted test role violating the organization-wide security minimum, and confirm teams can still successfully publish roles meeting only the mandatory bar (without being forced into any specific team's additional stylistic preferences).

**Rollback or recovery strategy:** if the mandatory bar proves too broad or causes excessive friction, narrow it to a more genuinely minimal, well-justified security-only scope, informed by actual team feedback.

**Long-term prevention:** maintain this two-tier model (mandatory organization-wide security minimum, optional team-specific additional standards) as the standing governance framework for the shared registry, periodically reviewing the mandatory tier's scope to ensure it stays focused on genuine, justified minimums rather than drifting toward either over-constraint or under-protection.

### Step-by-Step Implementation
```text
Two-tier governance model:
Tier 1 (mandatory, organization-wide, non-bypassable in the publish pipeline):
  - Security-relevant checks only (no hardcoded secrets, no firewall-disabling
    tasks, proper become_user scoping, etc. - per Question 111's policy layer)
Tier 2 (optional, team-specific, layered on top):
  - Each team's own ansible-lint strictness, style preferences, additional
    role-specific quality bars - never imposed org-wide
```

### Under-the-Hood Explanation
A publication-pipeline gate enforcing only the mandatory Tier 1 checks (via the same policy-engine mechanism from Question 111) genuinely cannot be bypassed regardless of any individual team's own practices, since it's evaluated centrally as part of the shared registry's own publish process — while Tier 2 remains each team's own independent `ansible-lint`/CI configuration, entirely under their own control and not something the shared registry's governance needs to standardize.

### Common Weak Answer
"Just mandate that every team adopt the exact same ansible-lint configuration and style standards."

### Why the Weak Answer Fails
This over-constrains genuine team autonomy in areas (style, workflow preference) that don't actually need organization-wide uniformity, risking friction and resistance that could undermine adoption of the genuinely necessary security minimums — a governance model should distinguish what actually needs to be mandatory from what can reasonably remain team-specific.

### Follow-Up Questions
1. How would you decide, in practice, which specific checks belong in the mandatory Tier 1 versus optional Tier 2?
2. How would you handle a team that resists even the mandatory Tier 1 minimum, citing their own workflow needs?
3. How does this two-tier model compare to the companion EKS repository's Question 117 (twenty clusters, twenty policy opinions) — the same underlying governance-consistency challenge in a different technology context?

### Key Interview Signals
Designs a genuinely two-tier governance model distinguishing non-negotiable, security-relevant minimums from legitimately-variable team preferences, rather than either forcing uniform standards everywhere or leaving genuine security gaps unaddressed.

### Hands-On Connection
[Lab 13 — Policy as Code](../labs/lab-13-policy-as-code/) and [Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).
