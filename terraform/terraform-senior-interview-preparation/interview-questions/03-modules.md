# Category 3: Module Architecture and Reuse

Questions 23–34 of 120. Category weight: 12 questions. Deep-dive reference: [`docs/module-design.md`](../docs/module-design.md).

---

## Question 23: The version bump that broke forty repositories

### Scenario
Your platform team publishes a shared `vpc` module used by roughly forty application repositories, each pinned with `version = ">= 4.0"`. A minor-looking change — renaming the `subnet_cidrs` input to `private_subnet_cidrs` for clarity, and removing the old name — ships as `4.6.0`. Within hours, dozens of consumer pipelines start failing `terraform init`/`plan`.

### Interview Question
Diagnose the root cause and redesign the module's release process so this can't happen again.

### Strong Senior-Level Answer
**Initial assessment:** two independent failures compounded: an unconstrained consumer version range (`>= 4.0` floats onto any future release, including breaking ones) and a breaking change classified/shipped as a non-major bump.

**Technical reasoning:** a required-input rename is unambiguously a breaking change under semantic versioning — any consumer not already setting `private_subnet_cidrs` will fail validation immediately. This should have been a `5.0.0` release, and even then, unconstrained consumers would still have broken the moment they next ran `init -upgrade`.

**Investigation process:** confirm the actual diff between `4.5.x` and `4.6.0` against the module's own CHANGELOG (or lack thereof) — the absence of a documented breaking-change process is usually the deeper finding, not just this one release.

**Recommended solution:** immediately publish a `4.6.1` patch (or yank `4.6.0` if the registry supports it) restoring the old input name as a deprecated alias accepting both, buying time; separately, cut the rename as a proper `5.0.0` with a migration guide and, ideally, `moved`-block-equivalent guidance (a documented rename script) so consumers upgrade deliberately. Long-term, mandate `~>` constraints for every consumer (never unconstrained `>=`), require a CHANGELOG entry classified by semver impact on every module PR, and run the module's own test suite plus a contract-test matrix against a representative sample of real consumer configurations before any release — especially majors.

**Risk controls:** treat any input/output removal, rename, or default-value change as requiring a major bump and a deprecation window (supporting both names for at least one prior minor) rather than a same-release swap.

**Validation steps:** contract tests applying the new version against pinned copies of several real consumers' actual configurations should catch this exact class of break pre-release.

**Rollback or recovery strategy:** consumers roll back via their own version constraint to the last good version; the module author's rollback is republishing/yanking the breaking release and communicating clearly.

**Long-term prevention:** semver discipline, CHANGELOG-with-classification as a required PR field, contract testing gate before publish, and consumer-side `~>` pinning enforced via a linter/policy check on consumer repos.

### Step-by-Step Implementation
```hcl
# Deprecation-friendly interim release (4.6.1): accept both names
variable "subnet_cidrs" {
  type    = list(string)
  default = null
}
variable "private_subnet_cidrs" {
  type    = list(string)
  default = null
}
locals {
  effective_subnet_cidrs = coalesce(var.private_subnet_cidrs, var.subnet_cidrs, [])
}
```
```hcl
# Consumer pinning discipline going forward
module "vpc" {
  source  = "app.terraform.io/my-org/vpc/aws"
  version = "~> 4.6"   # never ">= 4.0"
}
```

### Under-the-Hood Explanation
`terraform init` resolves `version` constraints against the registry's published version list at init time; an unconstrained `>=` range means the next `init -upgrade` (or even a fresh `init` on a clean cache, depending on lock-file state) can silently pick up a new major release. `terraform validate` then fails immediately if a `required` variable a consumer never set has no default — exactly what happens when a required input is renamed without a backward-compatible transition.

### Common Weak Answer
"We should test modules before releasing them."

### Why the Weak Answer Fails
Too generic — it doesn't identify the two specific, fixable failures (unconstrained consumer pinning, and a rename misclassified as non-breaking) or propose the concrete mechanisms (semver discipline, CHANGELOG classification, contract testing, deprecation aliasing) that actually prevent recurrence.

### Follow-Up Questions
1. How would you retrofit `~>` pinning across forty existing consumer repos that currently use `>= 4.0`?
2. What would your contract-test matrix actually look like in CI — how many consumer configurations, and how do you keep that fixture set representative over time?
3. How do you handle a genuinely necessary breaking change (not just a rename) where no backward-compatible alias is possible?

### Key Interview Signals
Identifies both root causes (not just one), proposes concrete process fixes (not "test more"), and understands deprecation-aliasing as a real technique, not just theory.

### Hands-On Connection
[Lab 4 — Production Module Design](../labs/lab-04-module-design/) and [Lab 11 — Native Terraform Testing](../labs/lab-11-testing/).

---

## Question 24: The module that depended on itself

### Scenario
A `networking` module creates subnets and needs a security group ID (to associate with a VPC endpoint) that's produced by a separate `security` module — but the `security` module also needs a subnet ID (to scope a security-group-referencing VPC endpoint policy) from the `networking` module. Neither module can be planned first.

### Interview Question
Redesign this to eliminate the cycle.

### Strong Senior-Level Answer
**Initial assessment:** a genuine circular dependency between two child modules — Terraform's graph has no mechanism to resolve this; it's a modeling error, not a Terraform limitation to work around with flags.

**Technical reasoning:** the cycle exists because each module was scoped by "logical area" (networking vs. security) rather than by actual resource coupling — the VPC endpoint and its associated security group/policy are tightly coupled to each other regardless of which "logical area" they're filed under.

**Investigation process:** identify exactly which resource pair is mutually dependent (usually a small subset of the two modules' full resource sets, not everything) — here, specifically the VPC endpoint, its security group, and its policy.

**Recommended solution:** two valid fixes. (a) Extract the genuinely coupled resources (VPC endpoint + its security group + its policy) into their own small module or into the root module directly, so neither `networking` nor `security` needs the other — both instead feed inputs (subnet IDs, base security group IDs) to this third piece from above. (b) If the coupling is truly pervasive throughout both modules, merge them into one module — a "networking-and-security" module isn't a failure of module design if that's genuinely how tightly these concerns interrelate for this platform.

**Risk controls:** whichever fix is chosen, re-verify no new cycle was introduced by tracing every cross-module reference explicitly, not just fixing the one cycle found.

**Validation steps:** `terraform validate`/`plan` succeeding at all is the first proof (a real cycle is a hard plan-time error); confirm the resource graph (`terraform graph`) shows one-directional module composition afterward.

**Rollback or recovery strategy:** not applicable — this is a design-time fix caught before any resources exist; no infrastructure impact.

**Long-term prevention:** during module design review, explicitly diagram cross-module dependencies before implementation — a circular arrow on that diagram is the same signal whether or not it's yet expressed in code.

### Step-by-Step Implementation
```hcl
# Root module composes in one direction only
module "networking" {
  source = "./modules/networking"
  # produces vpc_id, subnet_ids — no dependency on security module
}

module "security" {
  source = "./modules/security"
  vpc_id = module.networking.vpc_id
  # produces base security group ids — no dependency on networking beyond vpc_id
}

module "vpc_endpoint" {
  source            = "./modules/vpc-endpoint"
  subnet_ids        = module.networking.subnet_ids
  security_group_id = module.security.endpoint_sg_id
  # the previously-cyclic coupling lives here, one level up, depending on both cleanly
}
```

### Under-the-Hood Explanation
Terraform's graph builder detects cycles during graph construction (before plan/apply proceeds) by attempting a topological sort — if any two nodes have edges pointing at each other (directly or transitively), no valid ordering exists and Terraform errors out immediately, refusing to guess an order. Extracting the coupled resources into a third module/layer that depends on both, but that neither of the original two depends on, restores a valid one-directional DAG.

### Common Weak Answer
"Add `depends_on` between the two modules to force an order."

### Why the Weak Answer Fails
`depends_on` cannot resolve a genuine mutual dependency — if both modules truly need an output from the other before either can be evaluated, no `depends_on` ordering makes that possible; the fix must be structural (extract the shared concern, or merge the modules), not an ordering hint.

### Follow-Up Questions
1. How would you detect this kind of cycle during code review, before it's even attempted in Terraform?
2. What's the difference between this cycle and a legitimate two-phase dependency within a single root module (e.g., an EKS cluster's OIDC issuer feeding back into an IAM module for pod roles)?
3. If merging the two modules is the right call, how do you decide the new, combined module's interface so it doesn't become the "overly generic" anti-pattern?

### Key Interview Signals
Confirms the candidate recognizes a cycle as a modeling problem requiring restructuring, not something a Terraform flag can paper over.

### Hands-On Connection
[Lab 4 — Production Module Design](../labs/lab-04-module-design/).

---

## Question 25: The module with fifty optional variables

### Scenario
An internal `ec2-instance` module has grown to accept fifty-plus optional variables covering every conceivable EC2 configuration option across every team that's ever used it. New engineers regularly misconfigure it (missing encryption, wrong subnet tier) because the sheer surface area makes correct usage non-obvious, and the module's own test suite covers only a handful of the possible variable combinations.

### Interview Question
How would you redesign this module's philosophy?

### Strong Senior-Level Answer
**Initial assessment:** this module optimized for flexibility at the cost of having no real opinion — which, for a module consumed directly by application engineers (not by other module authors), is generally the wrong trade-off; it pushes the burden of getting security/compliance defaults right onto every individual consumer.

**Technical reasoning:** opinionated modules encode organizational standards as defaults and only expose the small set of inputs that genuinely vary per legitimate use case — this is faster to use correctly, harder to misuse, and dramatically easier to test exhaustively because the input space is small.

**Investigation process:** audit actual usage across consumers — which of the fifty variables are set to non-default values in practice, and by how many consumers? Frequently, the real variance is a handful of inputs (instance type, AMI, a couple of tags) while the rest are always left at defaults or always set to the same "correct" value everywhere.

**Recommended solution:** redesign around a small, opinionated core (encryption always on, IMDSv2 always enforced, always placed in the correct subnet tier via a `tier` enum rather than a raw subnet ID, tagging always applied from a standard schema) exposing only genuinely-varying inputs; provide a narrow, explicit, reviewed escape hatch (e.g., a single `overrides` object, documented as requiring platform-team sign-off for any use) for the rare legitimate exception, rather than fifty first-class optional variables treated as equally normal.

**Risk controls:** version this as a major bump with a migration guide, since narrowing the interface is itself a breaking change for any consumer using a variable that's being removed from the public interface (see [Question 23](#question-23-the-version-bump-that-broke-forty-repositories) for the release discipline this requires).

**Validation steps:** with a small input space, exhaustive `terraform test` coverage (every legitimate combination) becomes actually achievable, closing the test-coverage gap the scenario describes.

**Rollback or recovery strategy:** roll out gradually — offer the new opinionated module as a new major version while the old flexible one remains available and deprecated for a defined window, letting consumers migrate on their own schedule rather than a forced simultaneous cutover.

**Long-term prevention:** establish a design review gate for any new module or module-interface addition, specifically asking "does this new optional variable represent a genuine, recurring need, or a one-off convenience for a single consumer" before merging it.

### Step-by-Step Implementation
```hcl
# Before: fifty flat optional variables, no real opinion
# After: small opinionated surface + narrow escape hatch
variable "tier" {
  type        = string
  description = "Deployment tier controlling subnet placement and security defaults."
  validation {
    condition     = contains(["public", "private", "data"], var.tier)
    error_message = "tier must be one of: public, private, data."
  }
}

variable "instance_type" {
  type = string
}

variable "overrides" {
  type        = map(any)
  default     = {}
  description = "Platform-team-reviewed exceptions only. Each key requires a linked approval ticket in the PR."
}

resource "aws_instance" "this" {
  ami                    = data.aws_ami.approved.id
  instance_type          = var.instance_type
  subnet_id              = local.tier_subnet_map[var.tier]
  metadata_options {
    http_tokens = "required"   # IMDSv2 enforced, not optional
  }
  root_block_device {
    encrypted = true            # always on, not optional
  }
}
```

### Under-the-Hood Explanation
This is purely a module-interface design decision — Terraform itself has no preference between a flexible or opinionated module. The practical engine-level benefit of a narrow input space is combinatorial: `terraform test` coverage of N booleans/enums requires testing a space that grows with the number of independent inputs, so shrinking fifty largely-orthogonal optional variables down to a handful of interdependent, validated ones makes genuinely exhaustive test coverage achievable rather than aspirational.

### Common Weak Answer
"Add more documentation so people know how to use all the options correctly."

### Why the Weak Answer Fails
Documentation doesn't reduce the actual combinatorial misuse surface — it asks every consumer to correctly navigate fifty options by reading carefully, which is the same failure mode already observed. The structural fix is reducing the surface area itself, not documenting a large surface area better.

### Follow-Up Questions
1. How do you handle the genuine outlier consumer who needs something the opinionated defaults don't support, without immediately re-expanding back to fifty variables?
2. How would you migrate forty existing consumers from the old flexible module to the new opinionated one with minimal disruption?
3. Is there a case where a fully flexible module is still the right design — what characterizes that case?

### Key Interview Signals
Distinguishes "flexibility is always good" thinking from a deliberate, opinionated-by-default design philosophy appropriate for application-facing modules.

### Hands-On Connection
[Lab 4 — Production Module Design](../labs/lab-04-module-design/).

---

## Question 26: Four modules deep

### Scenario
A root module calls an `environment` module, which calls a `workload` module, which calls a `compute` module, which finally declares the actual `aws_instance` resources — four levels of nesting. A recent debugging session to trace why a single tag value wasn't propagating correctly took most of a day, following the variable through all four layers.

### Interview Question
Would you flatten this, and how?

### Strong Senior-Level Answer
**Initial assessment:** yes — four levels of nesting where each intermediate layer does little more than pass variables through unchanged is exactly the deeply-nested-module anti-pattern; it adds indirection cost (debugging time, slower `plan`/`validate` as each layer re-evaluates) without a corresponding benefit.

**Technical reasoning:** module nesting is justified when each layer adds genuine composition value (e.g., a layer that combines three sibling child modules and wires their outputs together meaningfully) — not when a layer exists purely to relay a variable or two unchanged to the next layer down.

**Investigation process:** audit each of the four layers: does `environment` actually do anything besides call `workload`? Does `workload` do anything besides call `compute`? If either is a pure pass-through with no added logic, defaults, or composition, it's a candidate for removal.

**Recommended solution:** flatten to the layers that add real value — likely collapsing to two levels: a root module (or `environment` layer, if it genuinely handles per-environment configuration selection) directly calling `compute` (which owns the actual resources), removing the `workload` pass-through layer entirely by having its few genuinely-used variables passed straight through.

**Risk controls:** flattening changes module call structure, which changes resource addresses (`module.environment.module.workload.module.compute.aws_instance.this` becomes `module.compute.aws_instance.this`) — this requires `moved` blocks or `state mv`, exactly like any other refactor, to avoid destroy/recreate.

**Validation steps:** zero-diff plan after flattening is the proof; additionally, time a `terraform validate`/`plan` before and after to quantify the reduced overhead.

**Rollback or recovery strategy:** flattening is a pure refactor with a `moved`-block safety net; if a diff appears unexpectedly, the collapse likely dropped or altered a default/computed value that one of the removed layers was silently providing — investigate before proceeding.

**Long-term prevention:** apply a "does this layer add real composition value" test before introducing any new module nesting level going forward, and periodically audit existing deep nesting as tech debt.

### Step-by-Step Implementation
```hcl
# Before: environment -> workload -> compute (workload is pure passthrough)
# After: environment -> compute directly
moved {
  from = module.environment.module.workload.module.compute.aws_instance.this
  to   = module.environment.module.compute.aws_instance.this
}
```
```bash
terraform plan   # expect 0 diff after flattening + moved blocks
```

### Under-the-Hood Explanation
Each module call is a node (and its own nested subgraph) in Terraform's overall configuration graph — `terraform validate`/`plan` must traverse and evaluate every layer's variable/output expressions, even ones that are pure pass-throughs, adding real (if individually small) overhead per layer, and adding a real hop for any human tracing a value's path, which is what turned a one-line tag issue into a full day of debugging in this scenario.

### Common Weak Answer
"Nesting is fine, it's more organized — the issue is just that debugging tools need improvement."

### Why the Weak Answer Fails
It treats symptomatic debugging pain as a tooling gap rather than recognizing the actual root cause: unnecessary indirection with no corresponding composition value. Better debugging tools would help, but the structural fix (removing layers that don't earn their complexity) is the real answer.

### Follow-Up Questions
1. How do you decide, in general, whether a new module layer is "adding composition value" versus "just organizing code"?
2. How would you flatten this if the `workload` layer, while mostly a pass-through, did have one piece of genuine logic (say, a computed default for one variable)?
3. What's an example of module nesting that *is* justified, and why does it differ from this case?

### Key Interview Signals
Confirms the candidate treats nesting depth as a cost to be justified per layer, not a default organizational virtue.

### Hands-On Connection
[Lab 4 — Production Module Design](../labs/lab-04-module-design/) and [Lab 5 — Multi-Environment Architecture](../labs/lab-05-multi-environment/).

---

## Question 27: The VPC module that only gave you an ID

### Scenario
Your organization's shared `vpc` module outputs only `vpc_id`. Every one of a dozen consuming teams independently writes their own `data "aws_subnet" "private"` lookups (using tag-based filters) to rediscover subnet IDs, because the module doesn't expose them — and two teams' filters are subtly wrong, occasionally picking up the wrong subnet after a networking change.

### Interview Question
What's wrong with this module's output design, and how do you fix it without breaking anyone?

### Strong Senior-Level Answer
**Initial assessment:** the module's output surface is under-designed — it exposes the bare minimum rather than what consumers actually, legitimately need, forcing every consumer to reimplement subnet discovery via fragile tag-based data source lookups instead of receiving a stable, guaranteed value directly from the module that created those subnets.

**Technical reasoning:** a module's outputs should describe *what the module guarantees to provide*, not the smallest technically-sufficient set — subnet IDs, grouped meaningfully (e.g., by tier and AZ), are exactly the kind of "consumers legitimately need this" output missing here.

**Investigation process:** survey the dozen consumers' data-source-lookup code to catalog exactly what they're all independently trying to derive — this is almost always redundant, near-identical logic across consumers, which is the clearest signal the module should just provide it directly.

**Recommended solution:** add new outputs (`private_subnet_ids`, `public_subnet_ids`, ideally as maps keyed by AZ for clarity) as a **backward-compatible minor version** (pure addition, no removal) — every existing consumer is unaffected, and new/updated consumers can migrate off their fragile tag-based lookups onto the module's own guaranteed outputs at their own pace.

**Risk controls:** don't remove the ability for a consumer to still do their own lookup if they have a genuine reason to — the fix is *adding* a better path, not restricting flexibility, avoiding a breaking change entirely for this specific fix.

**Validation steps:** for each migrating consumer, confirm their plan is a no-op after switching from a tag-based data source to the module's direct output — same subnet IDs, different (correct, guaranteed) source.

**Rollback or recovery strategy:** since this is purely additive, there's no rollback risk to the module itself; a migrating consumer can revert to their old lookup independently if something looks wrong, with no coordination needed.

**Long-term prevention:** during module output design review, ask "what will every reasonable consumer need to derive about this module's resources" and provide those directly, rather than waiting for consumers to independently discover the gap via fragile workarounds.

### Step-by-Step Implementation
```hcl
# vpc module: additive outputs, minor version bump only
output "private_subnet_ids" {
  value       = { for s in aws_subnet.private : s.availability_zone => s.id }
  description = "Private subnet IDs keyed by availability zone."
}

output "public_subnet_ids" {
  value       = { for s in aws_subnet.public : s.availability_zone => s.id }
  description = "Public subnet IDs keyed by availability zone."
}
```
```hcl
# Consumer migration (optional, at their own pace)
# Before:
data "aws_subnet" "private" {
  filter { name = "tag:Tier" values = ["private"] }
}
# After:
locals {
  private_subnet_ids = module.vpc.private_subnet_ids
}
```

### Under-the-Hood Explanation
Module outputs are just expressions evaluated against the module's own resources/locals and exposed to the caller — there's no mechanical constraint forcing a minimal output surface; the under-design here is purely a module-authoring choice. Adding new outputs is unconditionally backward-compatible from Terraform's perspective (existing consumers who don't reference the new outputs are entirely unaffected), which is exactly why this fix requires no major version bump or migration guide — only a documentation update encouraging (not forcing) adoption.

### Common Weak Answer
"Tell the two teams with wrong filters to fix their tag-based lookups."

### Why the Weak Answer Fails
This fixes two symptoms while leaving the systemic cause (every consumer independently reimplementing subnet discovery) in place for the other ten teams, who will eventually hit the same class of bug with their own slightly-different-but-still-fragile filters.

### Follow-Up Questions
1. How would you decide how granular subnet-related outputs should be (by tier, by AZ, by both) without over-designing the interface?
2. What's the risk of exposing *too much* — e.g., every internal resource's full attribute set as outputs — and how does that differ from this under-design problem?
3. How would you encourage the ten teams with correct-but-fragile lookups to migrate, without forcing a disruptive simultaneous cutover?

### Key Interview Signals
Confirms the candidate treats module output design as a deliberate interface decision (what should consumers be guaranteed, not just what's minimally sufficient) rather than an afterthought.

### Hands-On Connection
[Lab 4 — Production Module Design](../labs/lab-04-module-design/).

---

## Question 28: The "patch" that forced replacement everywhere

### Scenario
A module author ships what they label a patch release (`2.3.1` → `2.3.2`) fixing a typo in a default tag value. Every consumer's next plan shows every tagged resource being updated — expected and harmless — except one consumer's `aws_launch_template` resources show as **replaced**, not updated, because `tags` happens to be part of a `ForceNew` block for that specific resource type in their pinned provider version.

### Interview Question
Was this actually a safe patch release? How do you prevent this class of surprise?

### Strong Senior-Level Answer
**Initial assessment:** the *module* change was genuinely minor in intent, but its real-world impact depends on the *consuming provider's resource schema*, which the module author can't fully control or predict for every consumer's provider version — this is a subtler failure mode than a clear-cut breaking interface change.

**Technical reasoning:** semantic versioning classifies changes by *interface* impact (added/removed/changed inputs-outputs), but a default-value change can have *replacement* impact on specific resource types depending on which attributes are `ForceNew` in a given provider version — something not visible from the module's HCL alone without checking the actual provider schema for every resource type the module touches.

**Investigation process:** check the AWS provider's schema for `aws_launch_template` — confirm whether `tags` (or the specific default-changing attribute) is genuinely `ForceNew` for this resource type, and whether that's consistent across the provider versions different consumers are likely pinned to.

**Recommended solution:** for any module release touching a default value that flows into resource attributes, explicitly test (via the contract-testing matrix from [Question 23](#question-23-the-version-bump-that-broke-forty-repositories)) against every distinct resource type the module manages, checking specifically for unexpected `-/+` replacement in the resulting plan — not just "does it apply successfully," but "does the *kind* of diff match what's expected for a patch." If a default-value change would force replacement for some resource types, that's disqualifying for a patch/minor release; it needs to ship as a major version with an explicit callout, or the default change needs to be made opt-in (new resources get the new default; existing ones require an explicit value to change) rather than universal.

**Risk controls:** maintain a per-resource-type "replacement-sensitive attribute" list for the resource types your most-used modules manage, referencing the provider's own schema documentation, and check any default-value change against that list before release.

**Validation steps:** the contract-test matrix plan output should be diffed specifically for replacement operations, not just any change, since a plan showing updates is expected for a tag-default fix but a plan showing replacement means the release classification is wrong.

**Rollback or recovery strategy:** yank/patch the release to make the tag-default change conditional or opt-in; consumers who already applied the unwanted replacement need the standard replacement-recovery process (confirm no unacceptable disruption occurred, or plan a controlled re-provision if it did).

**Long-term prevention:** treat "does this change force replacement for any managed resource type" as a mandatory pre-release check for every module change, not just ones that look obviously interface-breaking.

### Step-by-Step Implementation
```hcl
# Safer default-value change: opt-in for existing resources, default for new ones
variable "default_tags" {
  type    = map(string)
  default = null
}
locals {
  # Only apply the corrected default if the consumer hasn't already pinned their own value
  effective_default_tags = coalesce(var.default_tags, { ManagedBy = "terraform" })  # corrected typo isolated here
}
```
```bash
# Contract-test check specifically for unexpected replacement, not just any diff
terraform show -json plan.out | jq '.resource_changes[] | select(.change.actions == ["delete","create"])'
```

### Under-the-Hood Explanation
Whether a changed attribute value causes an update or a replacement is determined entirely by the provider's schema (`ForceNew` marking on that attribute for that resource type), evaluated during the `PlanResourceChange` RPC (see [`terraform-internals.md` §9](../docs/terraform-internals.md#9-provider-rpc-communication)) — this is provider-schema-level information, invisible from the module's own HCL, which is exactly why a module author can ship a change that looks harmless in the module's code but has replacement impact for specific resource types/provider versions.

### Common Weak Answer
"Patch releases are safe by definition since they're just bug fixes — the provider must have a bug if this caused a replacement."

### Why the Weak Answer Fails
It's not a provider bug — `tags` being `ForceNew` for a given resource type (if that's genuinely the case) is documented, intended provider behavior; the module release process failed to check the real-world replacement impact of a seemingly-minor default change before calling it safe.

### Follow-Up Questions
1. How would you build automated tooling to check "does this default-value change risk forcing replacement" across every resource type a module touches, without manually cross-referencing provider docs each time?
2. How does this risk change across a provider *version* upgrade even with no module change at all?
3. Should a module ever hard-code awareness of specific resource types' `ForceNew` attributes, or is that too tightly coupling module logic to provider internals?

### Key Interview Signals
Tests whether the candidate recognizes that semver classification of a module change and its real replacement impact on consumers are two different things that can diverge, requiring an explicit check beyond "is this an interface change."

### Hands-On Connection
[Lab 11 — Native Terraform Testing](../labs/lab-11-testing/).

---

## Question 29: Retiring the ad hoc Git-tag module sources

### Scenario
Your organization's forty-plus internal modules are currently referenced by consumers via raw Git URLs with `?ref=` tags (`git::ssh://git@github.com/my-org/tf-modules.git//vpc?ref=v4.2.0`), scattered inconsistently across repos with no central visibility into which consumers use which module versions.

### Interview Question
Would you migrate to a private module registry, and how would you execute that migration with minimal disruption?

### Strong Senior-Level Answer
**Initial assessment:** yes — a private registry (Terraform Cloud/Enterprise private registry, or an equivalent) provides namespaced, discoverable source addresses, listed version history, and (in TFC/TFE specifically) consumer/usage visibility that raw Git-URL sourcing has none of; the operational blindness described (no central visibility into who's on what version) is precisely what a registry solves.

**Technical reasoning:** the migration is purely a `source`/`version` argument change per consumer — the module content itself doesn't need to change (a registry can be backed by the same Git repository's tags, so the underlying versioning scheme carries over).

**Investigation process:** inventory current usage first — for each of the forty modules, which consumers reference which ref, and are those refs actually valid semver tags already, or inconsistent ad hoc naming that needs cleanup before migration.

**Recommended solution:** stand up the private registry pointing at the existing Git repository (most registry implementations support this without moving the code), publish the existing tags as registry versions, then migrate consumers incrementally — each consumer's PR simply changes `source = "git::ssh://...?ref=v4.2.0"` to `source = "app.terraform.io/my-org/vpc/aws"` with `version = "4.2.0"` (or their nearest existing tag), verified via zero-diff plan (module source changes don't affect resource addresses, so this should be a genuine no-op for the underlying infrastructure).

**Risk controls:** migrate a small number of low-risk consumers first to validate the registry setup end-to-end (auth, version resolution, `init` behavior) before rolling out to all forty.

**Validation steps:** for each migrated consumer, `terraform init` followed by `terraform plan` should show zero changes — the module's actual resource declarations haven't changed, only its `source` addressing.

**Rollback or recovery strategy:** each consumer's migration is independent and reversible (revert the `source`/`version` change in their own repo) if the registry has an issue — no need to coordinate a rollback across all forty simultaneously.

**Long-term prevention:** once migrated, enforce (via a linter/policy check on consumer repos, or simply convention plus code review) that all new module consumption uses the registry address, not raw Git URLs, so the ad hoc pattern doesn't creep back in.

### Step-by-Step Implementation
```hcl
# Before
module "vpc" {
  source = "git::ssh://git@github.com/my-org/tf-modules.git//vpc?ref=v4.2.0"
}

# After
module "vpc" {
  source  = "app.terraform.io/my-org/vpc/aws"
  version = "~> 4.2.0"
}
```
```bash
terraform init
terraform plan   # expect 0 diff — only the module source addressing changed
```

### Under-the-Hood Explanation
A private module registry is, at its core, an index mapping `<namespace>/<name>/<provider>` addresses and semver-formatted version strings to the underlying source archives (frequently generated directly from the same Git tags already in use) — `terraform init` resolves the registry address via the registry's API instead of directly cloning a Git ref, but the actual module content downloaded is typically byte-identical to what the equivalent `?ref=` checkout would have produced, which is exactly why this migration doesn't affect resource addressing or state at all.

### Common Weak Answer
"Just tell everyone to switch to the registry going forward for new usage; we don't need to migrate the existing forty."

### Why the Weak Answer Fails
This leaves the exact operational blindness described in the scenario (no central visibility into version usage) unresolved for all existing consumption, which is the majority of the actual problem — a registry only delivers its visibility/discoverability benefit once consumers are actually using it.

### Follow-Up Questions
1. How would you handle module versions that were never given proper semver tags in the original Git-based scheme?
2. What additional value does a registry provide beyond addressing — how does it change your release process from Question 23?
3. How would you handle this migration for an organization without Terraform Cloud/Enterprise access, using a different private-registry-compatible mechanism?

### Key Interview Signals
Confirms the candidate can execute a low-risk, incremental, verifiable migration rather than proposing a disruptive simultaneous cutover, and understands what a registry actually adds operationally beyond "nicer source strings."

### Hands-On Connection
[Lab 4 — Production Module Design](../labs/lab-04-module-design/).

---

## Question 30: Proving a new module version won't break anyone before you ship it

### Scenario
Your platform team wants to publish a major version of the `rds` module that changes several defaults (enabling deletion protection by default, changing the default backup retention window). Given the module has around twenty-five known consumers, leadership wants confidence this won't repeat the Question 23 incident before it ships.

### Interview Question
Design the pre-release validation process.

### Strong Senior-Level Answer
**Initial assessment:** this calls for contract testing — validating the new module version against a representative sample of real consumer configurations, not just the module's own isolated unit tests, since the risk here is specifically about *consumer* impact.

**Technical reasoning:** the module's own `terraform test` suite (unit/plan-mode tests against synthetic inputs) verifies the module's internal logic is correct, but says nothing about whether *actual* consumers, with their actual existing state, would see an unacceptable diff (especially replacement) from adopting the new version.

**Investigation process:** pull a representative sample of the twenty-five consumers' actual module-call configurations (the `module` block plus their variable values) — ideally all twenty-five if feasible, or a sample weighted toward the ones managing the most critical/stateful databases.

**Recommended solution:** build a CI job that, for each sampled consumer configuration, pins the *new* module version, runs `terraform plan` against a copy of (or read-only access to) their actual state, and asserts: no unexpected replacement operations, and any changes present are limited to the expected set (e.g., `deletion_protection` flipping to true, `backup_retention_period` changing — both expected, in-place updates for RDS, not replacements). Any consumer configuration producing an unexpected replacement blocks the release until investigated.

**Risk controls:** for the specific new defaults chosen here (deletion protection on, longer backups) — these are *safety-increasing* changes, so the main risk isn't data loss from the module change itself, but forced downtime if either default happens to require replacement for a given consumer's specific RDS engine/configuration; confirm via the AWS provider docs that both attributes are in-place-updatable for the engines in use.

**Validation steps:** the contract-test matrix passing cleanly across all twenty-five (or the representative sample) is the release gate — not merely "the module's own tests pass."

**Rollback or recovery strategy:** ship behind a documented migration guide regardless of clean contract-test results, since real production state can still surface an edge case the sampled configurations didn't cover; be prepared to patch quickly if a consumer outside the sample hits an issue.

**Long-term prevention:** make this contract-test matrix a standing CI job (not a one-off exercise for this release) that runs automatically against every future major version candidate for this module.

### Step-by-Step Implementation
```bash
# Conceptual contract-test harness
for consumer in $(cat consumer-configs.list); do
  cp -r "fixtures/${consumer}" "workdir/${consumer}"
  sed -i 's/version = "~> 4\..*"/version = "~> 5.0"/' "workdir/${consumer}/main.tf"
  terraform -chdir="workdir/${consumer}" init
  terraform -chdir="workdir/${consumer}" plan -out=plan.out
  replacements=$(terraform -chdir="workdir/${consumer}" show -json plan.out \
    | jq '[.resource_changes[] | select(.change.actions == ["delete","create"])] | length')
  if [ "$replacements" -gt 0 ]; then
    echo "FAIL: ${consumer} shows unexpected replacement"
    exit 1
  fi
done
```

### Under-the-Hood Explanation
This is entirely orchestration around the standard `terraform plan -out` + `terraform show -json` mechanism (see [`cicd.md` §2](../docs/cicd.md#2-plan-generation-plan-artifacts-and-plan-integrity)) — the contract-testing insight isn't a new Terraform feature, it's applying the existing plan-inspection tooling programmatically across many real consumer fixtures instead of just one configuration under test, specifically filtering plan JSON for the `["delete","create"]` action pair that signals replacement.

### Common Weak Answer
"Run the module's test suite and if it passes, ship it."

### Why the Weak Answer Fails
The module's own test suite validates the module in isolation against synthetic test fixtures — it cannot catch an issue that only manifests against a *specific real consumer's* actual accumulated state and configuration history, which is exactly the class of problem that caused the Question 23 incident.

### Follow-Up Questions
1. How do you keep the representative-consumer fixture set up to date as consumers' own configurations evolve over time?
2. What would you do if one consumer, out of twenty-five, does show an unexpected replacement — does that block the whole release?
3. How does this contract-testing approach scale if the module has hundreds of consumers rather than twenty-five?

### Key Interview Signals
Distinguishes candidates who equate "tested" with "the module's own unit tests pass" from those who understand contract testing against real consumer state as the actual mitigation for the Question 23 class of incident.

### Hands-On Connection
[Lab 11 — Native Terraform Testing](../labs/lab-11-testing/).

---

## Question 31: The README that lied

### Scenario
A module's hand-maintained `README.md` documents seven input variables. The actual module, after eighteen months of incremental changes, has fourteen — the other seven were added without updating the README. A new engineer, following the README, misses a security-relevant optional variable entirely and ships a resource with a weaker-than-intended default.

### Interview Question
How do you prevent module documentation from silently going stale like this?

### Strong Senior-Level Answer
**Initial assessment:** hand-maintained documentation for a module's input/output reference is fundamentally unreliable at scale — the moment updating the README becomes a manual, easily-forgotten second step alongside an actual code change, it will drift, exactly as happened here.

**Technical reasoning:** the fix is generating the reference documentation directly from the module's own `variables.tf`/`outputs.tf` source (which are the actual, executable source of truth) rather than maintaining prose describing them separately.

**Investigation process:** confirm the actual current, correct interface directly from `variables.tf`/`outputs.tf` (never trust the stale README while doing this audit), and specifically flag any security-relevant variable (like the one at issue here) for review — was its default actually correct, or does the incident reveal a design issue (should this security-relevant setting have a default at all, versus being required so it can't be silently missed)?

**Recommended solution:** adopt `terraform-docs` (or equivalent) to auto-generate the variables/outputs reference table directly from source, wired into a pre-commit hook or CI check that fails the PR if the generated documentation doesn't match what's committed — making documentation drift structurally impossible to merge, not just discouraged.

**Risk controls:** for the specific security-relevant variable that was missed, consider whether it should have a `validation` block or be promoted to required (with no default) rather than optional-with-a-default — a required argument forces every consumer to make an explicit, conscious choice, rather than silently inheriting a default they never saw documented.

**Validation steps:** after wiring up `terraform-docs` in CI, verify the check actually fails on a deliberately-undocumented new variable added in a test PR, proving the gate works before relying on it.

**Rollback or recovery strategy:** not applicable — this is a tooling/process fix; the immediate incident (the misconfigured resource) needs its own separate remediation (correct the default going forward, review any already-deployed instances for the same gap).

**Long-term prevention:** apply the auto-generated-docs-plus-CI-gate pattern to every reusable module in the registry, not just this one, since stale documentation is a systemic risk across the whole module ecosystem, not unique to this module.

### Step-by-Step Implementation
```yaml
# .pre-commit-config.yaml (or equivalent CI step)
- repo: https://github.com/terraform-docs/terraform-docs
  hooks:
    - id: terraform-docs-go
      args: ["markdown", "table", "--output-file", "README.md", "--output-mode", "inject", "./modules/vpc"]
```
```bash
# CI gate: fail if generated docs don't match committed README
terraform-docs markdown table ./modules/vpc > /tmp/generated-readme-section.md
diff <(sed -n '/BEGIN_TF_DOCS/,/END_TF_DOCS/p' README.md) /tmp/generated-readme-section.md \
  || (echo "README out of date - run terraform-docs" && exit 1)
```

### Under-the-Hood Explanation
`terraform-docs` parses the module's actual `.tf` source (variable/output blocks, their types, descriptions, and defaults) directly via the same HCL parsing Terraform itself uses, rendering a table that is by construction always consistent with the real interface at generation time — the only way it can go stale is if someone changes the module without re-running the generator, which the CI diff-check step is specifically designed to catch and block.

### Common Weak Answer
"Remind the team to update the README whenever they add a variable."

### Why the Weak Answer Fails
This is the exact process that already failed for eighteen months across seven added variables — a reminder is not a control; the fix needs to make out-of-date documentation something CI mechanically rejects, not something that depends on every future contributor remembering.

### Follow-Up Questions
1. How would you handle documentation for module *behavior* that isn't just an input/output list (e.g., "this module assumes the VPC has DNS support enabled") — `terraform-docs` doesn't capture that.
2. Should the missed security-relevant variable in this incident have had a validation block, a required (non-default) status, or something else — how do you decide?
3. How would you audit whether other modules in your registry have the same documentation-drift problem right now?

### Key Interview Signals
Confirms the candidate reaches for an automated, CI-enforced solution over a process reminder, and separately considers whether the security-relevant variable's *design* (optional-with-default vs. required) contributed to the incident.

### Hands-On Connection
[Lab 4 — Production Module Design](../labs/lab-04-module-design/).

---

## Question 32: Adding an optional field without breaking anyone

### Scenario
Your `rds` module's `instance_config` input is a fixed object type with five required fields. You need to add a new capability — optional Multi-AZ support — without forcing all existing consumers to update their calls immediately.

### Interview Question
How do you add this without a breaking change?

### Strong Senior-Level Answer
**Initial assessment:** this is exactly what `optional()` type constraints (Terraform >= 1.3) are designed for — adding a new field to an object type with a default, so existing consumers who don't set it are entirely unaffected.

**Technical reasoning:** before `optional()` existed, adding a field to a fixed object type variable was itself a breaking change (every consumer's object literal would need the new field, or type checking would fail) — `optional()` specifically solves this class of backward-compatible evolution.

**Investigation process:** confirm the module's current minimum supported Terraform version constraint (`required_version`) actually allows `optional()` syntax — if the module still supports pre-1.3 Terraform for some legacy consumers, this feature isn't available and a different backward-compatible approach (a wholly separate new variable) would be needed instead.

**Recommended solution:** add `multi_az` as an `optional(bool, false)` field within the existing `instance_config` object type — existing consumers' calls, which don't set this field, automatically get `false` (preserving current behavior exactly), while new/updating consumers can set `multi_az = true` explicitly.

**Risk controls:** this can genuinely ship as a **minor** version bump (a backward-compatible addition), not a major — confirm via the contract-test matrix (Question 30) that existing consumers show zero diff after upgrading to the new minor version, proving the addition is truly transparent to them.

**Validation steps:** a `terraform test` case explicitly asserting that omitting `multi_az` in the input produces `false` in the resulting resource's `multi_az` argument, and that setting it explicitly to `true` produces `true`.

**Rollback or recovery strategy:** not applicable — purely additive change, no existing behavior altered.

**Long-term prevention:** default to `optional()` fields for any new capability being added to an existing object-typed variable, reserving new top-level variables only for genuinely independent concerns.

### Step-by-Step Implementation
```hcl
variable "instance_config" {
  type = object({
    engine            = string
    instance_class    = string
    allocated_storage = number
    engine_version    = string
    identifier        = string
    multi_az          = optional(bool, false)   # new, backward-compatible
  })
}

resource "aws_db_instance" "this" {
  engine            = var.instance_config.engine
  instance_class    = var.instance_config.instance_class
  allocated_storage = var.instance_config.allocated_storage
  engine_version    = var.instance_config.engine_version
  identifier        = var.instance_config.identifier
  multi_az          = var.instance_config.multi_az
}
```
```hcl
# tests/multi_az_defaults.tftest.hcl
run "omitting_multi_az_defaults_false" {
  command = plan
  variables {
    instance_config = {
      engine            = "postgres"
      instance_class    = "db.t3.micro"
      allocated_storage = 20
      engine_version    = "16.3"
      identifier        = "test-db"
    }
  }
  assert {
    condition     = aws_db_instance.this.multi_az == false
    error_message = "multi_az should default to false when omitted"
  }
}
```

### Under-the-Hood Explanation
`optional(type, default)` is resolved during Terraform's type-checking/conversion phase for object-typed values: when a consumer's supplied object literal omits the field, Terraform substitutes the declared default before any further evaluation, so from the module's internal logic's perspective, the field is always present with either the consumer-supplied or default value — there is no code-path difference between "consumer omitted it" and "consumer explicitly set it to the default," which is exactly what makes this backward-compatible at the type-system level.

### Common Weak Answer
"Just add a new top-level `multi_az` variable instead of touching the object type, to be safe."

### Why the Weak Answer Fails
While technically also non-breaking, this fragments the module's interface unnecessarily — related configuration for one resource ends up split across an object-typed variable and several unrelated flat variables, degrading interface clarity over time as this pattern repeats for future additions, when `optional()` handles the same requirement cleanly within the existing structure.

### Follow-Up Questions
1. How would you handle this same requirement for a module still constrained to a pre-1.3 Terraform version?
2. What happens if you need to add a *required* new field to an existing object type — is there any backward-compatible way to do that?
3. How do `optional()` object attributes interact with `validation` blocks that reference the optional field?

### Key Interview Signals
Confirms the candidate knows the specific, modern language feature designed for this exact backward-compatibility problem, rather than reaching for a workaround.

### Hands-On Connection
[Lab 4 — Production Module Design](../labs/lab-04-module-design/).

---

## Question 33: The module that let you forget encryption

### Scenario
An S3-bucket-provisioning module has an `enable_encryption` variable defaulting to `true`, but nothing stops a consumer from explicitly setting it to `false` — which one team did, unintentionally, by copy-pasting an example from an internal wiki page that had it disabled for a local-testing scenario.

### Interview Question
How would you make it structurally difficult to ship an unencrypted bucket through this module, while still allowing a genuine, reviewed exception?

### Strong Senior-Level Answer
**Initial assessment:** a default, even a safe one, is not a guardrail — it only protects consumers who don't override it, and this scenario shows how easily an override can happen accidentally (copy-pasted example code) rather than through a deliberate, reviewed decision.

**Technical reasoning:** the fix is a `precondition` (or a `validation` block, depending on whether the check depends only on input or also on other resource state) that actively rejects the unsafe combination unless a second, explicit, harder-to-copy-paste-accidentally signal is also present — raising the bar from "one flag flipped" to "a deliberate, named exception."

**Investigation process:** confirm this is genuinely a case where *no* legitimate production use case needs unencrypted storage (likely true for this org) versus a case where a rare, real exception exists (e.g., a specific compliance-approved scenario) — the design differs based on that answer.

**Recommended solution:** if no legitimate use case exists, remove the ability to disable encryption entirely — hardcode `enable_encryption` as always-true internally, removing the variable altogether (a major-version change, with a migration note explaining why). If a rare, legitimate exception does exist, keep the toggle but pair it with a `precondition` requiring an explicit, harder-to-accidentally-set companion variable (e.g., `unencrypted_bucket_exception_ticket = "SEC-1234"`, a non-empty string referencing an approval ticket) — making the unsafe path require deliberate, documented justification rather than a single silent boolean flip.

**Risk controls:** pair this module-level guard with a policy-as-code check (Conftest/OPA) as defense-in-depth, so the guard holds even for any code path that might bypass the module (a raw resource declared outside the module, or an older module version still in use).

**Validation steps:** a `terraform test` case with `expect_failures` confirming that `enable_encryption = false` without the exception ticket is rejected, and that providing both together is accepted.

**Rollback or recovery strategy:** for the team that already shipped an unencrypted bucket, this requires a real remediation: enable encryption on the existing bucket (note: enabling encryption on an existing S3 bucket doesn't retroactively encrypt already-stored objects — a re-upload/copy step or lifecycle policy may be needed depending on compliance requirements) and audit what, if anything, sensitive was stored there while unencrypted.

**Long-term prevention:** apply the same "should this ever be legitimately disabled, and if so, what makes disabling it deliberate rather than accidental" question to every other security-relevant boolean default across all modules in the registry.

### Step-by-Step Implementation
```hcl
variable "enable_encryption" {
  type    = bool
  default = true
}
variable "unencrypted_bucket_exception_ticket" {
  type    = string
  default = null
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  count  = var.enable_encryption ? 1 : 0
  bucket = aws_s3_bucket.this.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }

  lifecycle {
    precondition {
      condition = var.enable_encryption || (
        var.unencrypted_bucket_exception_ticket != null &&
        length(var.unencrypted_bucket_exception_ticket) > 0
      )
      error_message = "Disabling encryption requires unencrypted_bucket_exception_ticket referencing an approved exception ticket."
    }
  }
}
```

### Under-the-Hood Explanation
`precondition` blocks inside a resource's `lifecycle` are evaluated during the plan graph walk, before the resource's own create/update operation is attempted — a failing precondition halts the plan for that resource (and anything depending on it) with the custom error message, giving immediate, specific feedback rather than allowing an insecure configuration to reach apply. This is a plan-time-only, Terraform-Core-level check — it doesn't touch AWS at all, which is why the policy-as-code backstop (evaluated independently against the plan JSON) matters for defense-in-depth against any path that bypasses this module.

### Common Weak Answer
"The default is already `true`, so this is basically already safe."

### Why the Weak Answer Fails
The scenario explicitly demonstrates a default being overridden accidentally via copy-pasted example code — "the default is safe" provides zero protection against an override, accidental or otherwise; the fix must make the *unsafe override itself* harder to do by accident, not just make the *default* safe.

### Follow-Up Questions
1. How would you extend this "require an explicit exception marker" pattern to other security-relevant toggles across your module registry consistently?
2. What's the trade-off between removing the toggle entirely (hardcoding safety) versus keeping it with a friction-adding precondition?
3. How would a policy-as-code check catch this same misconfiguration for a raw `aws_s3_bucket` resource declared entirely outside this module?

### Key Interview Signals
Tests whether the candidate reaches for structural friction (a precondition requiring deliberate justification) rather than trusting a default alone, and considers defense-in-depth via policy-as-code for paths the module itself can't cover.

### Hands-On Connection
[Lab 4 — Production Module Design](../labs/lab-04-module-design/) and [Lab 13 — Policy as Code](../labs/lab-13-policy-as-code/).

---

## Question 34: Sunsetting the module nobody was supposed to still be using

### Scenario
Two years ago, your team published a `legacy-alb` module and later replaced it with a much-improved `alb` module. The legacy module was never formally deprecated — it's still in the registry, still technically works, and a recent audit discovered six consumers still using it, including one added just last month by a new hire who had no idea a newer module existed.

### Interview Question
Design the deprecation and migration process, including how you'd have prevented the new hire from picking the legacy module in the first place.

### Strong Senior-Level Answer
**Initial assessment:** the core failure is that "replaced" was never actually communicated or enforced anywhere discoverable — the legacy module looked, to a new hire searching the registry, exactly as valid and current as the replacement, because nothing marked it otherwise.

**Technical reasoning:** deprecation needs to be visible at the point of discovery (the registry listing itself), not just known informally within the team that made the change.

**Investigation process:** confirm exactly what differs functionally between `legacy-alb` and `alb` for each of the six current consumers — is this a drop-in swap, or does it require configuration changes (renamed variables, different defaults) that need per-consumer migration work?

**Recommended solution:** immediately update the legacy module's README and registry description with an explicit, prominent deprecation notice naming the replacement and a sunset date; if the registry platform supports it, mark the module version itself as deprecated so `terraform init`/searches surface a warning. Set a real, communicated sunset date (e.g., 90 days) giving the six consumers a concrete migration window, with the platform team providing a migration guide (and, ideally, `moved`-block-equivalent guidance if resource addressing differs between the two modules) to make the six migrations as low-friction as possible. After the sunset date and confirmed migration of all six, remove the legacy module from the registry entirely (or leave a final version that immediately errors with a clear message pointing to the replacement, if outright removal risks breaking anyone unexpectedly still pinned to it).

**Risk controls:** track migration completion per consumer explicitly (a simple checklist/ticket) rather than assuming everyone migrated just because the deadline passed — confirm before removing the legacy module.

**Validation steps:** each of the six consumers should show a zero-diff (or an expected, reviewed, intentional diff) plan after migrating to the new module, verified the same as any other module-version migration.

**Rollback or recovery strategy:** keep the legacy module's last version available (even if deprecated/removed from active registry search) for a defined grace period after the official sunset, purely so a consumer who somehow missed the migration window isn't immediately broken — but this is a safety net, not license to skip the active migration push.

**Long-term prevention:** establish a standing convention that any module replacement is immediately paired with a registry-level deprecation notice on the old one, not a purely informal, team-internal understanding — and periodically audit the registry for modules that have had zero commits/updates in a long time as a signal to check whether they're actually still meant to be current.

### Step-by-Step Implementation
```markdown
<!-- legacy-alb/README.md, top of file -->
> **DEPRECATED**: This module is replaced by [`alb`](https://registry.example.com/my-org/alb/aws).
> Sunset date: 2026-10-24. New usage is not supported. See [migration guide](MIGRATION.md).
```
```hcl
# legacy-alb, final published version: fail loudly rather than silently keep working past sunset
# (illustrative - actual mechanism depends on registry platform's deprecation support)
```
```bash
# Track migration completion explicitly, don't assume
grep -rl 'source.*legacy-alb' --include='*.tf' ~/repos/*/  # re-audit before removal
```

### Under-the-Hood Explanation
There's no Terraform-Core mechanism that automatically flags a module as deprecated to consumers — this is entirely a registry-platform and documentation-convention concern (Terraform Cloud/Enterprise private registries support marking versions/modules deprecated in their own metadata, surfaced in the UI and, for some configurations, as an `init`-time warning; a purely Git-tag-based module source has no equivalent built-in mechanism at all, reinforcing the value of a real registry from [Question 29](#question-29-retiring-the-ad-hoc-git-tag-module-sources)).

### Common Weak Answer
"Just tell people not to use the legacy module anymore."

### Why the Weak Answer Fails
This is exactly the informal, team-internal-knowledge approach that already failed — a new hire with no access to that tribal knowledge had no way to discover the module was deprecated, because nothing about the module itself, in the place they'd actually go looking (the registry), indicated it.

### Follow-Up Questions
1. How would you handle a consumer who, after the sunset date, still can't migrate in time due to their own unrelated project constraints — do you extend the deadline, or force the issue?
2. What would you do differently if the legacy and replacement modules had significantly different resource types under the hood (not just a renamed interface), making migration inherently riskier?
3. How do you build an organizational habit of always pairing a module replacement with a deprecation notice, rather than relying on remembering to do it each time?

### Key Interview Signals
Confirms the candidate treats deprecation as requiring visible, discoverable, registry-level signaling — not an assumption that "everyone will just know" — and designs a concrete sunset timeline with real migration support, not an open-ended informal request.

### Hands-On Connection
[Lab 4 — Production Module Design](../labs/lab-04-module-design/).
