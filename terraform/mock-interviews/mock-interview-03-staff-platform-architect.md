# Mock Interview 3: Staff or Platform Architect

**Format**: 15 questions. **Focus**: Multi-account architecture, security, scale, organizational ownership, HA, and DR. **Level target**: Staff/Architect (score 5 is the pass bar; consistent 4s indicate strong Lead-level performance but not yet Staff-ready).

---

## Question 1
**Interviewer asks:** "Design a landing zone and account-vending system for an organization scaling from 10 to 100+ AWS accounts, including how governance is enforced without your six-person platform team becoming a bottleneck."

**Expected answer points:**
- Automated, deterministic account vending (not manual, ticket-driven provisioning).
- SCPs as non-negotiable, non-bypassable guardrails at the OU level; policy-as-code as the reviewable, testable pipeline gate.
- Recognizes the platform team's leverage must come from owning shared modules/pipeline/policy, not manual review of every change.
- Delegated ownership within guardrails, not centralized approval for everything.

**Follow-up questions:**
1. How do you roll out a new mandatory security tool across all 100 accounts safely?
2. How do you handle a business unit needing a genuinely different compliance posture?
3. What's your actual measure of whether this is working — headcount-independent scale?

**Red flags:** Any answer where the platform team remains a manual approval gate for every application team's change — doesn't scale past a few dozen accounts.

**Model answer:** *"The core design principle is that governance has to be structural, not headcount-dependent — six people can't manually review changes across 100+ accounts. SCPs enforce non-negotiable guardrails at the OU level, independent of any individual team's Terraform quality. Policy-as-code in every pipeline catches organization-specific rules reviewably and testably. Account vending is a deterministic Terraform pipeline, not a ticket process — every new account gets an identical baseline automatically. The platform team's actual leverage is owning the shared modules, the vending pipeline, and the policy set; delegated teams operate freely within those guardrails without needing platform-team sign-off for every change."*

**Full reference:** [Question 43](../interview-questions/05-aws-architecture.md#question-43-a-hundred-accounts-several-regions-one-terraform-estate), [Question 45](../interview-questions/05-aws-architecture.md#question-45-account-creation-shouldnt-be-a-ticket)

---

## Question 2
**Interviewer asks:** "A stakeholder wants 'as little downtime as possible' for a revenue-critical service, with a limited budget. How do you turn that into an actual architecture decision?"

**Expected answer points:**
- "As little as possible" is unbounded and always justifies the most expensive tier if taken literally — the job is translating it into concrete RTO/RPO numbers the business will actually fund.
- Present tiered options (backup/restore, pilot light, warm standby, active/active) with cost and recovery-speed trade-offs explicitly.
- Quantify actual cost of downtime to make the conversation concrete and let the business choose with real numbers.

**Follow-up questions:**
1. What if they refuse to commit to a specific number even after seeing the cost breakdown?
2. How do you revisit this decision as the service's criticality changes?
3. What's the Terraform-architecture implication of each tier?

**Red flags:** Silently picks a tier (usually the most expensive) without presenting the actual trade-off to the business.

**Model answer:** *"I wouldn't silently pick a tier — I'd present the real trade-off: backup/restore costs least but recovers in hours; pilot light and warm standby cost progressively more for progressively faster recovery; active/active is near-zero downtime at the highest cost. I'd quantify the actual revenue impact of downtime for this specific service so the business can compare it against each tier's cost, and let that comparison — not my assumption of what 'a little downtime' means — drive the decision. Whatever's chosen gets a concrete, documented RTO/RPO target, not an ambiguous aspiration."*

**Full reference:** [Question 99](../interview-questions/11-ha-dr.md#question-99-picking-a-dr-strategy-before-picking-a-dr-budget)

---

## Question 3
**Interviewer asks:** "Your organization runs its first-ever full DR drill and the actual RTO is 47 minutes against a documented 5-minute SLA. What do you do?"

**Expected answer points:**
- Treat this as valuable data, not something to explain away — update the documented figure to reality immediately.
- Break down the 47 minutes into its actual phases (decision time, DNS propagation, cold-start capacity, data promotion) to find the real bottleneck(s).
- Fix each identified bottleneck, then re-drill to validate — don't just theorize the fix worked.

**Follow-up questions:**
1. What if leadership pushes back on updating a customer-facing SLA?
2. How would you decompose "47 minutes" into its actual components?
3. What cadence would you set for future drills?

**Red flags:** "Tell customers this was a one-time fluke and the real RTO is still 5 minutes" — dismissing measured evidence.

**Model answer:** *"This is exactly what the drill is for — I wouldn't explain it away. First, update the documented RTO to reflect reality while the fix is in progress; continuing to cite an unvalidated 5-minute figure in a customer SLA is a real business risk. Then decompose the 47 minutes: how much was decision-making time, how much was DNS TTL/propagation, how much was cold-start capacity in a standby that wasn't actually 'warm'? Fix whichever phase dominates, then re-drill and only update the SLA figure once a second drill actually confirms the improvement."*

**Full reference:** [Question 100](../interview-questions/11-ha-dr.md#question-100-the-drill-that-told-an-uncomfortable-truth)

---

## Question 4
**Interviewer asks:** "During an actual regional outage, your team tries to execute the DR runbook — but the Terraform state backend itself is in the affected region and unreachable. What went wrong in the design, and how do you fix it?"

**Expected answer points:**
- A classic, easy-to-miss gap: the tool used to execute recovery shares the same regional failure domain as what it's recovering.
- Fix: cross-region state bucket replication, with a documented, drilled fallback procedure to point Terraform at the replica.
- Extends to auditing every other tool in the incident-response chain for the same gap.

**Follow-up questions:**
1. How do you handle the replication lag between primary and replica state?
2. What other tools in your incident chain might have this same gap?
3. How would you have caught this before an actual outage exposed it?

**Red flags:** "We'd just wait for the region to recover before running the DR runbook" — defeats the entire purpose of having one.

**Model answer:** *"This is a specific, well-known but easy-to-miss gap — the DR architecture addressed the application layer's regional dependency but not the tool used to execute the DR runbook itself. The fix is cross-region replication on the state bucket, with a documented and drilled fallback procedure pointing Terraform at the replica during exactly this kind of event. More broadly, this is the prompt to audit every other tool in the incident-response chain — CI/CD platform, secrets manager, monitoring — for the same 'does this share fate with what it's recovering from' question."*

**Full reference:** [Question 101](../interview-questions/11-ha-dr.md#question-101-the-dr-plan-that-needed-terraform-which-needed-the-thing-that-just-went-down)

---

## Question 5
**Interviewer asks:** "After a successful DR failover running for six hours, you need to fail back — but the secondary region has accumulated writes the primary never saw. How do you reconcile, and how does your data-layer choice affect this?"

**Expected answer points:**
- Reconciliation difficulty is a direct consequence of the replication technology chosen (multi-master vs. one-directional).
- For one-directional replication (e.g., RDS read replica promoted during failover): treat the more-complete (secondary) data as authoritative, re-establish it as primary, rebuild the old primary as the new replica — don't naively revert to the stale old primary.
- For genuinely multi-master (DynamoDB Global Tables): reconciliation is largely automatic via built-in conflict resolution, understanding the implications of last-writer-wins.

**Follow-up questions:**
1. What if the data layer is somewhere in between fully multi-master and one-directional?
2. How would application-level idempotency keys make this easier regardless of data-layer choice?
3. How would you validate data integrity before fully completing failback?

**Red flags:** "Just copy the primary's data back over the secondary's" — discards six hours of legitimate writes.

**Model answer:** *"The difficulty here is entirely a function of the data-replication technology chosen, which is exactly why that choice deserves scrutiny at DR-design time, not just at RTO/RPO selection time. For one-directional replication like a promoted RDS read replica, the right move is treating the secondary — which has the complete data — as authoritative, re-establishing it as primary, and rebuilding the old primary as the new replica in the reverse direction. Naively reverting to the old primary would silently discard six hours of real customer writes. If the data layer had been something genuinely multi-master, like DynamoDB Global Tables, this reconciliation would be far more automatic — which is itself a reason to prefer that architecture for anything with tight RTO/RPO requirements."*

**Full reference:** [Question 102](../interview-questions/11-ha-dr.md#question-102-the-failback-that-found-two-versions-of-the-truth)

---

## Question 6
**Interviewer asks:** "After an incident, a stakeholder says 'I thought Multi-AZ RDS meant we were protected against outages.' How do you explain the actual scope, and use this to teach the HA-versus-DR distinction?"

**Expected answer points:**
- Multi-AZ is genuine, valuable HA — protects against an AZ-level failure — but provides zero protection against a full regional outage, since all AZs in a Multi-AZ deployment are in the same region.
- Frame using the actual incident as the concrete teaching example, not an abstract lecture.
- If regional protection is now warranted, that's a separate, real DR investment conversation.

**Follow-up questions:**
1. How do you audit other services/stakeholders for the same misconception?
2. What's the actual mechanism difference between Multi-AZ failover and DR failover?
3. How do you prevent this misunderstanding proactively, before the next incident?

**Red flags:** "Multi-AZ should have handled this — must be misconfigured" — treating a scope mismatch as a technical defect.

**Model answer:** *"I'd use the actual incident as the concrete example: Multi-AZ would have handled a single data center going down — automatic failover in about a minute, no customer impact — but what happened was a full regional event, a different and much larger-scope failure that Multi-AZ was never designed to address, since every AZ in a Multi-AZ deployment lives in the same region. If this incident shows regional protection is now genuinely warranted for this service, that becomes its own DR investment conversation — a separate decision from HA, not something Multi-AZ was ever supposed to cover."*

**Full reference:** [Question 103](../interview-questions/11-ha-dr.md#question-103-multi-az-isnt-multi-region)

---

## Question 7
**Interviewer asks:** "A security audit finds your Terraform CI execution role has `AdministratorAccess`, justified as 'we didn't know what permissions were needed.' How do you remediate without breaking every pipeline?"

**Expected answer points:**
- Derive the actual required permission set empirically (IAM Access Analyzer policy generation from CloudTrail history), not by guessing a smaller policy from scratch.
- Test the generated policy in non-prod (or monitor mode) against every real pipeline before cutting over production.
- Keep the old policy detached-but-available for a defined rollback window.

**Follow-up questions:**
1. What if the observation window misses a genuine but rare operation?
2. How do you scale this remediation across dozens of similarly over-permissioned roles?
3. What ongoing process prevents this drifting back to broad permissions?

**Red flags:** "Write a policy with what we think Terraform needs" — repeats the exact guessing pattern that created the problem.

**Model answer:** *"Guessing a smaller policy from scratch is the same approach that likely produced `AdministratorAccess` in the first place. I'd derive least privilege empirically — IAM Access Analyzer's policy generation from actual CloudTrail history over a representative period, including infrequent-but-legitimate operations like an annual DR drill. I'd validate the generated policy against every real pipeline in non-production first, then cut production over as a single tested swap, keeping the old policy detached but available for a defined rollback window in case the observation window missed something."*

**Full reference:** [Question 63](../interview-questions/07-security.md#question-63-the-ci-role-that-could-do-almost-anything)

---

## Question 8
**Interviewer asks:** "A security researcher discloses that a popular community module your organization uses had a backdoored default for several versions. Walk me through your incident response."

**Expected answer points:**
- Treat as a genuine supply-chain compromise: assess actual impact (which consumers, which version, was it ever applied) before anything else.
- Remediate every affected resource; check CloudTrail for actual unauthorized access during the exposure window — this may be a genuine data-exposure incident requiring breach-assessment process, not just an infrastructure fix.
- Structural prevention: vetting process for third-party modules touching security-relevant resources; pin to audited commits, not floating tags.

**Follow-up questions:**
1. How do you determine if this was ever actually exploited versus just theoretically vulnerable?
2. How would you design a vetting process that doesn't create excessive team friction?
3. How does your response differ for a compromised provider versus a compromised module?

**Red flags:** "Switch to a different module going forward" as the complete answer — ignores impact assessment and potential data exposure entirely.

**Model answer:** *"This gets the same treatment as any other compromised dependency. First, impact assessment: which of our buckets were provisioned or last applied during the compromised version window, and did the backdoored policy actually reach applied infrastructure. I'd check CloudTrail for any access from the unexpected external account during that window — if there's evidence of actual access, this becomes a genuine data-exposure incident needing our breach-assessment process, not just an infrastructure fix. Structurally, this is the trigger to establish real vetting for third-party modules touching security-relevant resources, and to pin to audited commits rather than trusting an upstream maintainer's account security indefinitely."*

**Full reference:** [Question 62](../interview-questions/07-security.md#question-62-the-module-that-wasnt-what-it-claimed-to-be)

---

## Question 9
**Interviewer asks:** "Audit finds your production OIDC role's trust policy only checks the token issuer, not the repository or environment claim. What's the actual risk, and how do you fix it?"

**Expected answer points:**
- Any workflow anywhere in the GitHub org (or wherever the OIDC provider is registered) can currently assume this production role — a significant privilege-escalation exposure, not a theoretical one.
- Fix: add `sub`/`aud` condition scoped to the exact expected repository/environment claim.
- Test carefully against the legitimate pipeline's actual claim format before rolling into production, to avoid locking out legitimate CI.

**Follow-up questions:**
1. How do you verify the exact claim format your CI actually produces before tightening?
2. How do you extend this scoping for a monorepo with multiple environments?
3. How would you detect this class of misconfiguration proactively across dozens of roles?

**Red flags:** "Rotate the role's ARN" as the fix — doesn't address the actual trust-policy gap at all.

**Model answer:** *"Without a `sub` condition, any workflow anywhere in the org that can obtain a validly-signed OIDC token from the same issuer satisfies the trust policy — that's a real, not theoretical, privilege-escalation exposure. I'd add a condition scoped to the exact `repo:ORG/REPO:environment:production` subject claim, verified first against a non-production copy of the role to confirm the exact claim format our CI actually produces, since a too-strict condition would lock out legitimate CI just as badly as a too-loose one exposes the role."*

**Full reference:** [Question 37](../interview-questions/04-providers.md#question-37-the-assume-role-trust-policy-that-trusted-too-much)

---

## Question 10
**Interviewer asks:** "Your organization is deciding between building custom Terraform CI/CD tooling versus adopting a commercial platform like Terraform Cloud or Spacelift. How do you frame this for leadership?"

**Expected answer points:**
- Genuine build-vs-buy trade-off — not a technical-superiority question, since every commercial capability has a buildable equivalent.
- Quantify actual engineering time (build/maintain) versus subscription cost at the organization's actual scale.
- Recommend based on organization-specific fit (unusual requirements favor build; standard needs favor buy), not vendor branding.

**Follow-up questions:**
1. What specific requirement would tip this decision firmly toward "build"?
2. How would you structure a pilot before full commitment?
3. How do you avoid vendor lock-in becoming an unexamined risk?

**Red flags:** "It's the official HashiCorp product so we should use it" — vendor-affiliation reasoning, not a real trade-off analysis.

**Model answer:** *"Every capability a commercial platform provides — state locking, policy enforcement, run orchestration, RBAC — has a buildable equivalent; this isn't a technical-capability gap, it's a total-cost-of-ownership question. I'd quantify actual engineering time to build and maintain custom tooling against subscription cost at our real scale, and frame the recommendation around organization-specific fit — unusual compliance or integration requirements might favor build, standard needs usually favor buy — rather than which vendor's sales pitch was more compelling."*

**Full reference:** [Question 119](../interview-questions/15-leadership-design.md#question-119-build-the-platform-or-buy-it)

---

## Question 11
**Interviewer asks:** "You're the first dedicated Platform/Terraform hire at a 150-engineer company with a dozen teams' worth of inconsistent Terraform practices. What's your first 90 days?"

**Expected answer points:**
- Resist immediately mandating standards — audit and understand existing practice first, since inconsistent conventions often encode real lessons.
- Fix acute risk first (state security, credential handling), independent of broader standardization.
- Build genuine shared value incrementally (registry, high-demand shared modules) and earn voluntary adoption before pushing broader mandates.

**Follow-up questions:**
1. How do you handle a team that resists adopting a new shared module even after trust-building?
2. How do you decide which existing practices to generalize versus discourage?
3. How do you measure success at the end of year one?

**Red flags:** "Immediately establish organization-wide standards for everything" — skips the audit/trust-building phase entirely.

**Model answer:** *"I wouldn't start mandating — I'd start auditing. Weeks 1-3: inventory state security and credential handling across every team, and catalog existing patterns to understand what's load-bearing versus accidental. Weeks 4-6: fix any acute risk found — unencrypted state, long-lived credentials — independent of any broader standardization push. Weeks 7-12: build genuine shared value incrementally, likely starting with the most-duplicated module (probably networking) built with input from the teams with the strongest existing practices, and track voluntary adoption as the real signal of success, not a mandate."*

**Full reference:** [Question 118](../interview-questions/15-leadership-design.md#question-118-youre-the-first-terraform-hire)

---

## Question 12
**Interviewer asks:** "A high-visibility production outage traces back to an unreviewed local `terraform apply`, no `prevent_destroy`, and a stale-state collision with another team's concurrent change. You're leading the response. Walk me through it — technically and organizationally."

**Expected answer points:**
- Maps the specific technical fixes (OIDC-only production access, `prevent_destroy` audit, CI concurrency controls) to specific findings.
- Runs a genuine blameless postmortem — traces to systemic/structural causes, not individual blame.
- Uses the incident as leverage for organization-wide, tracked remediation (audited beyond just the affected team), not a one-off patch.
- Explicitly protects blameless culture even under pressure to find an individual at fault.

**Follow-up questions:**
1. How do you balance remediation urgency against doing it carefully?
2. How do you measure whether this produced lasting change six months later?
3. How do you handle leadership wanting individual accountability instead of systemic fixes?

**Red flags:** "Have a conversation with the engineer about being more careful" — the exact non-control this entire repository argues against, at the highest stakes.

**Model answer:** *"Technically, this maps directly to known fixes: make production applies structurally unreachable from any human-assumable credential — OIDC-only; audit and roll out `prevent_destroy` across every production stateful resource; add CI concurrency controls per environment. Organizationally, I'd run a genuinely blameless postmortem tracing to these structural gaps, not to the individual engineer's judgment under pressure — and I'd push to audit every other team for the same three gaps, since this incident is a symptom of an organization-wide pattern, not a one-team problem. The real leverage of a high-visibility incident is getting previously-deprioritized structural investments funded — I'd use it that way, tracked to completion, not as a one-off patch."*

**Full reference:** [Question 120](../interview-questions/15-leadership-design.md#question-120-the-incident-that-should-change-how-the-whole-company-works)

---

## Question 13
**Interviewer asks:** "An internal engineering-metrics dashboard has no DR plan and leadership won't fund a warm-standby architecture for it. Design an appropriate, cost-conscious DR approach."

**Expected answer points:**
- Maps stated criticality ("nice to have back quickly," no explicit SLA, limited budget) to the backup/restore tier — not over-engineering.
- Ensures the "redeploy elsewhere" path is genuinely region-parameterized and validated at least once, not just theoretical.
- Sets honest recovery-time expectations (hours, not minutes) matching the actual investment.

**Follow-up questions:**
1. What would change your recommendation as this tool's usage grows?
2. Why does even a "nice to have" tool deserve at least one real validation test?
3. How would this same discipline apply across many similar internal tools?

**Red flags:** "Accept it'll just be unavailable during an outage, no DR plan at all" — overcorrects in the other direction; even minimal DR discipline costs little here.

**Model answer:** *"This maps clearly to the cheapest tier — backup/restore — given the stated low criticality and explicit budget constraint. The actual investment is mostly discipline, not infrastructure: making sure the module set has no hidden regional assumptions so a 'redeploy elsewhere' actually works, a cheap periodic data export with cross-region durability, and — importantly — actually testing that redeploy-and-restore path once, even for a low-priority tool, since an unvalidated plan provides no real assurance regardless of how cheap the tier is. I'd set honest expectations that recovery here means hours, not minutes, matching the actual investment."*

**Full reference:** [Question 104](../interview-questions/11-ha-dr.md#question-104-dr-on-a-budget-for-something-that-still-matters)

---

## Question 14
**Interviewer asks:** "Your VP asks for a monthly report on 'how well we're doing on infrastructure governance,' with no specific metric in mind. What do you build?"

**Expected answer points:**
- Doesn't guess at a single metric — proposes concrete, decision-relevant metrics: policy compliance rate/trend, exception count and age, tag compliance, security-scan finding backlog trend.
- Confirms with the VP which metrics actually map to decisions before finalizing.
- Presents with narrative interpretation, not raw numbers alone.

**Follow-up questions:**
1. How do you handle a metric that looks good but is being gamed via broad exceptions?
2. How do you know if the governance program is actually improving outcomes, not just metrics?
3. How would you present this differently to an engineering audience versus the VP?

**Red flags:** "Show them run success/failure rate" — says almost nothing about governance specifically.

**Model answer:** *"'How are we doing' is vague enough to answer with almost anything, which is itself the problem — I'd propose concrete, decision-relevant metrics: policy compliance rate and trend, active exception count and age distribution, tag compliance percentage, and security-scan finding backlog trend, each aggregated from signals the pipeline already produces. I'd confirm with the VP which of these actually map to decisions they'd make differently, and present with a brief narrative — what changed and why — rather than raw numbers alone."*

**Full reference:** [Question 114](../interview-questions/13-governance.md#question-114-telling-leadership-whether-governance-is-actually-working)

---

## Question 15
**Interviewer asks:** "Your organization has grown from 20 to 400 engineers touching Terraform. `terraform init` is slow, local dev loops feel sluggish, and PR review has become a bottleneck. This isn't one big-state performance problem — how do you address it at organizational scale?"

**Expected answer points:**
- Recognizes this as a workflow-scaling problem, distinct from any single configuration's runtime performance.
- Shared provider plugin cache addresses slow `init` broadly; targeted performance fixes to widely-used shared modules address sluggish plan/validate; distributed ownership (per the layered architecture) scales review capacity.
- Prioritizes based on broadest impact, measures with concrete before/after metrics.

**Follow-up questions:**
1. How do you prioritize among these three investments with limited platform-team bandwidth?
2. How do you verify ownership delegation is actually improving review turnaround, not just redistributing the bottleneck?
3. What changes again going from 400 to 2,000 engineers?

**Red flags:** "Terraform is just inherently slower at scale, not much to do about it" — treats organizational friction as unavoidable rather than addressable.

**Model answer:** *"This is a workflow-at-scale problem, not a single configuration's performance problem, and it needs distinct levers: a shared, integrity-verified provider plugin cache addresses slow `init` for everyone at once; the plan/validate performance techniques applied specifically to the organization's most-used shared modules benefit every consumer; and the review bottleneck gets fixed by distributing ownership per the layered architecture, so review capacity scales with engineering headcount instead of concentrating on a platform team sized for 20 engineers. I'd prioritize whichever has the broadest daily impact first, and measure concretely — init time, plan time, review turnaround — before and after, rather than relying on anecdotal 'it feels faster.'"*

**Full reference:** [Question 110](../interview-questions/12-performance-scale.md#question-110-scaling-the-workflow-not-just-the-state)

---

## Scoring Rubric Reference
- **4 (Lead):** Architecture trade-offs, governance, scale awareness — a strong performance here is a good Lead-level result but underperforms the bar for this Staff/Architect interview.
- **5 (Staff/Architect):** Connects technical choices to business risk, designs for multiple teams/accounts, covers blast radius, security, cost, compliance, HA, and DR, and establishes durable organizational standards. **This is the passing bar for this interview.**

A candidate scoring 5 consistently across all 15 questions — including the organizational-leadership questions (11, 12, 14) as fluently as the technical-architecture questions — is genuinely interviewing at Staff/Principal Platform Architect level. If technical questions score 5 but organizational/leadership questions lag, that's a specific, addressable gap worth deliberate practice before the real interview — revisit [`docs/interview-cheatsheet.md`](../docs/interview-cheatsheet.md) and [Lab 15](../labs/lab-15-enterprise-capstone/)'s `OPERATIONS.md` for the operational-documentation muscle this level specifically tests.
