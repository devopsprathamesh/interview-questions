# Category 15: Leadership and Architecture Decisions

Questions 118–120 of 120. Category weight: 3 questions. This category synthesizes the entire repository — every prior category's technical depth in service of organizational, cultural, and business decisions. Deep-dive reference: [`docs/interview-cheatsheet.md`](../docs/interview-cheatsheet.md).

---

## Question 118: You're the first Terraform hire

### Scenario
You join a 150-engineer company as its first dedicated Platform/Terraform Engineer. Terraform is already in use, but inconsistently — a dozen teams have each built their own conventions, module patterns, and state management approaches independently, with no shared standards, no central module registry, and no organization-wide security/policy enforcement.

### Interview Question
What do you actually do in your first 90 days?

### Strong Senior-Level Answer
**Initial assessment:** the temptation in this role is to immediately start building — a shiny new module registry, a comprehensive policy framework, a perfect layered architecture — but the actual first job is understanding what already exists and why, since a dozen teams' independently-evolved conventions almost certainly encode real, hard-won lessons (even if inconsistently applied) that a top-down rebuild risks discarding or repeating.

**Technical reasoning:** the highest-leverage early actions are the ones that reduce risk without requiring every team to change their workflow immediately — auditing for the highest-severity gaps (state security, credential handling, anything security-critical) first, since these carry real, present risk regardless of how inconsistent day-to-day conventions are.

**Investigation process:** spend meaningful early time actually reading the dozen teams' existing Terraform code and talking to the engineers who wrote it — what conventions emerged and why, what's caused real incidents versus what's just stylistically different but functionally fine, and which teams have the strongest existing practices worth generalizing into an organization-wide standard rather than inventing something new from scratch.

**Recommended solution:** a realistic 90-day arc: **weeks 1-3**, audit — inventory every team's state backend configuration for the security baseline (encryption, access control, versioning per [`security.md`](../docs/security.md)), inventory credential handling (any long-lived keys that should be OIDC), and catalog the range of existing module/architecture patterns. **Weeks 4-6**, close the highest-severity gaps found (any unencrypted/publicly-accessible state bucket, any long-lived credential that should be OIDC-federated) — these are worth acting on immediately, independent of any broader standardization effort, since they're genuine present risk. **Weeks 7-12**, begin building genuine organization-wide value incrementally — likely starting with a small number of the most-needed shared modules (probably networking/VPC, since nearly every team needs it and it's usually the most duplicated), a private module registry, and a lightweight policy-as-code starting point covering the most critical guardrails (public exposure, encryption) rather than attempting comprehensive governance on day one.

**Risk controls:** resist the urge to mandate a single "correct" architecture for all twelve teams immediately — earn credibility first by fixing acute risks and providing genuinely useful shared modules that teams *want* to adopt, before pushing for broader convention standardization that requires more organizational buy-in.

**Validation steps:** track adoption of whatever shared modules/registry you build — genuine voluntary adoption by teams is the real signal of success in the early months, more than any top-down mandate would be.

**Rollback or recovery strategy:** not directly applicable to an organizational role, but the general principle holds: any standard/convention you propose should be tested against at least one or two real teams' actual usage before being pushed broadly, exactly like the contract-testing discipline for module releases (see [Question 30 in category 3](03-modules.md#question-30-proving-a-new-module-version-wont-break-anyone-before-you-ship-it)).

**Long-term prevention:** the goal of the first 90 days is establishing trust and closing acute risk — the deeper organizational standardization (layered architecture, comprehensive policy-as-code, full CI/CD standardization) is a multi-quarter or multi-year effort that should be sequenced deliberately, not compressed into an unrealistic first-90-days mandate.

### Step-by-Step Implementation
```markdown
<!-- 90-day plan skeleton -->
## Weeks 1-3: Audit
- State backend security baseline across all 12 teams (encryption, access control, versioning)
- Credential handling audit (any long-lived keys vs. OIDC)
- Catalog existing module/architecture patterns and conventions

## Weeks 4-6: Close acute risk
- Remediate any unencrypted/publicly-accessible state
- Migrate any long-lived credentials to OIDC federation
- No broad convention mandates yet - targeted, high-severity fixes only

## Weeks 7-12: Build genuine shared value
- Stand up a private module registry
- Ship 1-2 high-demand shared modules (likely VPC/networking) built WITH input
  from the teams with the strongest existing practices, not invented in isolation
- Introduce a lightweight policy-as-code baseline (public exposure, encryption only)
- Track voluntary adoption as the real success metric
```

### Under-the-Hood Explanation
This question tests organizational judgment more than any specific Terraform mechanism — every technical tool referenced here (state security audit, OIDC migration, module registry, policy-as-code) has already been covered in depth elsewhere in this repository; the actual skill being assessed is sequencing and prioritization: understanding existing practice before replacing it, fixing acute risk before pursuing comprehensive standardization, and earning adoption through genuine value rather than mandate.

### Common Weak Answer
"Immediately establish organization-wide standards for modules, state management, and CI/CD so everyone is consistent."

### Why the Weak Answer Fails
This skips the audit/understanding phase entirely and risks mandating a rebuild that discards real, hard-won lessons embedded in the twelve teams' existing (if inconsistent) practices, while also almost certainly generating significant organizational friction and resistance from teams being told to abandon their working systems for an unproven new standard imposed on day one.

### Follow-Up Questions
1. How would you handle a team that actively resists adopting a new shared module or standard, even after the acute-risk-fixing phase has built some credibility?
2. How would you decide which of the twelve teams' existing practices to generalize into an org-wide standard versus which to actively discourage?
3. How would you measure success at the end of your first year, beyond just "things feel more standardized"?

### Key Interview Signals
This is a Staff/Architect-level question testing organizational judgment, sequencing, and the ability to build credibility incrementally rather than imposing top-down mandates — a candidate who jumps straight to "build the perfect platform" without an audit/trust-building phase is signaling less organizational maturity than one who sequences deliberately.

### Hands-On Connection
[Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/) synthesizes the technical end-state this 90-day plan is working toward.

---

## Question 119: Build the platform, or buy it?

### Scenario
Your organization is evaluating whether to build a custom internal CI/CD and governance platform for Terraform (extending your existing GitHub Actions setup with custom tooling) versus adopting a commercial Terraform-focused platform (Terraform Cloud/Enterprise, or a competitor like Spacelift or env0) that provides much of this out of the box.

### Interview Question
How would you frame this decision for leadership, and what would actually change your recommendation?

### Strong Senior-Level Answer
**Initial assessment:** this is a genuine build-vs-buy decision, and the correct frame isn't "which is technically superior" in the abstract — it's total cost of ownership (engineering time to build and maintain custom tooling, versus subscription cost) weighed against the organization's actual specific needs and how well a commercial platform's opinionated model fits them.

**Technical reasoning:** commercial platforms (TFC/TFE, Spacelift, env0) bundle state management, run orchestration, policy enforcement (Sentinel or their own equivalent), and access control into an integrated product — building the equivalent custom (state backend, CI/CD pipeline logic, policy-as-code integration, RBAC) is entirely achievable (this repository demonstrates exactly how), but represents real, ongoing engineering investment that a commercial platform trades for a subscription cost.

**Investigation process:** quantify the actual engineering time currently spent maintaining custom CI/CD/governance tooling (or projected to be spent building it, if not yet built) and compare against the commercial platform's pricing at your organization's scale (number of workspaces/runs, which is how most of these platforms price) — this is a genuine, quantifiable comparison, not just a gut feeling.

**Recommended solution:** present leadership with the actual trade-off framed concretely: "building custom costs approximately N engineer-months upfront plus M ongoing engineer-time per quarter for maintenance, versus a commercial platform costing $X/month at our scale, with the commercial option providing faster time-to-value but less flexibility for [specific things your organization needs that don't fit the commercial platform's opinionated model, if any exist]." The right answer is genuinely dependent on specifics — an organization with unusual, highly-custom requirements (a very specific compliance posture, deep integration with proprietary internal systems) may be better served by custom tooling despite the cost; an organization with fairly standard needs is very often better served by adopting a mature commercial platform rather than reinventing well-solved problems.

**Risk controls:** whichever path is chosen, avoid vendor lock-in becoming an unexamined risk — understand what migrating away from a chosen commercial platform (or from custom tooling to a commercial one later) would actually require, since state format and workflow patterns can create switching costs either direction.

**Validation steps:** if evaluating a commercial platform, run a genuine pilot with a representative subset of your actual configurations before committing organization-wide, to validate it actually fits your real workflow needs rather than assuming from a sales demo.

**Rollback or recovery strategy:** for a commercial platform pilot, ensure your state remains in a format/backend that isn't irreversibly locked into the platform (most reputable platforms support standard Terraform state formats reasonably portably) so a decision to not proceed doesn't strand your infrastructure.

**Long-term prevention:** revisit this decision periodically as both your organization's needs and the vendor landscape evolve — a build-vs-buy decision made at 150 engineers may not still be the right call at 500, in either direction.

### Step-by-Step Implementation
```markdown
<!-- Leadership decision framing -->
## Build vs. Buy: Terraform Platform

**Build (extend current GitHub Actions + custom tooling):**
- Upfront: ~[N] engineer-months (state backend hardening, policy-as-code integration, RBAC)
- Ongoing: ~[M] engineer-hours/quarter maintenance
- Pro: full flexibility for [specific unusual requirements]
- Con: ongoing engineering opportunity cost; reinventing well-solved problems

**Buy (Terraform Cloud/Enterprise or equivalent):**
- Cost: ~$[X]/month at current workspace/run volume
- Pro: integrated state, runs, policy (Sentinel), RBAC out of the box; faster time-to-value
- Con: less flexibility for [specific things]; genuine but usually manageable switching cost later

**Recommendation:** [specific, reasoned choice] based on [organization's actual specific needs]
```

### Under-the-Hood Explanation
This question deliberately has no single correct technical answer — every capability a commercial platform provides (state locking, policy enforcement, run orchestration, RBAC) has a well-understood, buildable equivalent already covered throughout this repository (Labs 2, 3, 12, 13), meaning the decision genuinely comes down to organizational economics and specific fit, not a technical capability gap either direction. The interview signal is whether the candidate frames this as a real trade-off analysis rather than a reflexive preference for either "always build for control" or "always buy to save time."

### Common Weak Answer
"Terraform Cloud is the official HashiCorp product, so we should just use it."

### Why the Weak Answer Fails
This is the same reasoning flaw as [Question 67 in category 7](07-security.md#question-67-choosing-a-policy-engine-before-you-have-a-platform-for-it) (choosing Sentinel because it's "HashiCorp-native" rather than because it fits the actual platform) — vendor affiliation isn't a substitute for an actual cost/fit analysis, and the right answer genuinely depends on organization-specific factors this response doesn't engage with at all.

### Follow-Up Questions
1. What specific, concrete requirement would tip this decision firmly toward "build" for your organization, if any?
2. How would you structure a genuine pilot to validate a commercial platform choice before full organizational commitment?
3. How would you handle a scenario where the decision was already made (e.g., by a previous platform lead) and you disagree with it — would you push to revisit it, and under what conditions?

### Key Interview Signals
A Staff/Architect-level question testing whether the candidate can frame a genuine business/technical trade-off analysis for leadership, quantifying real costs on both sides rather than defaulting to a reflexive build-everything or buy-everything preference, or deferring to vendor branding.

### Hands-On Connection
[Lab 12 — CI/CD Pipeline](../labs/lab-12-cicd-pipeline/) and [Lab 13 — Policy as Code](../labs/lab-13-policy-as-code/) demonstrate the "build" side of this trade-off concretely.

---

## Question 120: The incident that should change how the whole company works

### Scenario
A production outage — root-caused to an unreviewed `terraform apply` run locally by an engineer under time pressure, against a production database with no `prevent_destroy`, using a stale local state that didn't reflect a concurrent change another team had made an hour earlier — costs the company several hours of customer-facing downtime and becomes a widely-discussed incident across the engineering organization. You're asked to lead the response.

### Interview Question
This incident touches nearly every theme in this repository — state staleness, missing guardrails, local vs. pipeline applies, concurrent changes, incident culture. How do you lead the organizational response, beyond just fixing this one incident's immediate causes?

### Strong Senior-Level Answer
**Initial assessment:** this incident is a composite of several individually-covered failure modes (local production applies, missing `prevent_destroy`, stale state, concurrent-change collision) — the immediate technical fixes are all things this repository has already covered individually, but leading the *organizational* response requires more than a checklist of technical fixes; it requires using this incident as the forcing function for changes that individual technical fixes alone won't achieve.

**Technical reasoning:** the specific technical root causes map directly to controls covered throughout this repository: production applies should be structurally impossible to run locally (per [Question 89 in category 10](10-troubleshooting.md#question-89-the-apply-that-hit-the-wrong-account)), `prevent_destroy` should protect production stateful resources (per [Question 3 in category 1](01-terraform-core.md#question-3-decommissioning-a-prevent_destroy-protected-resource) and [Question 75 in category 8](08-cicd.md#question-75-cant-we-just-roll-it-back)), and CI-level concurrency controls should prevent the concurrent-change collision (per [Question 72 in category 8](08-cicd.md#question-72-the-queue-nobody-could-see)).

**Investigation process:** run a genuine blameless postmortem establishing the full timeline and every contributing factor — not stopping at "an engineer ran apply locally" (a symptom) but tracing back to why that was even possible (no structural prevention), why time pressure led to a shortcut (what organizational or on-call pressure created that pressure), and why the missing guardrails (`prevent_destroy`, concurrency controls) hadn't already been addressed (were they known gaps, or genuinely not considered before this incident?).

**Recommended solution:** implement the specific technical fixes (OIDC-only production role trust, per Question 89; `prevent_destroy` audit and rollout across all production stateful resources; CI concurrency groups per environment, per Question 72) as concrete, tracked deliverables with owners and deadlines — but also address the organizational dimension: is there a systemic pattern of engineers feeling pressured to bypass process during incidents (per the emergency-bypass discussion in [Question 71 in category 8](08-cicd.md#question-71-the-hotfix-that-skipped-the-line)) that needs a genuine, sanctioned fast-path instead of an ad hoc, risky one? Present findings and the remediation plan not just to the immediately-affected team but broadly across engineering, since the specific gaps found (local production access, missing prevent_destroy, no concurrency controls) are very likely to exist in other teams' configurations too, not just the one involved in this incident.

**Risk controls:** resist the temptation to make the individual engineer the focus of the postmortem or its narrative — a blameless postmortem culture is itself a control (people report and investigate incidents honestly when they're not afraid of being blamed for them), and undermining that culture in response to a high-visibility incident does lasting damage to your organization's ability to learn from future incidents.

**Validation steps:** track completion of the specific technical remediations with real deadlines, and — importantly — audit whether the *same* gaps (local production access, missing prevent_destroy, no concurrency controls) exist in other teams' environments, treating this incident as a prompt for an organization-wide audit, not just a fix scoped to the one affected team.

**Rollback or recovery strategy:** for the specific incident, this maps to the standard database-recovery process (restore from the most recent snapshot, quantify actual data loss, communicate transparently) covered in [Question 75](08-cicd.md#question-75-cant-we-just-roll-it-back) — but the "rollback" this question is really asking about is organizational: ensuring the postmortem's findings actually translate into completed remediation, not just a document that gets filed away.

**Long-term prevention:** this is the actual heart of the question — establishing that structural, technical controls (not reminders, not "be more careful next time") are the durable fix, communicated and applied organization-wide, with the incident serving as the concrete, memorable justification for investments (OIDC-only roles, prevent_destroy audits, concurrency controls) that might otherwise have been deprioritized as abstract best practice rather than urgent, demonstrated need.

### Step-by-Step Implementation
```markdown
<!-- Blameless postmortem structure -->
## Incident: Production database outage - [date]

### Timeline
[Full sequence of events, focused on system/process factors, not individual blame]

### Contributing factors (not root "causes" - systems thinking, not single-cause)
1. Production applies were runnable with locally-available credentials (structural gap)
2. No prevent_destroy on the affected database (structural gap)
3. No CI-level concurrency control for this environment's state (structural gap)
4. Time pressure during [context] led to bypassing the normal reviewed pipeline (process gap)

### Remediation (tracked, owned, deadlined - not just this team, audited org-wide)
- [ ] OIDC-only production role trust policy, no human-assumable path - Owner: X, Due: [date]
- [ ] prevent_destroy audit across all production stateful resources, all teams - Owner: Y, Due: [date]
- [ ] CI concurrency groups per environment, all teams - Owner: Z, Due: [date]
- [ ] Org-wide audit for the same three gaps beyond the affected team - Owner: W, Due: [date]
- [ ] Review whether legitimate incident-time fast-path process needs improvement (per Q71)
```

### Under-the-Hood Explanation
Every individual technical mechanism referenced in this response — OIDC trust scoping, `prevent_destroy` lifecycle guards, CI concurrency groups, blameless postmortem structure — has been covered in mechanical depth elsewhere in this repository. What this question specifically tests is the ability to synthesize multiple individually-understood technical controls into a coherent incident-response and organizational-change leadership narrative, recognizing that a single high-visibility incident is often the actual catalyst that gets previously-deprioritized structural investments (which every senior engineer may have already known were good ideas) funded and prioritized organization-wide.

### Common Weak Answer
"Have a conversation with the engineer about being more careful with production applies going forward."

### Why the Weak Answer Fails
This is the "remind people to be careful" non-control pattern that recurs as the wrong answer throughout this entire repository, applied here at the highest stakes — it does nothing to prevent the next engineer, under the next bout of time pressure, from being structurally *able* to make the same mistake, and actively damages incident-response culture by personalizing what was fundamentally a systemic, structural set of gaps.

### Follow-Up Questions
1. How would you balance the urgency of implementing these fixes quickly against doing them carefully enough not to introduce new problems (e.g., locking production access down so tightly it creates a different operational bottleneck)?
2. How would you measure, six months later, whether this incident actually resulted in lasting organizational change versus a temporary flurry of activity that faded?
3. How would you handle a similar incident's postmortem if leadership's instinct was to focus on individual accountability rather than systemic fixes?

### Key Interview Signals
This is the capstone Staff/Architect-level question — it tests whether a candidate can hold the entire technical picture (every relevant control from across this repository) in mind simultaneously while leading a response that's also organizationally and culturally sound: blameless, systemic, tracked to completion, and used as leverage for durable, structural change rather than a one-off patch or an individual-blame narrative.

### Hands-On Connection
[Lab 14 — Drift, Failure, and Recovery](../labs/lab-14-drift-and-recovery/) and [Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/) together provide the hands-on foundation for every technical control this incident response draws on.
