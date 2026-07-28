# Category 13: Governance and Policy as Code

Questions 111–114 of 120. Category weight: 4 questions. Deep-dive reference: [`docs/security.md` §9](../docs/security.md#9-policy-as-code).

---

## Question 111: Tags that were supposed to be mandatory

### Scenario
Your organization mandates every resource carry `CostCenter`, `Owner`, and `Environment` tags for cost-allocation and ownership purposes. An audit finds roughly 30% of resources across the estate are missing at least one of these, despite this being "documented policy" in your engineering wiki for over a year.

### Interview Question
Design an enforcement mechanism that would actually close this gap, and explain why documentation alone didn't.

### Strong Senior-Level Answer
**Initial assessment:** "documented policy" with no enforcement mechanism is a request, not a control — it depends entirely on every engineer remembering and correctly applying it on every resource, across every module, indefinitely, which predictably degrades over time exactly as this 30% gap demonstrates.

**Technical reasoning:** enforcement needs to happen at the plan-review layer (policy-as-code, catching missing tags before merge/apply) and, ideally, be structurally simplified via `default_tags` at the provider level so engineers don't need to remember to add these three tags to every individual resource in the first place — reducing reliance on memory rather than only adding a gate that rejects mistakes after the fact.

**Investigation process:** determine why the 30% gap accumulated — is it legacy resources predating the policy (expected, addressable via a one-time remediation sweep) or ongoing new resources still failing to comply (indicating the lack of enforcement is actively causing new violations, not just carrying forward old debt)?

**Recommended solution:** add `default_tags` at every provider configuration (covering the three mandatory tags with sensible defaults or required-variable-driven values) so compliance is the path of least resistance rather than an extra manual step; add an OPA/Conftest policy-as-code rule denying any plan introducing a resource missing these tags, as the actual enforcement gate; and run a one-time remediation sweep (via Terraform or a tagging API call, depending on whether the untagged resources are Terraform-managed) to close the gap for the existing 30%.

**Risk controls:** the policy-as-code rule needs to correctly account for resource types that genuinely don't support tagging (rare, but exists) to avoid false-positive blocks — a rule that's too broad and blocks legitimate untaggable resources will itself get worked around/disabled by frustrated teams, undermining the whole enforcement effort.

**Validation steps:** after implementing `default_tags` and the policy gate, re-run the tag-compliance audit and confirm the gap has closed for new resources going forward (existing gap requires the separate remediation sweep to close retroactively).

**Rollback or recovery strategy:** not applicable — this is additive governance tooling; if the policy rule proves too strict and blocks legitimate work, adjust its resource-type exceptions deliberately rather than disabling the rule entirely.

**Long-term prevention:** report tag-compliance percentage as an ongoing, visible metric (not just a one-time audit) so any future regression is caught early rather than allowed to silently accumulate to 30% again over another year.

### Step-by-Step Implementation
```hcl
# Reduce reliance on memory: default_tags at every provider configuration
provider "aws" {
  default_tags {
    tags = {
      CostCenter  = var.cost_center
      Owner       = var.owner_team
      Environment = var.environment
    }
  }
}
```
```rego
# Enforcement gate: policy-as-code rule denying non-compliant resources
package main

taggable_types := {"aws_instance", "aws_db_instance", "aws_s3_bucket", "aws_lb"}

deny[msg] {
  resource := input.resource_changes[_]
  taggable_types[resource.type]
  required := {"CostCenter", "Owner", "Environment"}
  missing := required - {k | resource.change.after.tags_all[k]}
  count(missing) > 0
  msg := sprintf("%s: missing required tags: %v", [resource.address, missing])
}
```
```bash
# One-time remediation sweep for existing 30% gap (Terraform-managed resources)
terraform plan   # after adding default_tags, shows the tag additions needed for existing resources
terraform apply
```

### Under-the-Hood Explanation
`default_tags` at the provider level is merged into every applicable resource's `tags_all` computed attribute automatically at plan/apply time (see [Question 39 in category 4](04-providers.md#question-39-the-tag-that-wouldnt-stay-put) for the merge mechanics) — this removes the need for individual engineers to remember to add these tags to every resource block, while the policy-as-code rule provides an independent, structural check against the final computed tag set in the plan JSON, catching any resource that somehow still lacks required tags (a resource-level tag override that accidentally removes one, or a resource type/module that bypasses the provider-level default for some reason).

### Common Weak Answer
"Send a reminder email to the engineering organization about the tagging policy."

### Why the Weak Answer Fails
This is exactly the "documented policy" approach that already failed to prevent a 30% gap over a full year — a reminder doesn't change the underlying dynamic (a manual, memory-dependent step that will keep being missed by some fraction of changes indefinitely); the fix needs to be structural (default_tags plus a policy gate), not another appeal to remember correctly.

### Follow-Up Questions
1. How would you handle resource types that genuinely can't support the standard tagging schema?
2. How would you design the remediation sweep to avoid accidentally triggering unwanted replacements on the 30% of already-existing resources?
3. How would you extend this tag-governance approach to also cover resources created outside Terraform entirely (manual console changes)?

### Key Interview Signals
Confirms the candidate recognizes documentation-only policy as a non-control and designs both a structural simplification (`default_tags`) and an actual enforcement gate (policy-as-code), rather than proposing another reminder.

### Hands-On Connection
[Lab 13 — Policy as Code](../labs/lab-13-policy-as-code/).

---

## Question 112: The instance type nobody could justify

### Scenario
A cost review finds several `m5.24xlarge` instances (a very large, expensive instance type) provisioned in a development environment, apparently by an engineer testing something that didn't need that scale, and forgotten about for two months at meaningful ongoing cost.

### Interview Question
Design a policy-as-code control preventing oversized instance types in non-production environments, without being so rigid it blocks genuine, occasional legitimate needs.

### Strong Senior-Level Answer
**Initial assessment:** this needs a per-environment size ceiling (dev/staging should have a much lower maximum instance size than production) enforced as a hard gate, combined with a defined, low-friction exception path for the genuine, occasional case where a larger instance really is needed temporarily (e.g., a specific performance-testing exercise).

**Technical reasoning:** a flat organization-wide instance-size limit doesn't work, since production may legitimately need larger instances than dev/staging ever should — the policy needs to be environment-aware, checking the instance type against a ceiling that varies by the `Environment` tag/workspace.

**Investigation process:** survey what instance sizes are actually, legitimately used in dev/staging today to set a sensible default ceiling that doesn't immediately block normal, existing usage — the goal is catching genuine outliers like `m5.24xlarge` in dev, not making every existing dev instance suddenly non-compliant.

**Recommended solution:** implement an OPA/Conftest rule denying any instance type above a defined size tier for non-production environments (e.g., nothing larger than `xlarge` in dev/staging without an explicit, tracked exception), with a documented exception mechanism (a tagged, time-bound override requiring a linked justification, similar to the suppression-governance pattern from [Question 61 in category 7](07-security.md#question-61-the-finding-that-got-a-skip-comment-instead-of-a-fix)) for genuine temporary needs.

**Risk controls:** pair the policy gate with a scheduled cost-anomaly check (per [Question 47 in category 5](05-aws-architecture.md#question-47-the-nat-gateway-bill-nobody-explained)) as a backstop catching anything that slips through via a legitimate-looking exception that then overstays its intended, time-bound duration.

**Validation steps:** test the policy against both a legitimate small dev instance (should pass) and a deliberately oversized one (should be denied) to confirm correct behavior before rolling out broadly; confirm the exception mechanism works for a genuine test case.

**Rollback or recovery strategy:** for the specific `m5.24xlarge` instances already running, right-size or terminate them once confirmed unnecessary, and add the policy gate going forward so this doesn't recur silently.

**Long-term prevention:** report a regular cost/rightsizing dashboard highlighting any instance running above its environment's expected ceiling (even ones passing through a legitimate exception) so oversized instances don't just get gated at creation but are also visible on an ongoing basis if they persist longer than intended.

### Step-by-Step Implementation
```rego
package main

max_instance_size := {
  "development": {"t3.large", "t3.xlarge", "m5.large", "m5.xlarge"},
  "staging":     {"t3.xlarge", "m5.xlarge", "m5.2xlarge"},
}

deny[msg] {
  resource := input.resource_changes[_]
  resource.type == "aws_instance"
  env := resource.change.after.tags_all.Environment
  allowed := max_instance_size[env]
  allowed
  not allowed[resource.change.after.instance_type]
  not resource.change.after.tags_all["SizeExceptionTicket"]   # documented exception path
  msg := sprintf("%s: instance_type %s exceeds allowed size for %s environment", 
                 [resource.address, resource.change.after.instance_type, env])
}
```
```hcl
# Legitimate, tracked exception path
resource "aws_instance" "load_test_runner" {
  instance_type = "m5.24xlarge"
  tags = {
    Environment        = "development"
    SizeExceptionTicket = "PERF-1102"   # documented, time-bound justification
  }
}
```

### Under-the-Hood Explanation
The policy rule evaluates the plan JSON's `resource_changes` for `aws_instance` resources, looking up the environment-specific allowed-size set from the resource's own `Environment` tag and denying anything outside that set unless a specific exception-tracking tag is also present — this runs entirely against the static plan output (see [`security.md` §9](../docs/security.md#9-policy-as-code)), meaning the check happens before any apply, catching the oversized instance type at PR-review time rather than after cost has already been incurred, which is the whole point relative to only catching it via a retrospective cost review as happened in this scenario.

### Common Weak Answer
"Set a single organization-wide maximum instance size for everything."

### Why the Weak Answer Fails
A flat organization-wide ceiling either has to be set high enough to accommodate legitimate production needs (in which case it does nothing to prevent oversized dev instances, since the ceiling is too permissive for that environment) or low enough to catch dev misuse (in which case it incorrectly blocks legitimate production sizing) — the policy needs to be environment-aware to serve both purposes correctly.

### Follow-Up Questions
1. How would you extend this pattern to other cost-relevant resource types beyond EC2 instances (RDS instance classes, EBS volume sizes)?
2. How would you handle a legitimate, recurring need for larger dev instances (e.g., a data science team that regularly needs GPU instances for testing) without constant one-off exceptions?
3. How would you measure whether this policy actually reduced unnecessary cost, versus just moving the same spend into tracked exceptions?

### Key Interview Signals
Confirms the candidate designs environment-aware policy rules (not a flat, one-size-fits-all ceiling) with a genuine, tracked exception path, balancing enforcement against legitimate flexibility rather than either extreme.

### Hands-On Connection
[Lab 13 — Policy as Code](../labs/lab-13-policy-as-code/).

---

## Question 113: The exception that had no expiration date

### Scenario
Your policy-as-code framework supports exceptions (a tagged override allowing a specific, otherwise-denied configuration). An audit finds 200 active exceptions across the organization, some going back over two years, with no process for reviewing whether any of them are still needed.

### Interview Question
Redesign the exception process so it remains a legitimate governance tool rather than a permanent, unaudited backdoor.

### Strong Senior-Level Answer
**Initial assessment:** an exception mechanism with no expiration or review cadence inevitably accumulates into exactly this state — 200 unaudited, indefinitely-living exceptions provide essentially the same governance gap as having no policy at all for whatever those 200 specific cases cover, just with an appearance of control that doesn't reflect reality.

**Technical reasoning:** every legitimate exception mechanism needs three properties to remain meaningful over time: a mandatory justification (why this specific exception is needed), an expiration/review date (forcing periodic reconsideration rather than indefinite persistence), and visibility (someone tracking the current live exception count and their ages as an ongoing metric, not just at audit time).

**Investigation process:** for the current 200 exceptions, categorize by age and by whether the original justification is still verifiably applicable — likely a meaningful fraction are stale (the underlying need has since resolved) and simply were never revisited because nothing forced that revisit.

**Recommended solution:** redesign the exception mechanism to require an explicit expiration date at creation time (e.g., 90 days, renewable via a fresh, reviewed justification, not an automatic rollover), and build a scheduled report (or a policy-as-code check itself) flagging any exception past its expiration date as a hard failure requiring immediate renewal or removal — not a soft warning that can be ignored indefinitely.

**Risk controls:** for the retroactive cleanup of the current 200, require every one to go through the new renewal process (fresh justification, fresh expiration date) rather than grandfathering them in indefinitely — this forces exactly the review that should have been happening all along.

**Validation steps:** after implementing expiration enforcement, confirm the policy engine actually blocks an exception past its expiration date in a test case, and confirm the renewal process correctly extends a genuinely-still-needed exception.

**Rollback or recovery strategy:** not applicable — this is a governance-process redesign; for any of the 200 that turn out to no longer be needed once actually reviewed, remove the exception and confirm the underlying resource now complies with the policy without it (or gets remediated if it doesn't).

**Long-term prevention:** report the live exception count (and their ages/upcoming expirations) as a standing governance metric to leadership, making exception accumulation visible on an ongoing basis rather than something only discovered via periodic audits like this one.

### Step-by-Step Implementation
```hcl
resource "aws_instance" "legacy_app" {
  # ...
  tags = {
    PolicyException      = "public-sg-allowed"
    ExceptionJustification = "Legacy vendor integration requires public access - JIRA-4821"
    ExceptionExpiresOn    = "2026-10-24"   # mandatory, renewable, not indefinite
  }
}
```
```rego
package main

deny[msg] {
  resource := input.resource_changes[_]
  exception := resource.change.after.tags_all.PolicyException
  exception != ""
  expires := time.parse_rfc3339_ns(resource.change.after.tags_all.ExceptionExpiresOn)
  expires < time.now_ns()
  msg := sprintf("%s: policy exception '%s' expired on %s - renew or remove", 
                 [resource.address, exception, resource.change.after.tags_all.ExceptionExpiresOn])
}
```
```bash
# Scheduled report: exceptions approaching expiration, for proactive renewal
# rather than discovering expiry via a blocked pipeline
```

### Under-the-Hood Explanation
Encoding the expiration date directly as a checked policy condition (rather than only as documentation) means the policy engine itself enforces the review cadence — a plan referencing an expired exception fails the same `deny` gate as any other non-compliant configuration, converting "someone should periodically review exceptions" from a hoped-for process into an automatically-enforced one, exactly mirroring the broader theme across this repository of converting process reminders into structural, testable controls.

### Common Weak Answer
"Just review all 200 exceptions once now to clean them up."

### Why the Weak Answer Fails
A one-time cleanup addresses today's backlog but does nothing to prevent the same accumulation recurring over the next two years, since the underlying exception mechanism still has no expiration/review enforcement — the systemic fix (expiration dates enforced by the policy engine itself) is what prevents this exact audit finding from recurring.

### Follow-Up Questions
1. How would you handle a genuinely permanent, unlikely-to-ever-change exception (e.g., a legacy system that will never be updated) without forcing pointless repeated renewals?
2. How would you prioritize which of the 200 existing exceptions to review first, given limited time?
3. How would you extend this expiration-enforcement pattern to non-policy-as-code exceptions, like an SCP exception or a manually-granted IAM permission?

### Key Interview Signals
Confirms the candidate designs the exception mechanism itself to be self-limiting (expiration enforced by the policy engine) rather than relying on a one-time cleanup or an unenforced review reminder, consistent with the broader "structural control over process reminder" theme throughout this repository.

### Hands-On Connection
[Lab 13 — Policy as Code](../labs/lab-13-policy-as-code/).

---

## Question 114: Telling leadership whether governance is actually working

### Scenario
Your VP of Engineering asks for a monthly report on "how well we're doing on infrastructure governance" across the organization's Terraform estate, but has no specific metric in mind — just a general sense that they want visibility.

### Interview Question
Design the actual metrics and reporting structure you'd propose.

### Strong Senior-Level Answer
**Initial assessment:** "how well are we doing on governance" is vague enough to be answered with almost anything, which is itself a problem — the useful response is proposing concrete, specific, trackable metrics that actually reflect governance health, rather than either guessing what the VP wants or producing a report so broad it doesn't inform any actual decision.

**Technical reasoning:** meaningful governance metrics for a Terraform estate span several dimensions already touched on throughout this repository: policy compliance rate (percentage of plans passing policy-as-code gates without needing an exception), exception health (count of active exceptions, their ages, how many are past expiration per [Question 113](#question-113-the-exception-that-had-no-expiration-date)), tag compliance (per [Question 111](#question-111-tags-that-were-supposed-to-be-mandatory)), security scan finding trends (are Checkov/Trivy findings trending down over time, or accumulating faster than they're resolved), and state/access hygiene (how many state buckets/backends meet the encryption/access-control baseline from [`security.md`](../docs/security.md)).

**Investigation process:** confirm with the VP which of these dimensions actually maps to decisions they'd make differently based on the number — a metric nobody would ever act on, regardless of its value, isn't worth the ongoing reporting overhead.

**Recommended solution:** propose a concise monthly dashboard covering: policy compliance rate and trend, active exception count/age distribution, tag compliance percentage, and security-scan finding backlog trend — each with a brief "what changed and why" narrative rather than raw numbers alone, since a VP-level audience needs the interpretation, not just the data.

**Risk controls:** avoid a report so comprehensive it becomes noise — pick a small number of genuinely decision-relevant metrics rather than every possible governance signal, and be willing to retire a metric later if it turns out not to actually inform anything.

**Validation steps:** after the first month or two of reporting, check with the VP whether the metrics are actually useful for the decisions they're making, and adjust based on that feedback rather than assuming the initial proposal is permanently correct.

**Rollback or recovery strategy:** not applicable — this is a reporting-design exercise; if a metric proves unhelpful or misleading, revise or remove it in a subsequent report cycle.

**Long-term prevention:** treat the governance dashboard itself as something to periodically re-evaluate for relevance as the organization's actual governance maturity and priorities evolve — a set of metrics appropriate for an organization just starting to adopt policy-as-code looks different from one with a mature, multi-year governance program.

### Step-by-Step Implementation
```markdown
<!-- Monthly Governance Report skeleton -->
## Infrastructure Governance — [Month Year]

**Policy compliance rate:** 94% of plans passed policy gates without exception (up from 91% last month)
**Active exceptions:** 42 total, 3 past expiration (down from 51 total, 12 past expiration)
**Tag compliance:** 96% of resources carry all required tags (target: 98% by Q4)
**Security scan backlog:** 18 open findings, trending down (23 last month), 0 critical-severity open >30 days

**Narrative:** [What drove the changes this month, any notable incidents or remediation pushes]
```
```bash
# Underlying data sources for the dashboard, aggregated monthly
conftest test --output json $(find . -name '*.tfplan.json') | jq '[.[] | .failures | length] | add'
grep -c 'PolicyException' $(find . -name '*.tf') 
```

### Under-the-Hood Explanation
None of these metrics require novel tooling — they're aggregations of signals already produced by the policy-as-code pipeline (pass/fail results per plan), the tagging policy check (per Question 111), and the security scanner's own output (per [`security.md` §8](../docs/security.md#8-static-analysis-and-iac-scanning)) — the actual work is in aggregating these into a monthly rollup with trend comparison, rather than building any new detection mechanism specifically for reporting purposes.

### Common Weak Answer
"Just show them the number of Terraform runs per month and how many succeeded."

### Why the Weak Answer Fails
Run success/failure rate says almost nothing about governance specifically — a plan can succeed while still representing a security or compliance gap (if no policy gate exists to catch it), or fail for entirely unrelated reasons (a transient API error); this metric doesn't actually answer "how well are we doing on governance" in any meaningful sense.

### Follow-Up Questions
1. How would you handle a metric that looks good on paper (e.g., high policy compliance rate) but is actually being gamed via overly broad exceptions?
2. How would you present this data differently to an engineering audience (who might want more technical detail) versus the VP (who wants a higher-level summary)?
3. How would you know if your governance program is actually improving security/compliance outcomes, versus just producing better-looking metrics?

### Key Interview Signals
Confirms the candidate can translate a vague leadership request into concrete, decision-relevant metrics grounded in tooling that already exists, rather than either guessing at an arbitrary metric or producing an overwhelming, unfocused report.

### Hands-On Connection
[Lab 13 — Policy as Code](../labs/lab-13-policy-as-code/).
