# Mock Interview 2: Lead Ansible Engineer

**Format**: 15 questions, 75 minutes. **Focus**: role architecture, testing, CI/CD, and cross-team standards. **Level target**: Lead (score 4 on the rubric is the target; consistent 3s suggest more Senior-level readiness than Lead).

Use the [Scoring Rubric](#scoring-rubric-reference) at the end for every question.

---

## Question 1
**Interviewer asks:** "Design a role's interface so a new engineer can use it safely without reading its internal task files."

**Expected answer points:**
- `argument_specs.yml` — typed, validated, documented inputs, Ansible's closest equivalent to Terraform's typed module variables.
- Clear `defaults` vs. `vars` separation as a genuine interface decision, not an arbitrary file split.
- A `README.md` documenting intended usage, kept in sync with `argument_specs.yml` as the actual source of truth.

**Follow-up questions:**
1. What happens if `argument_specs.yml` and the README disagree?
2. How would you enforce this consistently across many roles maintained by different teams?
3. What's the failure mode of a role with no `argument_specs.yml` at all?

**Red flags:** Relies solely on a hand-written README as the interface contract, with no automated validation backing it.

**Model answer:** *"`argument_specs.yml` is the actual, enforced source of truth — typed, required/optional, with choices validated at role-call time, before any task runs. A README should describe the same contract in prose, but if they ever disagree, `argument_specs.yml` wins because it's the only one Ansible actually validates against; a stale README is a documentation bug, not a behavior bug. Without `argument_specs.yml` at all, a bad input surfaces confusingly deep inside a task instead of immediately, at the interface boundary."*

**Full reference:** [Question 26](../interview-questions/03-roles-collections.md#question-26-the-readme-that-lied)

---

## Question 2
**Interviewer asks:** "A shared role used by twelve teams passes its own Molecule tests cleanly after a change, but breaks one specific downstream consumer immediately. Why, and how do you prevent this going forward?"

**Expected answer points:**
- A role's own Molecule tests only cover scenarios its maintainers thought to test — inherently incomplete relative to real, diverse downstream usage.
- Fix: a contract-test matrix testing against representative real consumer configurations, not just the maintainer's assumed-typical scenario.

**Follow-up questions:**
1. How would you gather representative consumer configurations without requiring every team to proactively contribute one?
2. What's the CI cost trade-off of testing against many consumer configurations?
3. How does this compare to testing a widely-used Terraform module or a shared CI template?

**Red flags:** Concludes the downstream team's configuration was simply "wrong" without questioning whether the role's own test coverage was adequate.

**Model answer:** *"The role's own tests passing doesn't mean the change is safe for everyone — it only proves consistency with whatever the maintainer's own test scenario happens to cover, which is inherently a subset of real, diverse downstream usage. I'd build a contract-test matrix specifically incorporating a representative sample of actual consumer configurations, run in CI before any new version is published — this is the same pattern I'd apply to a widely-shared Terraform module or CI template facing the identical problem."*

**Full reference:** [Question 82](../interview-questions/09-testing-validation.md#question-82-the-role-that-had-no-idea-it-broke-someone-else)

---

## Question 3
**Interviewer asks:** "Your organization's `ansible-lint` configuration has accumulated dozens of globally-disabled rules over eighteen months. A serious violation just slipped through because the relevant rule was disabled long ago for an unrelated reason. How do you fix this?"

**Expected answer points:**
- Each individually-reasonable disable compounds into significant, silent erosion of the linter's actual protective value.
- Fix: re-enable every rule, address each violation by fixing it (default) or documenting a narrow, justified, reviewed exception — never a blanket disable.
- Prevent recurrence: require review/approval for any future rule-disable request.

**Follow-up questions:**
1. How would you prioritize which re-enabled violations to fix first across a large codebase?
2. What's the difference between a blanket `skip_list` entry and a scoped inline `# noqa`?
3. How would you apply this same discipline to a policy-engine's exclusion list, not just `ansible-lint`?

**Red flags:** Treats the immediate violation as an isolated bug rather than recognizing the systemic erosion pattern behind it.

**Model answer:** *"Each disable was individually reasonable at the time, but eighteen months of accumulation has quietly gutted the linter's actual coverage — that's the real problem, not just this one violation. I'd re-enable every rule, and for each currently-disabled one, either fix the underlying violations or, for a genuinely justified case, replace the blanket disable with a narrow, dated, documented inline exception. Going forward, any new disable request goes through the same review as any other governance change — never a unilateral addition to unblock one PR."*

**Full reference:** [Question 81](../interview-questions/09-testing-validation.md#question-81-the-lint-rule-everyone-disabled-instead-of-fixing)

---

## Question 4
**Interviewer asks:** "How would you design a CI pipeline that gives your team confidence comparable to Terraform's plan/apply model, given Ansible has no saved-plan-artifact equivalent?"

**Expected answer points:**
- Honestly acknowledge the gap: `--check --diff` re-evaluates live, it's not a frozen, guaranteed-identical artifact the way a Terraform plan file is.
- Mitigation: minimize the time between the reviewed check-mode run and the real apply, ideally the same pipeline invocation, same pinned commit/Execution Environment image.
- Layer in lint, Molecule testing, and a manual approval gate as complementary controls.

**Follow-up questions:**
1. What's the actual risk if the check-to-apply gap is large?
2. How would you communicate this honestly to a team expecting Terraform-equivalent guarantees?
3. What's the role of a pinned Execution Environment image in closing part of this gap?

**Red flags:** Claims `--check` is functionally equivalent to a Terraform plan file — overstates the guarantee and risks false confidence.

**Model answer:** *"I'd be upfront that this is a genuine, structural gap — Ansible's `--check` re-evaluates against live state fresh each time, it isn't a saved, frozen artifact the way a Terraform plan file is, so there's no absolute guarantee the real apply matches exactly what was reviewed. My mitigation is minimizing that gap: run the reviewed check and the real apply in immediate succession within the same pipeline execution, against the same pinned commit and Execution Environment image, and back it up with Molecule testing and lint as complementary, independent layers of confidence."*

**Full reference:** [Question 72](../interview-questions/08-cicd-automation.md#question-72-the-plan-ansible-never-had)

---

## Question 5
**Interviewer asks:** "A developer's local `ansible-playbook` run behaves differently than the identical playbook run via your AWX/CI pipeline. Diagnose and fix the architecture, not just this one incident."

**Expected answer points:**
- Independently-managed local Ansible/collection versions inevitably drift from whatever CI/AWX pins.
- Fix: `ansible-navigator` against the same, pinned Execution Environment image for both local development and CI — eliminating the version-drift class of bug entirely.

**Follow-up questions:**
1. How would you roll this out to a team accustomed to a locally-installed `ansible-core`?
2. What's the build/maintenance overhead of an Execution Environment image?
3. How does this compare to the companion EKS repository's container-image-consistency guidance?

**Red flags:** Proposes "just tell developers to keep their local versions up to date" — an unenforceable, drift-prone non-solution.

**Model answer:** *"This is a classic 'works on my machine' gap — independently-installed local Ansible/collection versions will always eventually drift from whatever's pinned in CI/AWX. The structural fix is having developers use `ansible-navigator` against the exact same, version-pinned Execution Environment image CI uses — not a policy asking people to manually keep versions in sync, which is exactly the kind of unenforceable process that fails eventually. It's genuinely the same discipline as the companion EKS repository's guidance on using identical container images across CI and local development."*

**Full reference:** [Question 73](../interview-questions/08-cicd-automation.md#question-73-the-execution-environment-that-drifted-from-every-developers-laptop)

---

## Question 6
**Interviewer asks:** "Design cross-account IAM access for a set of Ansible-driven controllers running in a hub account, managing resources in five separate target accounts."

**Expected answer points:**
- A hub-account IRSA/instance role with permissions scoped to *only* `sts:AssumeRole` against five specific, named target-account role ARNs — never a wildcard.
- Each target account's role independently scoped to that specific business unit's actual needs, trusting only the hub role's specific ARN.

**Follow-up questions:**
1. What's the risk of a wildcard `AssumeRole` permission instead of an explicit allowlist?
2. How would you extend this pattern for a sixth account being onboarded later?
3. How does this compare to the companion Ansible AWS-integration category's identical five-account scenario?

**Red flags:** Proposes a single broad credential with access across all five accounts simultaneously "for simplicity."

**Model answer:** *"I'd use a two-hop chained-role design: the hub role's own permissions are scoped to `sts:AssumeRole` against exactly five named target-account role ARNs, never a wildcard pattern that could match unintended roles. Each target account's role independently trusts only that specific hub role ARN, and is scoped to only what that business unit's automation genuinely needs. A single broad, shared credential across all five accounts would mean one compromised controller has unrestricted reach across every business unit — an unacceptable, avoidable blast radius."*

**Full reference:** [Question 29](../interview-questions/03-roles-collections.md#question-29-retiring-the-ad-hoc-git-tag-roles) and [Question 42](../interview-questions/04-modules-plugins.md#question-42-one-playbook-five-aws-accounts)

---

## Question 7
**Interviewer asks:** "You're asked to build organization-wide Ansible standards across 15 independent teams with wildly inconsistent current practices. How do you approach this without triggering mass resistance?"

**Expected answer points:**
- A two-tier model: a mandatory, non-negotiable security minimum (policy-enforced), plus recommended-but-optional style conventions.
- Roll out the mandatory tier in audit mode first, gather feedback, then enforce.
- Derive standards from actual, surveyed current practices and real incidents, not abstract preference.

**Follow-up questions:**
1. How would you handle a team resisting even the mandatory tier?
2. How would you measure genuine adoption versus superficial compliance?
3. How would you keep the standard from becoming stale over time?

**Red flags:** Proposes a single, comprehensive, immediately-mandatory standard imposed top-down with no phased rollout.

**Model answer:** *"I'd distinguish genuinely non-negotiable security minimums from matters of legitimate team preference — a two-tier model, where the mandatory tier (vault usage, scoped become, secret handling) is policy-enforced, and everything else (role layout, naming conventions) is recommended but not forced initially. I'd roll the mandatory tier out in audit mode first, gather feedback, and only then flip to enforcement — informed by a survey of what's actually working well across teams already, not an abstract best-practices document imposed without buy-in."*

**Full reference:** [Question 119: Building a platform team's Ansible standards from scratch](../interview-questions/15-leadership-design.md#question-119-building-a-platform-teams-ansible-standards-from-scratch)

---

## Question 8
**Interviewer asks:** "Two senior engineers disagree for weeks on whether to adopt Ansible or extend Terraform provisioners for a new configuration-management need. As the lead, how do you resolve this?"

**Expected answer points:**
- Convert both positions into specific, testable claims rather than abstract preferences.
- Run a bounded, time-boxed pilot testing the real need with both approaches, deciding on real evidence by a committed date.
- Never unilaterally override without incorporating both engineers' genuine expertise.

**Follow-up questions:**
1. What's HashiCorp's own documented guidance on provisioners, and how does that inform this specific debate?
2. How would you handle an inconclusive pilot result?
3. How would you communicate the decision to the "losing" side while preserving trust?

**Red flags:** "As the lead, I'd just decide" with no evidence-gathering process — risks a worse decision and damages team trust.

**Model answer:** *"I wouldn't unilaterally decide — I'd convert both positions into testable claims and run a bounded, time-boxed pilot implementing the real need both ways, evaluated against concrete criteria: idempotency/re-run safety, partial-failure handling, actual operational complexity. HashiCorp itself documents provisioners as a last resort, which is a relevant data point, but I'd still want the pilot's real evidence rather than deciding from that alone. I'd commit to a decision date upfront so the evidence-gathering process itself doesn't become another source of stalled uncertainty."*

**Full reference:** [Question 118: The tool debate that stalled a platform decision](../interview-questions/15-leadership-design.md#question-118-the-tool-debate-that-stalled-a-platform-decision)

---

## Question 9
**Interviewer asks:** "A migration from Puppet to Ansible produces a functionally-correct but deeply un-idiomatic codebase — heavy `command`/`shell` usage mimicking Puppet's exec resources, no roles, everything in a few massive playbooks. What went wrong in how this migration was approached?"

**Expected answer points:**
- A literal, one-to-one translation preserves the source tool's idioms inside the target tool's syntax, missing the actual benefit of migrating (maintainability, testability, reuse).
- The correct approach re-derives each resource's actual intent and expresses it using Ansible's own idiomatic mechanisms (proper modules, roles).

**Follow-up questions:**
1. How would you budget/communicate the additional time this correct approach requires?
2. How would you prioritize re-architecting an already-literally-translated codebase?
3. How does this mirror the same lesson in the companion EKS repository's Ansible-to-Kubernetes migration guidance?

**Red flags:** Defends the literal-translation approach as "faster, and we can clean it up later" — this technical debt rarely gets paid down voluntarily.

**Model answer:** *"The mistake was framing the migration as 'translate literally' instead of 're-architect using Ansible's own idioms.' A literal translation preserves Puppet's exec-resource shape inside Ansible syntax — heavy `command`/`shell` wrapping, no role structure — which is functionally working but captures none of Ansible's actual advantages: real idempotency, Molecule testability, role-based reuse. The correct approach re-derives what each Puppet resource was actually trying to accomplish and expresses that using proper Ansible modules and role decomposition — genuinely more expensive upfront, but the only approach that doesn't just relocate the technical debt into a new syntax."*

**Full reference:** [Question 117: The migration from Puppet that started with the wrong question](../interview-questions/14-migration-upgrade.md#question-117-the-migration-from-puppet-that-started-with-the-wrong-question)

---

## Question 10
**Interviewer asks:** "How would you design Ansible automation for a fleet growing toward 10,000 hosts over two years?"

**Expected answer points:**
- Compose every performance lever together: `forks` sizing, execution strategy, filtered fact-gathering, SSH pipelining, cached/scoped dynamic inventory.
- Profile a representative subset first to prioritize which levers matter most for this specific fleet's characteristics.
- Consider whether the fleet should be partitioned into multiple smaller per-application inventories/pipelines rather than one monolithic unit.

**Follow-up questions:**
1. Why is composing multiple levers more effective than maximizing any single one (e.g., just `forks`)?
2. How would you benchmark this design as the fleet actually grows toward the target size?
3. When would you decide to partition rather than scale one unified inventory?

**Red flags:** "Just increase forks as high as possible" — treats one lever as sufficient, ignoring the other independently significant factors at this scale.

**Model answer:** *"No single setting handles 10,000 hosts — I'd compose `forks` sizing (validated against control-node capacity), a deliberately-chosen execution strategy, filtered fact-gathering, SSH pipelining, and cached/scoped dynamic inventory together, since each addresses a genuinely distinct performance dimension. I'd first profile a representative subset of the actual fleet to see where time is really being spent, rather than guessing which lever matters most, and I'd seriously consider partitioning into per-application inventories once a single unit's management genuinely becomes unwieldy, rather than scaling one monolithic inventory indefinitely."*

**Full reference:** [Question 110: Designing Ansible for 10,000 hosts](../interview-questions/12-performance-scale.md#question-110-designing-ansible-for-10000-hosts--the-performance-capstone-synthesis)

---

## Question 11
**Interviewer asks:** "A shared CI pipeline template used by every project in your organization is changed to require a new environment variable — and it silently breaks every consuming project simultaneously. How should this have been prevented?"

**Expected answer points:**
- A shared template used organization-wide deserves the *highest*, not lowest, testing rigor, given its outsized blast radius.
- Fix: a contract-test suite for the template itself, using representative "consumer" test repositories, run before any change is published.
- Consider a backward-compatible transition (optional-with-default first) rather than an immediate breaking requirement.

**Follow-up questions:**
1. Why is "it's been running for years without issues" not evidence of safety?
2. How would you select representative consumer test repositories?
3. How does this compare to Question 2's shared-role testing gap?

**Red flags:** "It's been stable for years, this was just an unlucky one-off" — dismisses a systemic testing gap as bad luck.

**Model answer:** *"'It's been running for years without testing' describes accumulated risk, not evidence of safety — this incident is exactly what happens the first time a genuinely breaking change is introduced. A shared, organization-wide template needs the highest testing rigor precisely because its blast radius spans every consumer simultaneously — I'd build a contract-test suite using representative consumer repositories, run before any change is published, and for a change like a new required variable, I'd strongly prefer introducing it as optional-with-a-safe-default first, giving consumers time to adopt it before it ever becomes required."*

**Full reference:** [Question 86: Testing the thing that tests everything else](../interview-questions/09-testing-validation.md#question-86-testing-the-thing-that-tests-everything-else)

---

## Question 12
**Interviewer asks:** "How would you prove, for a compliance audit, that every IRSA-equivalent role and cross-account credential across thirty clusters/environments follows least privilege — without a slow, unreliable manual review?"

**Expected answer points:**
- Convert the vague audit ask into specific, automatable checks (trust-policy subject-scoping, node-role-fallback exposure, RBAC/permission wildcards).
- Build a systematic, scripted audit across every environment, not a per-environment manual review.
- Self-attestation from each team is not defensible evidence for a compliance audit.

**Follow-up questions:**
1. How would you validate the automated scan's own accuracy before trusting its output?
2. How would you prioritize remediation across many findings with limited engineering time?
3. How would you make this a recurring, not one-time, practice?

**Red flags:** Proposes having each of the thirty teams self-attest to compliance — unenforceable and not real evidence for an audit.

**Model answer:** *"I'd convert 'prove least privilege' into specific, checkable criteria — does every credential's trust/permission definition include proper scoping, are there any wildcard grants, is every ServiceAccount-equivalent identity actually using a scoped role rather than falling back to something broader. Then I'd build one automated script running that check across all thirty environments, producing a single, defensible report — self-attestation from each team individually isn't real evidence for a compliance audit, and manual review at that scale isn't reliable or fast enough. I'd spot-check the automated scan against a manual sample first to validate its own accuracy before trusting the full output."*

**Full reference:** [Question 34: Auditing IRSA at fleet scale](../interview-questions/03-roles-collections.md#question-34-sunsetting-the-role-nobody-was-supposed-to-still-be-using)

---

## Question 13
**Interviewer asks:** "Design the coordination process for rolling out a Kubernetes-adjacent or Ansible-core version upgrade across 20 clusters/environments shared by 20 independent teams."

**Expected answer points:**
- A staged, cohort-based rollout by risk tolerance (lowest-impact first), never simultaneous.
- Objective, evidence-based criteria for advancing between cohorts, not subjective judgment.
- Balance team scheduling autonomy against a firm, externally-anchored deadline (e.g., end-of-support date).

**Follow-up questions:**
1. How would you handle a team resisting every proposed upgrade window?
2. What's the risk of an entirely open-ended, no-deadline rollout?
3. How would you incorporate lessons from one year's rollout into the next?

**Red flags:** Proposes upgrading all 20 simultaneously "to save time" or leaving it entirely open-ended with no deadline.

**Model answer:** *"I'd stage this in cohorts by risk tolerance — a single lowest-impact environment first, as a genuine canary with a defined bake period, then progressively larger, higher-impact cohorts, each gated on objective, evidence-based criteria rather than subjective confidence. I'd give teams real input into their specific slot within an overall window, but anchor the whole process to a firm, non-negotiable final deadline — like an actual end-of-support date — so flexibility within the window doesn't become indefinite, unaccountable delay."*

**Full reference:** [Question 74/78-equivalent staged-rollout guidance, cross-referenced from the companion EKS repository's Questions 74 and 78]

---

## Question 14
**Interviewer asks:** "A team wants a single Ansible role that branches, via heavy conditionals, to handle both a legacy VM deployment and a Kubernetes Helm-based deployment of the same application. Good design?"

**Expected answer points:**
- No — VM configuration and Kubernetes manifest deployment are different-enough problems that forcing them into one role's conditionals sacrifices clarity for superficial reuse.
- Maintain two separate, platform-idiomatic paths, unifying only genuinely shared elements (version, config values) via a single external source.

**Follow-up questions:**
1. What would need to be true for a genuinely shared abstraction across both platforms to make sense?
2. How would you ensure both paths never silently diverge in application version?
3. How does this connect to the broader "opinionated over overly-generic role" principle?

**Red flags:** Endorses the single conditional-heavy role "since there's only one place to update" — a maintainability claim that doesn't actually hold once examined.

**Model answer:** *"I'd keep them separate — an Ansible role for the VM path, a Helm chart for the Kubernetes path — because the actual task content for each is entirely different regardless of how they're organized; forcing both into one role's conditionals adds real complexity without genuinely reducing duplication, since there's nothing substantive shared between 'install a package and template a config file' and 'apply a Kubernetes manifest.' What I would unify is the genuinely shared element — the same application version/artifact reference and any truly shared config values, sourced from one place both paths read from, so they can never silently drift into deploying different versions."*

**Full reference:** [Question 60: Choosing between an Ansible role and a Helm chart for the same job](../interview-questions/06-kubernetes-containers.md#question-60-choosing-between-an-ansible-role-and-a-helm-chart-for-the-same-job)

---

## Question 15
**Interviewer asks:** "Your organization's DR plan for its VM fleet relies on re-running Ansible playbooks against DR-region infrastructure — but the control node itself only exists in the primary region. What's wrong with this, architecturally?"

**Expected answer points:**
- The recovery mechanism shares fate with exactly the failure condition (primary region down) it's meant to respond to.
- Fix: a genuinely region-independent control-node capability — a standing DR-region control node, or a fast, tested, region-agnostic bootstrap procedure.
- This should be explicitly tested via a drill simulating the primary region (including its control node) being entirely unreachable.

**Follow-up questions:**
1. How is this the same underlying principle as the companion EKS repository's GitOps-controller-availability lesson?
2. How would you test this specific failure mode realistically?
3. What's the trade-off between a standing DR-region control node and an on-demand bootstrap procedure?

**Red flags:** "As long as someone can SSH in quickly during the emergency" — assumes the control node remains reachable, which is exactly the assumption a primary-region-wide outage invalidates.

**Model answer:** *"This is the 'recovery tool can't share fate with what it's recovering' principle — if the primary region is what's actually down, and the control node needed to run the recovery playbooks is only in that same region, the DR plan depends on its own execution mechanism surviving the exact disaster it exists to respond to. I'd provision a genuinely region-independent control-node capability — either a standing presence in the DR region, or a fast, tested bootstrap procedure with DR-region network access that doesn't route through primary at all — and I'd specifically test this by simulating the primary region, including its control node, as entirely unreachable during a drill, not just testing the happy path."*

**Full reference:** [Question 100: The control node that was the DR plan's weakest link](../interview-questions/11-ha-dr.md#question-100-the-control-node-that-was-the-dr-plans-weakest-link)

---

## Scoring Rubric Reference
- **1 (Beginner):** Definitions only, no production experience, no failure handling.
- **2 (Intermediate):** Understands normal implementation, limited troubleshooting, weak security/scale awareness.
- **3 (Senior):** Explains production implementation, covers validation and rollback, understands idempotency/security/maintainability.
- **4 (Lead):** Explains architecture trade-offs, covers team governance and scale, anticipates failure modes, offers preventive controls. **This is the target bar for this interview.**
- **5 (Staff/Architect):** Connects technical choices to business risk, designs for multiple teams/environments, covers blast radius/security/cost/compliance/HA/DR.

For this Lead-level mock, a candidate consistently scoring 4+ across all 15 questions is interview-ready for Lead Ansible Engineer roles. Consistent 5s suggest readiness for Staff-level interviews — try [Mock Interview 3](mock-interview-03-staff-platform-architect.md) next.
