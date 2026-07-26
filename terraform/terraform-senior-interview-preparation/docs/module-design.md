# Module Engineering

Modules are Terraform's unit of reuse and, more importantly at scale, Terraform's unit of **organizational contract**. A module interface is a promise to every consumer of that module; breaking it without a plan is how one team's Tuesday afternoon refactor becomes forty other teams' Wednesday incident. This document backs [`interview-questions/03-modules.md`](../interview-questions/03-modules.md) and is exercised in [Lab 4](../labs/lab-04-module-design/), [Lab 5](../labs/lab-05-multi-environment/), and [Lab 7](../labs/lab-07-refactoring-state/).

## 1. Root modules vs. child modules

The **root module** is whatever directory you run `terraform init`/`plan`/`apply` in — it defines the state boundary (one root module = one state, per backend configuration). **Child modules** are reusable building blocks called via `module` blocks; they have no state of their own — their resources live in the *calling* root module's state, namespaced under `module.<name>`.

**Why this distinction matters:** engineers sometimes assume "breaking a config into modules" reduces blast radius. It doesn't, by itself — module boundaries are a *code organization* boundary, not a *state* boundary. Blast radius reduction requires separate **root modules with separate state**, not just separate child modules called from the same root (see [`state-management.md`](state-management.md#state-splitting) and the layered architecture in [`terraform-architecture.md`](terraform-architecture.md#enterprise-architecture)).

## 2. Designing the module interface (inputs/outputs as an API contract)

A module's `variables.tf` and `outputs.tf` are its public API. Senior module design treats these with the same discipline as a versioned library API:

- **Required vs. optional inputs**: use `optional()` type constraints (Terraform >= 1.3) with sensible defaults instead of forcing every consumer to specify every field. `variable "instance_config" { type = object({ size = string, monitoring = optional(bool, false) }) }` lets new optional fields be added without breaking existing callers who don't set them.
- **Validation blocks**: fail fast, in the *module*, with a clear message, rather than letting a bad input propagate into a cryptic provider-level error three resources deep.

```hcl
variable "cidr_block" {
  type = string
  validation {
    condition     = can(cidrnetmask(var.cidr_block))
    error_message = "cidr_block must be a valid IPv4 CIDR, e.g. 10.0.0.0/16."
  }
}
```

- **Preconditions/postconditions on module outputs**: assert invariants about what the module actually produced, not just what was configured — e.g., asserting a computed subnet count matches the number of AZs requested.
- **Output design**: expose the minimum surface consumers need, but expose *enough* — a VPC module that only outputs `vpc_id` and forces every consumer to re-derive subnet IDs via data sources is under-designed; conversely, a module that dumps every internal resource's full attribute set as outputs has no real interface at all (any internal refactor becomes a breaking change because consumers may depend on internal-only outputs). Aim for outputs that describe *what the module guarantees to provide*, not *what it happens to currently contain*.

## 3. Module composition and dependency design

**Composition patterns:**
- **Root module composes children**: the common, recommended pattern — a root module for an environment calls `module.vpc`, `module.eks`, `module.rds`, wiring outputs of one into inputs of another. This keeps the dependency graph explicit and visible in one place.
- **Avoid deeply nested modules** (module calling module calling module, 3+ levels deep): each layer adds indirection, obscures the actual resource graph, slows `terraform plan`/`validate`, and makes "where does this input actually end up" a multi-hop search. If you find yourself passing a variable through two layers of modules untouched just to reach a third, that's a sign the composition should be flattened or the intermediate layer should own that concern directly.
- **Avoid circular dependencies between modules** (e.g., a networking module needing a security group ID from a security module, while the security module needs a subnet ID from the networking module): Terraform has no mechanism to resolve this — a real cycle is a plan-time error. The fix is almost always **extracting the shared concern into a layer both depend on** (e.g., both take a `vpc_id` as an input from a layer above, instead of depending on each other), or **splitting by resource type rather than by "logical area"** (e.g., a single module owns both the security group *and* the subnet association if they're this tightly coupled, rather than being artificially split across two modules that both need the other's output).

## 4. Avoiding overly generic modules

A module that accepts fifty optional variables to handle every conceivable EC2 configuration across every team is not flexible — it's unmaintainable and its interface has no opinion, which means every consumer re-derives correct usage from scratch and mistakes proliferate. Two competing philosophies, and when to pick each:

- **Opinionated modules**: encode your organization's standards directly (e.g., an `rds` module that *always* enables encryption, *always* sets a backup window, and only exposes `engine`, `instance_class`, and `allocated_storage` as inputs). Faster onboarding, fewer footguns, harder to misuse — but requires genuine organizational consensus on the "one right way," and a real escape hatch (see below) for the legitimate exception.
- **Flexible/composable modules**: expose most underlying resource arguments, trusting the consumer to assemble a secure, correct configuration. Appropriate for platform teams building primitives for *other module authors*, not for teams building the thing application engineers consume directly.

**Practical middle ground used throughout this repository's `modules/`**: opinionated defaults for everything security/compliance-relevant (encryption, logging, tagging), with narrow, explicit overrides only where a real, recurring need exists — not a blanket "pass through every provider argument" escape hatch.

## 5. Module versioning and semantic versioning

Every module — whether in a private registry, a Git repo referenced by tag, or a local path used across a monorepo — needs an explicit version contract:

```hcl
module "vpc" {
  source  = "app.terraform.io/my-org/vpc/aws"
  version = "~> 4.2.0"
}
```

**Semantic versioning discipline for module authors:**
- **Patch** (`4.2.0` → `4.2.1`): bug fixes, no interface change, no plan diff for any correctly-using consumer.
- **Minor** (`4.2.x` → `4.3.0`): backward-compatible additions — new optional inputs (with defaults), new outputs. Existing consumers see no forced changes.
- **Major** (`4.x` → `5.0.0`): any breaking change — a required-input rename, a removed output, a changed resource type that forces replacement for existing consumers, a changed default that alters behavior. **This is the version bump that must never happen silently.**

**The 40-broken-consumers scenario** (a canonical senior question — see [`interview-questions/03-modules.md`](../interview-questions/03-modules.md)): the root cause is almost always one of: (a) no version pinning in consumers (`version = ">= 4.0"` instead of a constrained range), (b) a breaking change shipped as a minor/patch bump because the change wasn't recognized as breaking, or (c) no pre-release validation against real consumer configurations. The fix is structural, not a one-time apology:
1. **Pin, don't float**: consumers use `~>` constraints scoped to a major version at minimum; never unconstrained `>=`.
2. **Deprecate before removing**: mark old inputs/outputs deprecated (via documentation and, where the provider/language allows, actual deprecation warnings) for at least one minor version before a major bump removes them.
3. **Publish a compatibility/migration guide per major version**, and where feasible, a `moved` block-based upgrade path so consumers get zero-diff plans across the major bump wherever the underlying resources didn't actually need to change.
4. **Validate breaking changes against a representative sample of real consumer configurations** (contract tests — see [`testing.md`](testing.md)) before publishing, not after the breakage reports come in.
5. **Communicate the deprecation timeline** through whatever channel your organization uses for platform announcements, with a hard sunset date.

## 6. Module registries

- **Public registry** (registry.terraform.io): fine for genuinely generic community modules; not appropriate as the home for your organization's internal, opinionated modules.
- **Private module registry** (Terraform Cloud/Enterprise private registry, or a Git-based private registry via the standard `git::` / SSH source syntax with tags as versions): the correct home for internal platform modules — gives you version listing, usage/consumer visibility (in TFC/TFE), and a stable, namespaced source address (`app.terraform.io/my-org/vpc/aws`) instead of every consumer hand-rolling a `git::ssh://...?ref=v4.2.0` source string.
- **Air-gapped/offline environments**: private registries or a Git-based source with an internal mirror are required when public registry access is blocked — see [`terraform-architecture.md`](terraform-architecture.md#air-gapped-environments) for the provider-side equivalent (provider mirrors).

## 7. Module testing

Covered in depth in [`testing.md`](testing.md), summarized here as it relates to module design specifically: every module intended for reuse by more than one consumer needs, at minimum, a `terraform test` suite covering (a) a valid, minimal configuration applies/plans cleanly against a mocked or real provider, (b) invalid inputs are rejected by `validation` blocks with the expected error, and (c) key output values match expectations. This is what makes it *safe* to publish a new module version at all — see [Lab 11](../labs/lab-11-testing/).

## 8. Module documentation

Minimum bar for any module intended for reuse: a `README.md` covering purpose, a minimal usage example, the full input/output reference (auto-generated via `terraform-docs` is strongly preferred over hand-maintained tables, which drift out of date), any preconditions/assumptions the module doesn't itself enforce (e.g., "assumes the VPC has DNS support enabled"), and the module's versioning/support policy. Undocumented internal modules are a common source of the "nobody knows why changing this variable breaks three other things" problem.

## 9. Upgrade and deprecation strategies

For a module consumer facing a major version upgrade:
1. Read the migration guide / CHANGELOG for the target major version.
2. Run `terraform plan` against the new version **in a non-production environment first**, even if the module claims compatibility.
3. Look specifically for unexpected `-/+` (replace) operations — a well-executed major bump minimizes forced replacements via `moved` blocks, but not every breaking change can avoid them (e.g., a genuine resource-type change).
4. Stage the rollout: lowest-risk environment first, with a defined rollback plan (pin back to the prior version — but note rollback isn't always clean if the new version already applied a destructive change; this is why non-prod validation matters more than a rollback plan for anything replace-heavy).

For a module *author* deprecating an old module/version: announce, provide the replacement, support both in parallel for a defined window, and only remove the old version from the registry after telemetry/consumer audit confirms no active usage — never delete a version consumers may still be pinned to without notice, since that breaks `terraform init` for anyone still on it.

## Common weak answer vs. senior answer

| Scenario | Weak answer | Senior answer |
|---|---|---|
| Module broke 40 consumers | "We should test modules before release" | Root-cause is unpinned consumer versions + no breaking-change classification; fix requires semver discipline, deprecation windows, `moved` blocks, and contract tests against real consumer configs — not just "test more" |
| Should this be one flexible module? | "Yes, more flexibility is always better" | Opinionated modules with narrow, deliberate escape hatches are usually correct for application-facing modules; full flexibility is appropriate only for low-level platform primitives |
| Circular dependency between two modules | "Add `depends_on` to force ordering" | `depends_on` can't break a genuine cycle; the fix is extracting the shared concern into a layer both depend on, or merging the two modules if they're this tightly coupled |
| Nested modules 4 levels deep | "That's fine, it's more organized" | Deep nesting obscures the real resource graph and slows plan/validate; flatten or have the intermediate layer own the concern directly |

## Related material
- Interview questions: [`interview-questions/03-modules.md`](../interview-questions/03-modules.md)
- Hands-on: [Lab 4 — Production Module Design](../labs/lab-04-module-design/), [Lab 5 — Multi-Environment Architecture](../labs/lab-05-multi-environment/), [Lab 7 — Refactoring Without Recreation](../labs/lab-07-refactoring-state/)
- Diagrams: [`diagrams/12-module-dependency.md`](../diagrams/12-module-dependency.md)
