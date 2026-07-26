# Category 1: Terraform Core Language and Workflow

Questions 1–10 of 120. Category weight: 10 questions. Deep-dive reference: [`docs/terraform-internals.md`](../docs/terraform-internals.md).

---

## Question 1: The subnet that shifted

### Scenario
Your team manages six private subnets, one per AZ, using `count = length(var.azs)` and indexing into `var.azs[count.index]` for each subnet's AZ and CIDR. A teammate removes the first AZ (`us-east-1a`) from `var.azs` because that AZ is being decommissioned from the account. They run `terraform plan` expecting one subnet to be destroyed.

### Interview Question
The plan instead shows five subnets being destroyed and recreated, and only one truly new one. Why did this happen, and how would you have designed this to avoid it?

### Strong Senior-Level Answer
**Initial assessment:** this is the classic `count` index-shifting failure. `count` gives each resource instance a purely positional identity (`aws_subnet.private[0]`, `[1]`, `[2]`...). Removing the first element of the list doesn't delete index 0 and leave the rest alone — every subsequent element shifts down one position, so index 0 now refers to what used to be index 1's AZ/CIDR, index 1 refers to what used to be index 2's, and so on. Terraform doesn't see "AZ us-east-1a was removed"; it sees "the configuration for `aws_subnet.private[0]` changed, and for `[1]`, and for `[2]`..." — each of which, because AZ and CIDR are typically `ForceNew` attributes, becomes a destroy-and-recreate.

**Technical reasoning:** the root cause is that resource *identity* (the count index) and resource *meaning* (which AZ/CIDR it represents) are decoupled — identity stayed at position, meaning moved. This is not a bug; it's how `count` is specified to work.

**Investigation process:** confirm via `terraform plan` output which specific subnets are marked `-/+` and cross-reference the `# forces replacement` annotations against the AZ/CIDR attributes — this confirms the index-shift theory versus some other unrelated cause.

**Recommended solution:** stop the plan from being applied. Do not apply an "everything shifts" plan against production networking — this would drop and recreate five subnets' worth of ENIs, breaking anything with a hardcoded dependency on those specific subnet IDs (route table associations, existing instances, RDS subnet groups) simultaneously. Migrate the resource to `for_each` keyed by AZ name (a stable identifier), e.g. `for_each = toset(var.azs)`, referencing `each.key` instead of `count.index`. Use `terraform state mv` (or `moved` blocks) to remap each existing `aws_subnet.private[N]` to `aws_subnet.private["us-east-1b"]` etc., for every subnet that isn't actually being removed, so the migration itself produces a zero-diff plan except for the one genuinely-removed AZ.

**Risk controls:** perform the `state mv` migration resource-by-resource, running `plan` after each to confirm zero unexpected diff before moving to the next.

**Validation steps:** final `terraform plan` should show exactly one subnet destroyed (the decommissioned AZ) and zero replacements for the remaining five.

**Rollback or recovery strategy:** since this was caught at plan time (never applied), rollback is simply not applying; if it had already been applied, recovery would require restoring from the affected resources' dependents (route tables, ASG subnet references) and likely an outage window to re-provision — reinforcing why this must be caught at plan review, not fixed post-incident.

**Long-term prevention:** default to `for_each` for any resource collection whose membership can change over time; reserve `count` for the 0/1 conditional-resource idiom and truly fixed-cardinality sets.

### Step-by-Step Implementation
```hcl
# Before (fragile)
resource "aws_subnet" "private" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.main.id
  availability_zone = var.azs[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
}

# After (stable identity)
resource "aws_subnet" "private" {
  for_each          = toset(var.azs)
  vpc_id            = aws_vpc.main.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, index(var.azs, each.key))
}
```
```bash
# Migration (repeat per remaining AZ before removing the decommissioned one)
terraform state mv 'aws_subnet.private[1]' 'aws_subnet.private["us-east-1b"]'
terraform plan   # confirm zero diff for this subnet
# ... repeat for indices 2-5 ...
# Only then remove "us-east-1a" from var.azs and apply the single intended destroy
```

### Under-the-Hood Explanation
Terraform's resource addressing scheme (see [`terraform-internals.md` §3](../docs/terraform-internals.md#3-resource-addressing)) treats `count.index` as part of the address. During plan, Terraform diffs *by address* — it has no semantic understanding that `[0]` "used to mean" AZ-a and now the same address's config means AZ-b; it only sees that the configuration bound to `aws_subnet.private[0]` has different `availability_zone`/`cidr_block` values than the state entry at that same address, and because those attributes are `ForceNew` in the AWS provider schema, the diff becomes a replacement (destroy + create) rather than an update. `for_each`'s map-keyed addressing (`aws_subnet.private["us-east-1b"]`) makes the address itself carry semantic meaning, so removing one key only affects the state entry for that exact key.

### Common Weak Answer
"Terraform recreated the subnets because the CIDR blocks changed — we should just apply it and let Terraform sort out the networking, since it'll all reconcile once it's done."

### Why the Weak Answer Fails
It doesn't identify the root mechanical cause (positional identity vs. semantic meaning), doesn't recognize this as a five-subnet outage waiting to happen, and "let Terraform sort out the networking" ignores that ENIs, route table associations, and anything else referencing the old subnet IDs will break the moment those subnets are destroyed — Terraform does not perform any kind of safe, ordered cutover for this scenario without explicit `for_each`/`moved` remediation.

### Follow-Up Questions
1. If this had already been applied in production before anyone noticed, what would your incident response look like?
2. How would you design a module input validation to catch a caller passing a list with a removed middle element, before it ever reaches this state?
3. Does converting to `for_each` fully eliminate this class of risk for every kind of resource collection, or are there still edge cases (e.g., a map value change that's itself `ForceNew`)?

### Key Interview Signals
Distinguishes candidates who've merely heard "prefer for_each" from those who understand *why* at the addressing/diffing level, and who default to a safe, incremental migration rather than a big-bang state change.

### Hands-On Connection
[Lab 7 — Refactoring Without Recreation](../labs/lab-07-refactoring-state/) reproduces this exact migration and proves zero-diff `state mv`/`moved` block outcomes.

---

## Question 2: The security group nobody could safely resize

### Scenario
A module manages ingress rules for a shared application security group using `dynamic "ingress"` blocks driven by a list variable. Product teams frequently add/remove ports from the list. Every change to the list — even adding one new port — currently causes the security group resource to show a full in-place update touching every existing rule, and once, a change accidentally set the CIDR to `0.0.0.0/0` for an internal-only port without anyone catching it in review.

### Interview Question
How would you redesign this configuration to make individual rule changes minimal-diff, and to make it structurally impossible for a public CIDR to slip into an internal-only rule set?

### Strong Senior-Level Answer
**Initial assessment:** two separate problems — a diff-noise problem (using a list for something that should be keyed) and a missing-guardrail problem (no validation on CIDR values).

**Technical reasoning:** `dynamic` blocks driven by a `list`-typed variable produce ordinally-indexed nested blocks — reordering or inserting into the middle of the list changes every subsequent block's position in Terraform's diff, even for security-group-rule resources that support independent rule resources. Using a `map`/`set` keyed by a stable identifier (e.g., a descriptive rule name) and, more importantly, using **separate `aws_security_group_rule` (or `aws_vpc_security_group_ingress_rule`) resources with `for_each`** instead of inline `dynamic` blocks inside the security group resource, decouples each rule's lifecycle from the others entirely.

**Investigation process:** confirm via `terraform plan` on a single-item change to the rule list whether the diff touches only the changed rule or the whole security group resource — this is the fastest way to prove the diff-noise problem to a skeptical team.

**Recommended solution:** move to standalone rule resources keyed by name, and add a `validation` block on the rules variable rejecting any CIDR of `0.0.0.0/0` unless an explicit `allow_public = true` flag is also set per-rule (an intentional, reviewable escape hatch, not a silent default).

**Risk controls:** pair the validation block with a policy-as-code check (Conftest/OPA) in CI as defense-in-depth, since `validation` blocks only run for people actually invoking `terraform plan/apply` locally with the right variables — a policy gate catches it regardless of entry point, including a plan generated by automation with different variable sourcing.

**Validation steps:** unit test (`terraform test`, plan-mode) asserting the validation block rejects an unqualified `0.0.0.0/0` rule and accepts one with `allow_public = true`.

**Rollback or recovery strategy:** migrating from inline `dynamic` blocks to standalone rule resources requires `state mv`/`moved` blocks resource-by-resource to avoid destroy/recreate of every existing rule — verify zero-diff before considering the migration complete.

**Long-term prevention:** treat "does this input variable admit a value that would create a public-facing hole" as a mandatory validation question for every security-relevant module input, not just security groups.

### Step-by-Step Implementation
```hcl
variable "ingress_rules" {
  type = map(object({
    from_port    = number
    to_port      = number
    protocol     = string
    cidr_blocks  = list(string)
    allow_public = optional(bool, false)
  }))

  validation {
    condition = alltrue([
      for k, r in var.ingress_rules :
      r.allow_public || !contains(r.cidr_blocks, "0.0.0.0/0")
    ])
    error_message = "Rule '${keys(var.ingress_rules)}' uses 0.0.0.0/0 without allow_public = true."
  }
}

resource "aws_vpc_security_group_ingress_rule" "this" {
  for_each          = var.ingress_rules
  security_group_id = aws_security_group.app.id
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  ip_protocol       = each.value.protocol
  cidr_ipv4         = each.value.cidr_blocks[0]
}
```

### Under-the-Hood Explanation
Standalone rule resources each get their own resource address (`aws_vpc_security_group_ingress_rule.this["web-443"]`), so the dependency graph and diff calculation treat each rule as fully independent — adding or removing one key has zero effect on any other rule's plan entry. `validation` blocks execute during the plan graph walk, before any resource operations are attempted, so a rejected input fails fast without ever reaching a provider RPC call.

### Common Weak Answer
"We should just be more careful in code review to catch public CIDRs."

### Why the Weak Answer Fails
Human review is not a control — it's a hope. It doesn't scale, doesn't catch automation-generated changes, and is exactly the process that already failed once in this scenario. Senior answers convert "be careful" into a structural, testable, CI-enforced guarantee.

### Follow-Up Questions
1. How would you handle a legitimate, reviewed exception where a rule genuinely needs to be public (e.g., a public ALB health check port)?
2. What's the difference in blast radius between a validation block failure and a policy-as-code failure, and why do you need both?
3. How would this design change if the security group needed to support thousands of dynamically-managed rules (e.g., per-tenant rules in a multi-tenant SaaS)?

### Key Interview Signals
Tests whether the candidate reaches for structural/testable controls (typed variables, validation blocks, policy-as-code) versus process-based controls (review, tribal knowledge) for security-critical configuration.

### Hands-On Connection
[Lab 4 — Production Module Design](../labs/lab-04-module-design/) and [Lab 13 — Policy as Code](../labs/lab-13-policy-as-code/).

---

## Question 3: Decommissioning a `prevent_destroy`-protected resource

### Scenario
A production RDS instance has `lifecycle { prevent_destroy = true }` set, correctly, to avoid accidental deletion. The application it serves is being fully decommissioned as part of a planned sunset, and the database must now actually be deleted as part of that approved project.

### Interview Question
Walk me through exactly how you would safely remove this protected resource, including what could go wrong.

### Strong Senior-Level Answer
**Initial assessment:** `prevent_destroy` is a Terraform-Core, plan-time-only guard — it has no AWS-side effect and exists purely to make `plan`/`apply` error out if the plan would destroy this resource. Decommissioning it requires deliberately removing that guard in a reviewed, auditable way — never bypassing it via `state rm` plus a manual console deletion, which desyncs state from reality and leaves no clean record.

**Technical reasoning:** the correct sequence separates "authorize the destroy" from "perform the destroy" into two distinct, independently reviewable steps, so a plan can be inspected between them.

**Investigation process:** before touching anything, confirm this is genuinely the only resource depending on nothing else expecting this database to exist — check for any other Terraform-managed resource (security group rules referencing it, IAM policies, application configs pulling its endpoint from a data source or parameter store) that would break, and confirm a final backup/snapshot policy is satisfied per any compliance/retention requirement for this data.

**Recommended solution:**
1. In a dedicated, reviewed PR, remove (or set to `false`) the `prevent_destroy` lifecycle argument only — no other changes in this commit.
2. Run `terraform plan` and confirm the plan shows **only** a no-op (lifecycle metadata changes don't themselves trigger a destroy) — this step alone should produce zero destructive diff.
3. In a **second**, separate PR/step, remove the resource block itself (or use a `removed` block, Terraform >= 1.7, which lets you record the decommission declaratively and optionally control whether the actual cloud resource is destroyed).
4. Run `terraform plan` again and verify **exactly** the intended RDS instance (and only genuinely-dependent resources, if any) appear as destroy.

**Risk controls:** require a manual approval gate on this specific apply (see [`cicd.md`](../docs/cicd.md#4-apply-approvals-and-environment-protection)), and take a final manual DB snapshot immediately before apply regardless of automated backup policy, as a deliberate belt-and-suspenders step for an irreversible action.

**Validation steps:** after apply, confirm via the AWS console/CLI (not just Terraform state) that the instance is gone and no orphaned dependent resources (subnet groups, parameter groups left dangling) remain if they were meant to go too.

**Rollback or recovery strategy:** once destroyed, "rollback" means restoring from the final snapshot into a new instance — the original instance cannot be un-deleted. This is why the two-step, reviewed, plan-verified sequence matters far more than for a reversible change.

**Long-term prevention:** document this exact two-step pattern as the org's standard decommissioning runbook so no one is tempted to shortcut via `state rm` + manual deletion under time pressure.

### Step-by-Step Implementation
```hcl
# Step 1 PR: remove only the lifecycle guard
resource "aws_db_instance" "legacy_app" {
  # ... unchanged arguments ...
  # lifecycle { prevent_destroy = true }   <- removed
}
```
```bash
terraform plan   # expect: no changes (lifecycle-only edit)
terraform apply
```
```hcl
# Step 2 PR (after final snapshot confirmed): removed block (Terraform >= 1.7)
removed {
  from = aws_db_instance.legacy_app

  lifecycle {
    destroy = true
  }
}
```
```bash
terraform plan   # expect: exactly one destroy, this resource only
terraform apply
```

### Under-the-Hood Explanation
`prevent_destroy` is evaluated by Terraform Core during plan construction: if the computed diff for a resource includes a destroy operation and its lifecycle block sets `prevent_destroy = true`, Core raises an error before the plan is even fully rendered, regardless of whether the destroy came from a removed resource block, a `for_each`/`count` shrink, or a forced replacement. A `removed` block is processed during graph construction as an explicit instruction to drop the resource from both configuration and (optionally) the cloud, giving you a reviewable diff for the decommission itself rather than relying on simply deleting the resource block (which produces the same destroy plan but with less clear version-control intent).

### Common Weak Answer
"Just run `terraform state rm` on it and then delete it manually in the console since `prevent_destroy` is blocking us."

### Why the Weak Answer Fails
This bypasses Terraform's own safety mechanism, leaves Terraform state and cloud reality desynced (state still shows nothing changed vs. reality showing it's gone as an unmanaged deletion outside Terraform's records), and produces no reviewable audit trail tying the deletion to the approved decommission project.

### Follow-Up Questions
1. What if another team's Terraform configuration references this database's endpoint via `terraform_remote_state` — how does that change your sequencing?
2. How would you design a policy-as-code rule that still allows this two-step decommission while blocking someone from just deleting the lifecycle block and the resource in the same commit?
3. How does this differ for a resource that has `create_before_destroy = true` as well — could that interact badly with a destroy-only change?

### Key Interview Signals
Confirms the candidate knows `prevent_destroy` is a plan-time-only guard (not an AWS control), and defaults to a reviewable, staged, snapshot-before-destroy process for irreversible actions rather than a state-mutation shortcut.

### Hands-On Connection
[Lab 4 — Production Module Design](../labs/lab-04-module-design/) (implementing the guard) and [Lab 14 — Drift, Failure, and Recovery](../labs/lab-14-drift-and-recovery/) (practicing controlled, irreversible-change runbooks).

---

## Question 4: The launch template nobody could safely swap

### Scenario
An Auto Scaling Group references a launch template. The AMI ID and `user_data` are baked into the launch template's own resource. Whenever the AMI is updated, the launch template resource is replaced (new version), but instances already running under the ASG don't get refreshed automatically, and one release, `user_data` changed silently (a config bug fix) without the AMI changing at all, and nobody realized instances hadn't picked up the fix for two weeks.

### Interview Question
How would you use lifecycle meta-arguments to guarantee that any meaningful change to the launch template — AMI or user_data — reliably triggers an instance refresh, without manual intervention?

### Strong Senior-Level Answer
**Initial assessment:** two related problems: (1) the launch template's own replacement doesn't automatically mean the ASG's *running instances* get replaced — that's a separate, explicit concern (instance refresh), and (2) `user_data` changes alone weren't being tracked as a trigger for anything, because nothing was watching that specific attribute across resources.

**Technical reasoning:** `replace_triggered_by` exists precisely for "these two things are logically coupled even though the provider schema doesn't model that coupling as a direct reference." Coupling an ASG's instance refresh mechanism to a hash of user_data plus the AMI ID makes the trigger explicit and version-controlled rather than relying on operators noticing.

**Investigation process:** confirm via `terraform plan` on a `user_data`-only change today whether *anything* shows a diff beyond the launch template resource itself — if the ASG shows no change at all, that confirms the missing linkage.

**Recommended solution:** use the ASG resource's native `instance_refresh` block (AWS ASG feature, exposed by the provider) triggered by launch template version changes, combined with `replace_triggered_by` on any auxiliary resource that needs to force replacement based on a computed hash of the template content.

**Risk controls:** configure `instance_refresh` with a `min_healthy_percentage` below 100 and a reasonable `checkpoint`/pause strategy so the rollout is gradual, not a simultaneous replace-everything event that could cause a capacity/availability gap.

**Validation steps:** after applying a `user_data` change, confirm via the ASG's activity history (or `aws autoscaling describe-instance-refreshes`) that a refresh was actually triggered and completed, not just that Terraform's plan showed a new launch template version.

**Rollback or recovery strategy:** if a bad `user_data` change causes a refresh to roll out broken instances, ASG instance refresh supports rollback to the previous launch template version — practice this explicitly rather than assuming it in an incident.

**Long-term prevention:** treat any attribute that *should* trigger a rollout, but which the provider schema doesn't natively couple to instance replacement, as a candidate for either `replace_triggered_by` or a native instance-refresh trigger — don't rely on operators remembering to trigger a manual refresh.

### Step-by-Step Implementation
```hcl
resource "aws_launch_template" "app" {
  name_prefix   = "app-"
  image_id      = var.ami_id
  user_data     = base64encode(templatefile("${path.module}/user_data.sh.tftpl", var.user_data_vars))

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "app" {
  name_prefix         = "app-"
  desired_capacity    = var.desired_capacity
  min_size            = var.min_size
  max_size            = var.max_size
  vpc_zone_identifier = var.subnet_ids

  launch_template {
    id      = aws_launch_template.app.id
    version = aws_launch_template.app.latest_version
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 90
      checkpoint_percentages  = [50, 100]
      checkpoint_delay        = 600
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}
```

### Under-the-Hood Explanation
`create_before_destroy` on the launch template (needed because `name_prefix`, not a fixed `name`, avoids a naming collision during replacement) means Terraform provisions the new template version before removing the old one — necessary because the ASG resource references the template by ID/version and can't tolerate a gap. The ASG's `instance_refresh` block is interpreted by the AWS provider as configuration for AWS's own native instance-refresh feature — Terraform's role is limited to *declaring* the desired refresh strategy; AWS's ASG service actually executes the gradual rollout, checkpointing, and rollback logic, outside of any further Terraform apply.

### Common Weak Answer
"We should just always run `terraform apply` twice — once for the launch template, once to manually cycle instances."

### Why the Weak Answer Fails
Manual, human-remembered cycling is exactly the process that already failed for two weeks in this scenario. It also doesn't provide a gradual, health-checked rollout — a manual "terminate all instances" approach risks a full capacity gap and doesn't roll back automatically if the new instances are unhealthy.

### Follow-Up Questions
1. How would `replace_triggered_by` be used instead of/in addition to `instance_refresh`, and when would you prefer one over the other?
2. What happens to in-flight connections/requests during a rolling instance refresh, and how does that inform your `min_healthy_percentage` and checkpoint choices?
3. How would you extend this pattern to a Kubernetes node group instead of a raw ASG — does EKS managed node group upgrade behave the same way?

### Key Interview Signals
Distinguishes candidates who know lifecycle meta-arguments exist from those who can compose them (`create_before_destroy` + `replace_triggered_by`/native instance refresh) into a genuinely safe, gradual, self-healing rollout mechanism.

### Hands-On Connection
[Lab 4 — Production Module Design](../labs/lab-04-module-design/).

---

## Question 5: The `ignore_changes = all` module nobody trusted

### Scenario
A module managing EC2 instances sets `lifecycle { ignore_changes = all }` on every instance resource because "some team keeps changing tags and instance types manually and we got tired of Terraform fighting them." Now `terraform plan` shows a clean, quiet diff every time, but nobody actually knows what's really running versus what the configuration says should be running, and a recent incident involved an instance type that had been silently downsized months ago by another team without anyone noticing until it caused a performance incident.

### Interview Question
What's wrong with this approach, and how would you redesign the drift-handling for this module?

### Strong Senior-Level Answer
**Initial assessment:** `ignore_changes = all` is a smell that indicates the resource isn't actually being managed by Terraform in any meaningful sense anymore — Terraform can no longer detect *any* divergence, which is the opposite of the value proposition of using Terraform at all. The "quiet diff" the team is happy about is actually total blindness to drift, including drift that matters (an unauthorized instance-type downsize causing a performance incident is exactly the kind of change this configuration is now structurally incapable of detecting).

**Technical reasoning:** `ignore_changes` should be scoped to the *specific* attributes genuinely owned by another system (e.g., a specific tag applied by a compliance-tagging Lambda), never a blanket `all`, which silences drift detection for every attribute including ones nobody intended to exempt.

**Investigation process:** determine, attribute by attribute, which fields are genuinely and legitimately modified outside Terraform (and by what — get a real answer, not "some team"), versus fields that should always be Terraform-owned and were only included in the blanket exemption out of convenience.

**Recommended solution:** replace `ignore_changes = all` with an explicit, narrow list — e.g., `ignore_changes = [tags["LastPatched"]]` if a patching system owns that one tag — and restore full drift detection on everything else, including `instance_type`. For `instance_type` specifically, since it sounds like another team has a legitimate, recurring need to resize instances outside the normal Terraform flow, that's a signal for an actual conversation about ownership: either that team's resizing should go through Terraform (a config change, reviewed), or the instance type should be treated as a genuinely externally-owned field with a **documented reason**, not a silent blanket ignore.

**Risk controls:** add a scheduled drift-detection plan (see [`cicd.md`](../docs/cicd.md#8-drift-detection-and-scheduled-plans)) so any remaining, narrowly-scoped drift is still visible and alertable, even where `ignore_changes` intentionally excludes it from *forcing* a revert.

**Validation steps:** after narrowing the exemption, run `terraform plan` and confirm it now surfaces the instance-type drift that had been hidden — this proves the fix actually restores visibility.

**Rollback or recovery strategy:** since this is a configuration-only change (narrowing an exemption list), the "rollback" is simply reverting to the broader exemption if the narrower one turns out to generate too much unwanted noise — but that decision should be made deliberately, attribute by attribute, not by reverting to `all` again.

**Long-term prevention:** add `ignore_changes = all` (or any suspiciously broad `ignore_changes` list) as a flagged pattern in code review guidelines and, ideally, a policy-as-code check that fails a PR introducing it without an accompanying comment justifying each specific attribute.

### Step-by-Step Implementation
```hcl
# Before (blind)
resource "aws_instance" "app" {
  # ...
  lifecycle {
    ignore_changes = all
  }
}

# After (narrow, documented)
resource "aws_instance" "app" {
  # ...
  lifecycle {
    ignore_changes = [
      tags["LastPatched"],   # owned by the automated patching Lambda, not Terraform
    ]
  }
}
```
```bash
terraform plan   # now surfaces instance_type drift and any other real divergence
```

### Under-the-Hood Explanation
`ignore_changes` operates during the diff-calculation stage of plan (see [`terraform-internals.md` §1](../docs/terraform-internals.md#1-the-execution-model-end-to-end)): for each listed attribute, Terraform substitutes the *refreshed real-world value* into the planned configuration instead of comparing against the declared configuration value, effectively making that attribute a no-op for diffing purposes regardless of what the `.tf` file says. `ignore_changes = all` applies this substitution to every attribute in the resource's schema, meaning refresh will silently accept whatever the cloud currently reports as "correct" for every field, permanently.

### Common Weak Answer
"`ignore_changes = all` is fine, it just means Terraform won't fight with manual changes."

### Why the Weak Answer Fails
It treats "Terraform stops reporting a problem" as equivalent to "there is no problem" — exactly backwards. The manual changes are still happening and still matter; the only thing that changed is that nobody can see them anymore through the tool that's supposed to be the source of truth for this infrastructure's configuration.

### Follow-Up Questions
1. How would you design the module's interface so the "team that keeps changing instance types" has a legitimate, fast, reviewed path to do so through Terraform instead of the console?
2. If the instance type genuinely must remain externally managed (e.g., a cost-optimization tool that resizes instances automatically), how would you model that ownership boundary cleanly?
3. What's the difference between using `ignore_changes` for this and using a completely separate, narrower resource/module boundary that excludes `instance_type` from Terraform's management scope entirely?

### Key Interview Signals
Separates candidates who treat `ignore_changes` as a convenience flag from those who understand it as a deliberate, narrow ownership-boundary decision that must be scoped and documented per attribute.

### Hands-On Connection
[Lab 14 — Drift, Failure, and Recovery](../labs/lab-14-drift-and-recovery/).

---

## Question 6: The certificate nobody noticed was expiring

### Scenario
An ACM certificate referenced by an ALB listener is provisioned by Terraform but is not renewed automatically because it uses email/DNS validation that occasionally lapses due to an unrelated DNS hygiene issue. The team wants an ongoing, automatic assertion — independent of any specific apply — that flags when this certificate (and others like it across the estate) is within 30 days of expiry, without blocking unrelated plans/applies.

### Interview Question
Which Terraform language feature is designed for this kind of standing assertion, and how does it differ from a `precondition`/`postcondition` on the resource itself?

### Strong Senior-Level Answer
**Initial assessment:** this calls for a `check` block (Terraform >= 1.5), which is specifically designed to run assertions **independently of the resource dependency graph**, surfacing a warning without failing the plan/apply for unrelated changes.

**Technical reasoning:** `precondition`/`postcondition` blocks live inside a resource, data source, or module's `lifecycle`, and their failure blocks the plan/apply for operations that touch that specific resource — appropriate for "this operation should not proceed if X is true," not for "continuously assert X regardless of what else is being planned." A `check` block runs its assertions during every plan/apply as a standalone unit, reporting a warning (not a hard failure) if the condition fails, which is exactly the "ongoing operational assertion" behavior wanted here.

**Investigation process:** confirm the current Terraform version supports `check` blocks (>= 1.5) and confirm the ACM certificate resource/data source exposes an attribute (`not_after`) usable in the condition.

**Recommended solution:** add a `check` block that reads the certificate's expiry via a `data "aws_acm_certificate"` lookup (or references the managed resource directly) and asserts it's more than 30 days from expiry, with a clear warning message identifying which certificate is at risk.

**Risk controls:** since `check` blocks only warn (they don't fail the plan), pair this with actual alerting — e.g., surface the warning in CI output prominently, or better, have a separate scheduled job parse `terraform plan` output (or use a dedicated monitoring tool like AWS Config or a certificate-expiry CloudWatch alarm) as the real paging mechanism, since a warning buried in routine CI logs is easy to miss.

**Validation steps:** test the check against a certificate artificially close to expiry (or mock the date) to confirm the warning fires correctly, and against a healthy certificate to confirm no false positive.

**Rollback or recovery strategy:** not applicable — this is an assertion, not a resource change; "rollback" isn't a concept that applies here.

**Long-term prevention:** for anything genuinely business-critical, prefer a dedicated monitoring/alerting system (CloudWatch alarms on ACM expiry, or AWS Certificate Manager's own renewal-failure notifications) as the primary control, with the `check` block as a secondary, Terraform-native signal surfaced during routine operations — not the sole mechanism relied upon.

### Step-by-Step Implementation
```hcl
data "aws_acm_certificate" "app" {
  domain      = var.domain_name
  statuses    = ["ISSUED"]
  most_recent = true
}

check "acm_certificate_not_expiring_soon" {
  data "aws_acm_certificate" "app" {
    domain      = var.domain_name
    statuses    = ["ISSUED"]
    most_recent = true
  }

  assert {
    condition     = timecmp(data.aws_acm_certificate.app.not_after, timeadd(timestamp(), "720h")) > 0
    error_message = "ACM certificate for ${var.domain_name} expires within 30 days: ${data.aws_acm_certificate.app.not_after}"
  }
}
```

### Under-the-Hood Explanation
`check` blocks are evaluated as their own top-level graph nodes during plan and apply, separate from the resource graph that determines create/update/destroy operations — this is precisely why a `check` failure doesn't propagate as a blocking error to unrelated resources in the same configuration. Internally, a failed `assert` inside a `check` block is reported as a plan-time warning attached to that check's address, visible in both human-readable and `-json` plan output, letting CI tooling parse it programmatically if deeper automation than "warning text" is desired.

### Common Weak Answer
"Add a `precondition` block to the ALB listener resource checking the certificate's expiry."

### Why the Weak Answer Fails
A `precondition` on the listener would only be evaluated when that specific resource is part of the current plan's graph — if nothing about the listener or its dependencies is changing in a given apply, the precondition may not even be evaluated in a way that surfaces the warning proactively on every run the way a standalone `check` block does; it also would hard-fail the plan for the listener specifically rather than warning, which is the wrong severity for an ongoing, non-blocking operational assertion.

### Follow-Up Questions
1. How would you extend this pattern to check expiry across dozens of certificates without duplicating the check block for each one?
2. What's the trade-off between relying on this Terraform-native check versus a fully separate monitoring system for something as critical as certificate expiry?
3. Could a `check` block's assertion ever have a legitimate reason to hard-fail the apply instead of warning — and if so, what would you use instead?

### Key Interview Signals
Confirms the candidate knows the distinct purposes of `check` blocks versus `precondition`/`postcondition`, and doesn't over-rely on a warning-only mechanism for a genuinely critical operational concern.

### Hands-On Connection
[Lab 11 — Native Terraform Testing](../labs/lab-11-testing/) and [Lab 4 — Production Module Design](../labs/lab-04-module-design/).

---

## Question 7: The apply that died halfway through a data migration

### Scenario
A `terraform apply` provisioning a new RDS instance, a set of IAM roles, and an EKS node group is interrupted when the CI runner is killed by an infrastructure maintenance event partway through. Some resources show as created in the AWS console; others don't exist yet. The next scheduled pipeline run is queued to try again in ten minutes.

### Interview Question
What do you do before that next run fires, and what's your process for safely resuming?

### Strong Senior-Level Answer
**Initial assessment:** this is a partial/interrupted apply. State was written incrementally as each resource operation completed, so state should accurately reflect exactly what succeeded — but that must be verified, not assumed, since the failure mode (CI runner killed) is different from a clean provider-reported error and could in rare cases leave ambiguity around the very last in-flight operation.

**Technical reasoning:** the next scheduled run should not simply be allowed to fire blindly — a fresh `plan` first is mandatory to see whether Terraform's understanding of "what's left to do" matches reality.

**Investigation process:** run `terraform state list` and compare against the full set of resources the original apply intended to create; independently check the AWS console/CLI for the same resources to confirm state and cloud reality agree (a killed CI runner is exactly the scenario where a resource could exist in the cloud from a completed-but-not-yet-state-written operation, in rare provider/backend timing edge cases). Also check whether the state lock was released or is now stale (see [`state-management.md` §3](../docs/state-management.md#3-state-locking)) — a killed process very likely left the lock held.

**Recommended solution:** first, resolve the lock (confirm the original process is genuinely dead via CI job status, then `force-unlock` if needed). Second, run `terraform plan` (not apply) and read it carefully — a partial apply very often produces a plan that cleanly finishes exactly the remaining work, but you must confirm it isn't proposing to replace something that partially succeeded (e.g., an IAM role that was created but not yet fully configured, showing as an update rather than continuing cleanly). Only after that review, proceed with `apply`.

**Risk controls:** disable or pause the scheduled pipeline run temporarily while performing this manual investigation, so a queued automated run doesn't fire mid-investigation and race the manual one.

**Validation steps:** after the resumed apply completes, verify end-to-end that the RDS instance, IAM roles, and node group are all healthy and correctly wired together (e.g., the node group's IAM role actually has the policies attached) — a resumed apply completing without error doesn't guarantee the full intended state is functionally correct if an earlier partial step left something subtly misconfigured.

**Rollback or recovery strategy:** if the plan reveals something irreconcilable (e.g., a resource stuck in a provider-side pending/failed state that Terraform can't cleanly reconcile), be prepared to manually intervene in the cloud console for that one specific resource (e.g., deleting a stuck RDS instance in a failed-create state) before retrying, documenting exactly what was done outside Terraform and why.

**Long-term prevention:** ensure CI runners for apply jobs have graceful-termination handling (a SIGTERM grace period) rather than hard kills where the CI platform supports it, and add a concurrency-group / pipeline-pause mechanism so a scheduled run can never automatically fire on top of an investigation in progress.

### Step-by-Step Implementation
```bash
# 1. Check lock status
terraform plan   # will fail fast with lock info if still held

# 2. Confirm original process is dead (check CI job status/logs), then:
terraform force-unlock <LOCK_ID>

# 3. Compare state vs. intended resources vs. cloud reality
terraform state list
aws rds describe-db-instances --db-instance-identifier <id>
aws eks describe-nodegroup --cluster-name <cluster> --nodegroup-name <ng>

# 4. Fresh plan, read carefully before proceeding
terraform plan -out=resume.tfplan
terraform show resume.tfplan   # review every line

# 5. Only then apply
terraform apply resume.tfplan
```

### Under-the-Hood Explanation
State is written incrementally, resource-by-resource, as each `ApplyResourceChange` RPC call returns successfully (see [`terraform-internals.md` §10](../docs/terraform-internals.md#10-state-serial-lineage-and-reconciliation-during-apply)) — this is precisely why a killed process still leaves an accurate (if incomplete) picture of what succeeded, rather than losing track entirely. The scheduled next run, if allowed to fire without investigation, would itself just run a fresh plan against this same state — the risk isn't that Terraform behaves incorrectly, it's that firing it blind (without a human reviewing the resume plan) removes the opportunity to catch a genuine edge-case inconsistency before it's applied.

### Common Weak Answer
"It's fine, just let the next scheduled run retry — Terraform will pick up where it left off automatically."

### Why the Weak Answer Fails
It's often *true* that Terraform will cleanly resume, but "usually true" isn't verification, and a killed-process interruption is exactly the scenario most likely to produce a rare edge case (a stuck cloud-side resource state, a stale lock) that a blind automated retry won't handle gracefully. Letting it fire unreviewed also races the possibility of two applies against the same state if the lock didn't get held/released cleanly.

### Follow-Up Questions
1. How would your answer change if the interrupted apply had included a `-replace` on a stateful resource like the RDS instance?
2. How do you design CI infrastructure so "runner killed by maintenance" becomes a graceful termination instead of a hard kill?
3. What monitoring/alerting would you add so a partial apply gets a human notified immediately, rather than relying on someone noticing before the next scheduled run fires?

### Key Interview Signals
Tests whether the candidate treats an interrupted apply as "probably fine, just retry" versus a genuine investigation-first scenario, and whether they know state is written incrementally (so it's not a guessing game about what succeeded).

### Hands-On Connection
[Lab 14 — Drift, Failure, and Recovery](../labs/lab-14-drift-and-recovery/).

---

## Question 8: The intermittent IAM race

### Scenario
An `aws_eks_node_group` and its associated `aws_iam_role_policy_attachment` (attaching the EKS worker node policy to the node group's role) are declared with no explicit dependency between them — the node group references the IAM *role*, not the policy attachment. About one apply in five, new nodes fail to join the cluster, and a re-run of the exact same apply with no changes succeeds.

### Interview Question
Diagnose the intermittent failure and fix it.

### Strong Senior-Level Answer
**Initial assessment:** classic missing-dependency-edge problem. Terraform's dependency graph is built from attribute references; because the node group references `aws_iam_role.eks_nodes.arn` (the role) but not any attribute of the policy attachment resource, there is no graph edge forcing the policy attachment to complete before the node group creation begins — the two are eligible to run in parallel, and whether the attachment finishes before AWS's EKS service actually tries to launch nodes and have them register (which requires the policy to already be attached) is a race, not a guarantee.

**Technical reasoning:** IAM policy attachment being "complete" from Terraform/AWS's API perspective (the API call returned success) doesn't always coincide with the policy being fully effective for the purposes of a dependent action AWS performs internally (IAM eventual consistency) — but even setting eventual consistency aside, without an edge, the *order* of the two operations isn't even guaranteed to be attachment-then-node-group in the first place.

**Investigation process:** confirm via `terraform graph` that no edge exists between the two resources; check EKS node group creation failure logs for the specific pattern (nodes fail to register, IAM permission errors) that would confirm the policy wasn't yet effective at node bootstrap time, distinguishing this from an unrelated cause (subnet/security group misconfiguration, capacity issues).

**Recommended solution:** add an explicit `depends_on = [aws_iam_role_policy_attachment.eks_worker_node_policy]` on the node group resource, forcing Terraform's graph to sequence the attachment fully before starting node group creation.

**Risk controls:** apply the same audit to every other IAM-role-then-service-that-uses-it pairing in the configuration — this bug pattern (referencing the role but not its policy attachments) is easy to have in multiple places once you look for it.

**Validation steps:** run several applies from a clean state (destroy/recreate in a non-prod environment) to confirm the failure no longer reproduces after adding `depends_on` — a single successful apply isn't sufficient proof for an intermittent, timing-based bug.

**Rollback or recovery strategy:** not a destructive change — adding `depends_on` only affects ordering, not resource identity, so this fix itself carries no replacement/data-loss risk.

**Long-term prevention:** during module design review, explicitly ask "does this resource depend on another resource's side effect (permissions, registration, propagation) that the provider schema doesn't structurally reference?" — this is the pattern to watch for generally, not just for this one IAM case.

### Step-by-Step Implementation
```hcl
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = var.subnet_ids

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.ecr_read_only,
  ]
}
```

### Under-the-Hood Explanation
Terraform's graph builder (see [`terraform-internals.md` §2](../docs/terraform-internals.md#2-dependency-graph-construction)) infers edges purely from what it can see in the configuration — attribute references and explicit `depends_on`. It has no model of side effects a resource's *creation* has on downstream systems beyond what the provider's own API calls return. Since the node group's arguments only reference the role (an attribute of `aws_iam_role.eks_nodes`), not any attribute of the policy attachment resources, no edge exists between them, and both become eligible for the same parallel execution batch during apply — whether the attachment's API call actually completes before the node group's creation call depends on scheduling, which is exactly why the failure is intermittent rather than constant or never.

### Common Weak Answer
"Just add a `time_sleep` resource between them to wait a few seconds for the IAM policy to propagate."

### Why the Weak Answer Fails
It treats a genuine missing-ordering-guarantee as a timing/propagation-delay problem. `depends_on` provides a real, deterministic ordering guarantee regardless of how fast or slow any individual API call is; a fixed sleep is a guess about a delay that could still be too short under load, and adds latency to every apply even when it isn't needed. (Note: `time_sleep` is a legitimate tool for *genuine* eventual-consistency propagation delays *in addition to* correct ordering via `depends_on` — but it is not a substitute for the ordering guarantee itself.)

### Follow-Up Questions
1. If the failure persisted even after adding `depends_on`, what would you investigate next (hint: genuine IAM eventual consistency vs. ordering)?
2. How would you write a `terraform test` case that could have caught this missing dependency before it reached production?
3. How does this same class of problem show up with Kubernetes provider resources depending on a just-created EKS cluster's API server being reachable?

### Key Interview Signals
Confirms the candidate understands `depends_on` exists specifically for dependencies the graph can't infer from attribute references, and can distinguish an ordering problem from a propagation-delay problem (which require different fixes).

### Hands-On Connection
[Lab 9 — Amazon EKS Infrastructure](../labs/lab-09-eks-infrastructure/).

---

## Question 9: Converting a legacy `count` fleet to `for_each` without downtime

### Scenario
Twelve application servers are managed with `count = 12` and referenced elsewhere (a load balancer target group attachment, a monitoring dashboard config) by their index. The team wants to move to `for_each` keyed by a logical server name (`web-01` through `web-12`) to support future non-contiguous scaling (removing `web-05` specifically without shifting the rest), but cannot tolerate destroying and recreating any of the twelve running servers.

### Interview Question
Design the migration plan.

### Strong Senior-Level Answer
**Initial assessment:** this is a pure refactor — the underlying resources shouldn't change at all, only their state addressing. The tool for this is `terraform state mv` (or, in modern Terraform, `moved` blocks, which achieve the same effect declaratively and are preferred for reusable modules since they apply automatically for every consumer without each consumer having to run manual state surgery).

**Technical reasoning:** as long as the resource *arguments* produced by the new `for_each` configuration are byte-identical to what `count` was producing for each corresponding index (same AMI, same subnet, same everything), the only thing that needs to change is the state entry's address — no attribute is actually different, so there's nothing to force a replacement, provided the address change itself is communicated to Terraform via `moved`/`state mv` rather than left for Terraform to infatuation over as "these are unrelated resources."

**Investigation process:** before changing anything, enumerate the exact mapping from old index to new key (`[0]` → `"web-01"`, `[1]` → `"web-02"`, etc.) and confirm every downstream reference (target group attachments, monitoring configs) that currently uses `count.index`-based addressing will be updated consistently in the same change.

**Recommended solution:** write `moved` blocks for every one of the twelve resources mapping old to new address, change the resource definition from `count` to `for_each`, update all downstream references from index-based to key-based, and run `plan` — expect **zero** changes (no create, no destroy, no update) if done correctly.

**Risk controls:** do this in a single, atomic PR/apply rather than partially — a half-migrated state (some resources moved, some not) is confusing and risks the remaining `count`-indexed resources shifting if anything about the list changes mid-migration.

**Validation steps:** `terraform plan` showing zero diff is the definitive proof; additionally spot-check `terraform state show` on a couple of the migrated addresses to confirm the attributes are identical to pre-migration.

**Rollback or recovery strategy:** if the plan unexpectedly shows a replacement for any resource, stop immediately — do not apply — and diff the old vs. new resource configuration attribute-by-attribute to find the mismatch (a common cause: `for_each`'s `each.key` producing a subtly different computed value than `count.index` did, e.g., in a `cidrsubnet()` offset calculation).

**Long-term prevention:** for any future collection of resources, default to `for_each` from the start (see [Question 1](#question-1-the-subnet-that-shifted)) so this migration is never needed again for new resource sets.

### Step-by-Step Implementation
```hcl
moved {
  from = aws_instance.web[0]
  to   = aws_instance.web["web-01"]
}
moved {
  from = aws_instance.web[1]
  to   = aws_instance.web["web-02"]
}
# ... repeat for all 12 ...

resource "aws_instance" "web" {
  for_each      = toset(var.server_names)  # ["web-01", ..., "web-12"]
  ami           = var.ami_id
  instance_type = var.instance_type
  subnet_id     = var.subnet_ids[index(var.server_names, each.key) % length(var.subnet_ids)]
  tags = {
    Name = each.key
  }
}

resource "aws_lb_target_group_attachment" "web" {
  for_each         = aws_instance.web
  target_group_arn = aws_lb_target_group.app.arn
  target_id        = each.value.id
}
```
```bash
terraform plan   # must show 0 to add, 0 to change, 0 to destroy
```

### Under-the-Hood Explanation
`moved` blocks are processed by Terraform Core early in the plan cycle, before diff calculation: for each `moved` entry, Terraform checks whether a state entry exists at the `from` address and, if so, relocates it internally to the `to` address before comparing against the new configuration — from the diffing engine's perspective, it's as if the resource had always been at the new address, so as long as the new configuration's computed attributes match what's already in the (relocated) state entry, the diff is a clean no-op. Without the `moved` block, Terraform would see a resource address in configuration (`aws_instance.web["web-01"]`) with no corresponding state entry, and a state entry (`aws_instance.web[0]`) with no corresponding configuration — interpreted as create-new plus destroy-old, i.e., full replacement.

### Common Weak Answer
"Just apply the new `for_each` configuration — Terraform is smart enough to figure out these are the same servers."

### Why the Weak Answer Fails
Terraform has no semantic understanding that a `for_each`-keyed address and a `count`-indexed address refer to "the same" real-world resource unless explicitly told via `moved`/`state mv` — without that, it will plan to destroy all twelve indexed instances and create twelve new keyed ones, which is exactly the outage this migration is trying to avoid.

### Follow-Up Questions
1. What would you do differently if this were a reusable module used by dozens of consumers, rather than a single root module?
2. How would you validate the migration in CI before it ever reaches a human approving a production apply?
3. What's the risk if the `server_names` list and the old `count`-based index order don't map 1:1 in a way everyone assumed (e.g., off-by-one)?

### Key Interview Signals
Tests whether the candidate can execute a genuinely zero-downtime refactor using `moved` blocks/`state mv`, and whether they insist on a zero-diff plan as proof rather than assuming success.

### Hands-On Connection
[Lab 7 — Refactoring Without Recreation](../labs/lab-07-refactoring-state/).

---

## Question 10: The workflow gap between `plan -out` and a later `apply`

### Scenario
A pipeline runs `terraform plan -out=tfplan` on PR open, a human reviews and approves the PR, and 45 minutes later (after CI queue delays) a separate job runs `terraform apply tfplan` using that saved artifact. In between, another engineer's unrelated hotfix pipeline applied a change to the same state.

### Interview Question
What happens when the delayed apply runs, and why is this actually the *safe* outcome rather than a bug?

### Strong Senior-Level Answer
**Initial assessment:** this is exactly the scenario that state serial/lineage checking exists to protect against. When `terraform apply tfplan` runs, Terraform first checks that the state the plan was computed against is still current — specifically, that the state's serial (and lineage) haven't advanced since the plan was saved.

**Technical reasoning:** because the hotfix pipeline's apply bumped the state's serial (and possibly changed resources the saved plan's diff was computed relative to), the saved plan is now stale — applying it blindly could mean either reapplying changes that no longer make sense given the new state, or missing that the saved plan's assumptions (e.g., a resource's "current" attributes at plan time) no longer hold.

**Investigation process:** the delayed apply's actual behavior: Terraform detects the mismatch and refuses to apply the stale plan, erroring out with a message indicating the state has changed since the plan was created — this is a deliberate, hard failure, not a silent partial application of stale intent.

**Recommended solution:** the pipeline should treat this failure as expected-and-safe, not alarming: re-run `terraform plan` fresh (re-deriving a plan against current state), and — critically — this **should trigger a fresh review**, not an automatic re-apply of whatever the new plan says, since the new plan may now include entirely different changes than what the original human approved.

**Risk controls:** design the pipeline so a stale-plan failure routes back to a "needs re-review" state on the PR (e.g., dismissing the previous approval, requiring a fresh plan comment and fresh sign-off) rather than being treated as a transient error worth blindly retrying.

**Validation steps:** confirm the new plan, once generated, is reviewed and its diff makes sense combined with whatever the hotfix pipeline already changed — there could now be interaction effects between the original PR's intended change and the hotfix that weren't visible when either was planned in isolation.

**Rollback or recovery strategy:** not applicable in the failure case itself (nothing was applied) — the "recovery" is simply the re-plan-and-re-review cycle described above.

**Long-term prevention:** add CI concurrency controls (see [`cicd.md` §6](../docs/cicd.md#6-concurrency-controls)) so that, ideally, two pipelines can't even both be actively modifying the same state's queue of pending changes without at least a serialized, visible ordering — reducing how often this scenario arises, though it can never be eliminated entirely (a legitimate emergency hotfix should always be allowed to jump the queue).

### Step-by-Step Implementation
```bash
# Original PR pipeline (T+0)
terraform plan -out=tfplan
# ... human reviews and approves ...

# Hotfix pipeline (T+20min) - applies directly, bumps state serial
terraform apply -auto-approve  # emergency fix, different PR

# Delayed apply job (T+45min) - attempts to apply the now-stale saved plan
terraform apply tfplan
# Error: Saved plan is stale
#   The given plan file can no longer be applied because the state was
#   changed by another operation after the plan was created.

# Correct remediation:
terraform plan -out=tfplan-v2   # fresh plan against current state
# route back through review before applying tfplan-v2
```

### Under-the-Hood Explanation
Every state write bumps the `serial` field (see [`state-management.md` §4](../docs/state-management.md#4-state-lineage-and-serial)); a saved plan file embeds the serial (and lineage) of the state it was computed against. When `apply` is given a saved plan file, before doing anything else it re-reads the current state from the backend and compares serial/lineage against what's embedded in the plan file — a mismatch is treated as a hard error specifically to prevent applying a diff that was computed against assumptions (resource attribute values, existence/non-existence of other resources) that are no longer true.

### Common Weak Answer
"That's annoying — we should just have the apply job regenerate the plan automatically and apply it without going back for review, to keep the pipeline moving."

### Why the Weak Answer Fails
This defeats the entire purpose of the plan-review-then-apply-that-exact-plan pattern (see [`cicd.md` §2](../docs/cicd.md#2-plan-generation-plan-artifacts-and-plan-integrity)) — it would mean a human's approval on the original PR is being treated as authorization for whatever a *later, different* plan says, which may include changes from the intervening hotfix or from further drift, that nobody actually reviewed.

### Follow-Up Questions
1. How would you design the CI/CD system to make "needs re-review" a clear, low-friction state rather than a confusing pipeline failure?
2. Is there a way to reduce how often this stale-plan scenario occurs without eliminating the legitimate ability to ship emergency hotfixes out-of-band?
3. How does this interact with `-lock=false` if someone were tempted to use it to "fix" the failure — why is that dangerous?

### Key Interview Signals
Confirms the candidate understands stale-plan rejection as a deliberate safety feature (not a bug to route around) and won't shortcut the review requirement to keep a pipeline "moving."

### Hands-On Connection
[Lab 12 — CI/CD Pipeline](../labs/lab-12-cicd-pipeline/) and [Lab 3 — Concurrent Execution and Locking](../labs/lab-03-state-locking/).
