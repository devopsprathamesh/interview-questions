# Category 15: Migration, Adoption, and Leadership/Architecture

Questions 118–120 of 120. Category weight: 3 questions. This final category is intentionally broader and more open-ended than earlier categories — it's where staff/lead-level judgment, communication, and organizational reasoning matter as much as technical depth.

---

## Question 118: Migrating a legacy fleet onto EKS

### Scenario
An organization runs 40 applications on a legacy, directly-on-EC2 (non-containerized) platform, managed via the companion Ansible repository's configuration-management patterns. Leadership wants to migrate to EKS over the next 18 months. You're asked to propose the migration strategy.

### Interview Question
Design the migration approach, including sequencing, risk management, and how you'd measure progress.

### Strong Senior-Level Answer
**Initial assessment:** a wholesale, big-bang migration of 40 applications is high-risk and hard to course-correct mid-flight — the correct approach is an incremental, risk-tiered migration prioritizing learning and de-risking early, informed by the same staged-rollout discipline established throughout this repository series (Category 8's fleet-upgrade staging, Category 10's canary deployments), applied here at the scale of an entire platform migration.

**Technical reasoning:** not every one of the 40 applications is equally straightforward to containerize/migrate — some (stateless, already well-modularized) are low-risk, high-learning-value candidates for an early wave; others (deeply stateful, tightly coupled to specific EC2-instance-level assumptions, or business-critical with low risk tolerance) warrant migrating later, once the team has genuine EKS operational experience from the earlier waves.

**Investigation process:** categorize all 40 applications along two axes: migration complexity (stateless/simple versus stateful/complex) and business criticality/risk tolerance — this produces a natural prioritization: begin with low-complexity, lower-criticality applications (maximizing learning while minimizing blast radius), and end with high-complexity and/or high-criticality applications (once the team's EKS operational muscle is well-established).

**Recommended solution:** a phased plan roughly mapping to this repository's own lab sequence: Phase 1 (months 1-3) stand up the EKS platform foundation (cluster, networking, IRSA, security baseline, observability — Labs 1-3, 8-9) and migrate 3-5 low-risk pilot applications, treating this explicitly as a learning phase with generous time for course-correction. Phase 2 (months 4-9) establish GitOps/CI-CD (Labs 10-12) and migrate the bulk of low-to-medium-complexity applications in waves, refining the migration playbook based on Phase 1's lessons. Phase 3 (months 10-16) migrate the remaining higher-complexity/higher-criticality applications, applying the by-now well-refined process. Phase 4 (months 17-18) decommission the legacy platform once every application is confirmed stable on EKS and a defined bake period has passed.

**Risk controls:** maintain the legacy platform running in parallel throughout (not decommissioning any piece of it until its EKS replacement has proven stable for a defined bake period) — never a one-way, irreversible cutover for any individual application until confidence is genuinely established; this mirrors the companion Terraform/Ansible repositories' "keep the old thing running until the new thing is proven" discipline applied at platform-migration scale.

**Validation steps:** define clear, objective success criteria per migration wave (functional parity, performance parity, no new incident patterns during a defined bake period) before considering any wave "complete" and moving to decommission that wave's legacy infrastructure.

**Rollback or recovery strategy:** for any individual application where the EKS migration reveals an unexpected, hard-to-resolve issue, the ability to fall back to the still-running legacy version (informed by the "keep the old thing running" risk control) provides a genuine, low-stress rollback path — never migrate an application's *only* running instance in a way that has no fallback.

**Long-term prevention/success measurement:** track concrete, leadership-visible metrics throughout — number of applications migrated per wave (velocity), number of migration-related incidents (quality), infrastructure cost trend (legacy platform cost declining as EKS platform cost grows, ideally with a net efficiency gain visible over time), and team-reported confidence/friction levels (a qualitative but important signal for whether the pace is sustainable).

### Step-by-Step Implementation
```text
Phase 1 (months 1-3): Platform foundation + 3-5 pilot applications (low complexity, low risk)
Phase 2 (months 4-9): GitOps/CI-CD maturity + bulk of low/medium-complexity apps, in waves
Phase 3 (months 10-16): Remaining high-complexity/high-criticality applications
Phase 4 (months 17-18): Legacy platform decommission, after confirmed bake period per app

Throughout: legacy and EKS versions run in parallel per application until that
application's EKS version is proven stable - never a one-way cutover.
```

### Under-the-Hood Explanation
This migration strategy applies the same core principle threaded through this entire repository series — stage risk, learn early and cheaply, never remove a fallback before its replacement is proven — at the scale of an organizational platform migration rather than a single infrastructure change, recognizing that a legacy-to-EKS migration is fundamentally a risk-management and change-management challenge as much as a technical one.

### Common Weak Answer
"Migrate all 40 applications simultaneously to hit the 18-month deadline efficiently."

### Why the Weak Answer Fails
A simultaneous, big-bang migration of 40 applications forgoes the ability to learn and course-correct from early waves before committing to the harder, higher-stakes applications, and creates an enormous, undifferentiated blast radius if anything goes wrong — an incremental, risk-tiered approach is both safer and, in practice, usually faster overall, since early-wave lessons meaningfully de-risk and speed up later waves.

### Follow-Up Questions
1. How would you handle a specific application that resists straightforward categorization (moderately complex, moderately critical) in your prioritization scheme?
2. How would you communicate migration progress and any timeline risk to leadership throughout the 18 months?
3. What would you do if Phase 1's pilot applications revealed the team needs meaningfully more foundational EKS expertise than initially planned for?

### Key Interview Signals
Designs a staged, risk-tiered, learn-early migration strategy with concrete phases, objective success criteria, and an explicit "never remove the fallback before the replacement is proven" discipline, rather than proposing an undifferentiated, all-at-once migration to meet a deadline.

### Hands-On Connection
[Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/) and the companion [Ansible repository's legacy-platform patterns](../../../ansible/ansible-senior-interview-preparation/).

---

## Question 119: The architecture decision nobody wanted to own

### Scenario
Two senior engineers on your platform team disagree strongly: one wants to adopt Karpenter as the sole autoscaling mechanism across the entire fleet; the other wants to keep Cluster Autoscaler for its perceived stability and familiarity, given the team's years of operational experience with it. The disagreement has stalled for weeks with no decision.

### Interview Question
As the lead responsible for this decision, how would you actually resolve it?

### Strong Senior-Level Answer
**Initial assessment:** a stalled architectural disagreement between two senior engineers, each with legitimate underlying concerns (Karpenter's genuine capability advantages per [`docs/node-management-and-autoscaling.md`](../docs/node-management-and-autoscaling.md) §2 versus the real value of operational familiarity/stability with an already-understood tool), needs a decision process that surfaces and weighs the actual, specific trade-offs rather than either deferring indefinitely or picking a side based on seniority/persistence.

**Technical reasoning:** both positions have genuine merit — Karpenter's flexible, consolidation-capable provisioning is a real technical advantage (per Category 4's questions), while "we have years of production experience successfully operating Cluster Autoscaler, and switching introduces genuine, non-zero operational risk during the transition" is also a legitimate, non-dismissible concern, not mere resistance to change.

**Investigation process:** convene both engineers (and relevant stakeholders) to explicitly articulate their concerns as concrete, checkable claims rather than general positions — "Karpenter is better" needs to become specific claims (cost savings via consolidation, faster provisioning for spiky workloads) that can be tested; "Cluster Autoscaler is safer" needs to become specific claims (known failure modes, existing runbooks, team's operational muscle memory) that can be weighed against Karpenter's actual maturity and the specific migration risks involved.

**Recommended solution:** propose a time-boxed, evidence-gathering pilot rather than a purely debate-based decision — migrate a bounded, lower-risk subset of the fleet to Karpenter, measure the concrete claims from both sides against real data (actual cost impact, actual operational incidents/friction during the pilot, actual team comfort level after hands-on experience), and use this evidence to make an informed, fleet-wide decision within a defined timeframe, rather than letting the disagreement stall indefinitely.

**Risk controls:** explicitly bound the pilot's scope and duration so it doesn't itself become an indefinite, unresolved half-state — set a clear decision date by which the fleet-wide direction will be decided based on the pilot's results, communicated to both engineers upfront so the process itself doesn't become another source of stalled uncertainty.

**Validation steps:** define, before the pilot begins, what specific evidence would actually change each engineer's position (informed by their own stated concerns) — this ensures the pilot is designed to genuinely inform the decision, not just generate more inconclusive data both sides can interpret differently.

**Rollback or recovery strategy:** if the pilot reveals genuine, significant issues with Karpenter for this organization's specific workload patterns, the bounded pilot scope means reverting that subset back to Cluster Autoscaler is a contained, low-risk action — exactly why a bounded pilot, not a full fleet-wide switch, is the right first step for a genuinely contested decision.

**Long-term prevention:** establish this same "convert positions into checkable claims, run a bounded pilot, decide by a set date based on evidence" process as the team's standard approach for future contested architectural decisions, so disagreements between senior engineers have a productive, time-bound resolution path rather than risking indefinite stalls.

### Step-by-Step Implementation
```text
1. Have both engineers state their position as specific, checkable claims.
2. Design a bounded pilot (a defined subset of the fleet, a defined duration)
   testing the specific claims from both sides against real data.
3. Set a clear decision date upfront, communicated to both engineers.
4. Gather evidence during the pilot: cost impact, operational incidents,
   team comfort/confidence after hands-on experience.
5. Make the fleet-wide decision based on the pilot's actual evidence,
   by the pre-committed date - not indefinitely deferred.
```

### Under-the-Hood Explanation
This is fundamentally a decision-process and team-leadership question rather than a purely technical one — the actual mechanism for resolving it (converting positions into testable claims, running a bounded, evidence-generating pilot, committing to a decision date) applies regardless of which specific technology is under debate, since the underlying pattern (legitimate technical disagreement between experienced engineers, stalled without a forcing function) recurs across many different architectural decisions a senior/staff engineer will need to help resolve over a career.

### Common Weak Answer
"As the lead, just make the call yourself based on your own judgment to end the stalemate."

### Why the Weak Answer Fails
Unilaterally overriding two senior engineers' genuine, evidence-based disagreement without incorporating their actual expertise and concerns risks making a worse decision than an evidence-informed process would, and also risks damaging the team's trust in the decision process itself for future disagreements — a good lead facilitates a productive resolution process rather than substituting their own judgment for the team's collective expertise without good reason.

### Follow-Up Questions
1. How would you handle a case where the pilot's results are genuinely ambiguous or inconclusive?
2. How would you communicate the final decision to the "losing" side of the debate in a way that maintains trust and collaboration going forward?
3. How would you scale this decision-process approach for a much larger team with many more stakeholders and opinions?

### Key Interview Signals
Designs a structured, evidence-based decision process (converting positions into testable claims, a bounded pilot, a committed decision date) rather than either avoiding the decision or unilaterally overriding both engineers' genuine expertise, demonstrating staff/lead-level facilitation and decision-making judgment.

### Hands-On Connection
[Lab 5 — Karpenter Autoscaling](../labs/lab-05-karpenter-autoscaling/) and [Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).

---

## Question 120: Explaining a platform decision to people who don't run Kubernetes

### Scenario
You need to present the business case for the EKS migration (from Question 118) to a group of non-technical executive stakeholders, who care about cost, risk, and timeline — not Kubernetes internals.

### Interview Question
How would you frame this presentation?

### Strong Senior-Level Answer
**Initial assessment:** a presentation to non-technical executives needs to translate every technical decision covered throughout this repository (autoscaling, GitOps, security policy, HA/DR) into business-relevant terms — cost impact, risk reduction, and delivery timeline — without requiring the audience to understand or care about the underlying Kubernetes mechanics, while still being honest and accurate about genuine trade-offs and risks.

**Technical reasoning:** every technical capability this repository covers has a corresponding business translation: Karpenter's cost-optimized autoscaling becomes "reduced infrastructure spend, with expected savings of X% based on our pilot data"; GitOps's continuous reconciliation and audit trail becomes "faster, safer deployments with a clear audit trail for compliance"; the security-hardening/policy-as-code layers become "reduced security/compliance risk, with specific, demonstrable controls"; the staged migration plan (Question 118) becomes "a de-risked timeline with clear, measurable milestones, not a single high-stakes cutover."

**Investigation process:** before the presentation, gather concrete, quantified data wherever possible (actual pilot cost/performance data, actual incident-rate comparisons, actual team-velocity metrics) rather than presenting purely qualitative claims — executives evaluating a significant investment decision need evidence, not just architectural enthusiasm.

**Recommended solution:** structure the presentation around the business's actual concerns, not the technology: (1) **Cost** — current spend, projected EKS-platform spend, expected savings/payback timeline, informed by real pilot data; (2) **Risk** — what's being reduced (deployment risk via GitOps/staged rollouts, security risk via policy enforcement, availability risk via proper HA/DR design) and what new risk is being introduced (a migration always carries some transition risk, be honest about this and show the mitigation plan from Question 118); (3) **Timeline** — the phased plan with concrete milestones and decision points, not a vague "18 months, trust us."

**Risk controls:** be honest about genuine uncertainty and trade-offs rather than overselling — executives who later discover a downplayed risk materialized will trust future technical recommendations less; a credible, appropriately-caveated presentation builds more durable trust than an overly confident one that later needs walking back.

**Validation steps:** after the presentation, ensure there's a clear mechanism for reporting actual progress against the presented plan's milestones (cost, risk, timeline) at agreed intervals, so the executive stakeholders can track real progress against what was presented, not just receive an initial pitch and then silence.

**Rollback or recovery strategy:** build the presentation's plan itself around the staged, reversible-per-wave migration approach from Question 118 — this is itself a risk-mitigation talking point for executive stakeholders specifically concerned about the downside of a failed or over-budget migration.

**Long-term prevention:** establish a regular, ongoing reporting cadence to these stakeholders throughout the actual migration (not just the initial pitch), reinforcing the trust built in the original presentation with continued, honest progress updates — including honestly reporting any deviation from the original plan and why, rather than only ever reporting good news.

### Step-by-Step Implementation
```text
Presentation structure:
1. Cost: current spend vs. projected EKS spend, savings/payback timeline (with real pilot data)
2. Risk: what's reduced (deployment, security, availability) vs. what's introduced
   (migration transition risk) and how it's mitigated (staged plan, parallel fallback)
3. Timeline: phased milestones with decision points, not a single all-or-nothing date
4. Ongoing reporting cadence commitment - progress updates against these three axes
   throughout the actual migration, not just this initial pitch
```

### Under-the-Hood Explanation
This is a communication and stakeholder-management skill, not a technical one — the underlying discipline (translate technical decisions into the audience's actual concerns, back claims with real evidence, be honest about trade-offs and risk, commit to ongoing accountability) is the same regardless of the specific technology being presented, and is exactly the skill that distinguishes a senior/staff engineer who can drive organizational decisions from one who can only execute technical work handed to them.

### Common Weak Answer
"Explain that Kubernetes is the industry standard and everyone is moving to it, so we should too."

### Why the Weak Answer Fails
"Industry standard" and "everyone is doing it" are not business justifications an executive audience should find compelling on their own — they don't address this organization's specific cost, risk, or timeline concerns, and a technical leader who can't translate a technical recommendation into concrete business terms specific to their own organization's situation isn't making a genuinely persuasive, accountable case for the investment.

### Follow-Up Questions
1. How would you handle a skeptical executive who pushes back on the projected cost savings figures?
2. How would you adjust this presentation if the pilot data (from Question 118) actually showed less favorable results than hoped?
3. How would you build ongoing trust with this stakeholder group across the full 18-month migration, not just in the initial pitch?

### Key Interview Signals
Translates every technical capability into concrete business terms (cost, risk, timeline) backed by real evidence, is honest about genuine trade-offs and risks rather than overselling, and commits to ongoing, accountable progress reporting — demonstrating the organizational communication and stakeholder-management judgment expected at senior/staff level.

### Hands-On Connection
[Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).
