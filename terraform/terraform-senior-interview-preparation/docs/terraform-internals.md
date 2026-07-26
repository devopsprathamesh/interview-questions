# Terraform Internals: Language, Workflow, and Execution Model

This document covers what Terraform is actually doing when you run it — the language semantics that trip up experienced engineers, and the workflow internals (`init`/`plan`/`apply`/`destroy`) that you need to reason about correctly during an incident. This is reference material for [`interview-questions/01-terraform-core.md`](../interview-questions/01-terraform-core.md) and is exercised directly in [Lab 1](../labs/lab-01-core-workflow/) and [Lab 3](../labs/lab-03-state-locking/).

> Version note: examples target Terraform >= 1.7 (stable `import`/`moved`/`check` blocks, optional object attributes). Always confirm current behavior against the [official Terraform documentation](https://developer.terraform.io/terraform/language) before asserting version-specific claims in a real interview — behavior has changed across 0.12, 0.13, 1.0, 1.1 (`moved`), 1.3 (optional attributes), 1.5 (`import`/`check` blocks), and 1.7+ (`removed` blocks).

## 1. The execution model, end to end

Terraform's core loop for any operation is:

1. **Configuration loading** — parse all `.tf`/`.tf.json` files in the working directory (and, transitively, modules) into an in-memory representation.
2. **Graph construction** — build a directed acyclic graph (DAG) of every resource, data source, module call, output, and provider configuration, with edges representing dependencies.
3. **State loading** — read the current state (local file or remote backend), acquire a lock if the backend supports it.
4. **Refresh** — for each managed resource already in state, call the provider's `ReadResource` RPC to get its current real-world attributes (this is "refresh"; in modern Terraform it happens as part of plan, not as a separate always-on step).
5. **Diff calculation** — compare desired configuration against refreshed state to compute a per-resource diff: no-op, create, update in place, destroy, or destroy-and-recreate (replace).
6. **Plan graph walk** — walk the DAG, evaluating expressions in dependency order, propagating **unknown values** for anything that depends on a not-yet-created resource.
7. **Apply graph walk** (apply only) — walk the graph again, this time actually invoking `CreateResource` / `UpdateResource` / `DeleteResource` provider RPCs, in parallel where the graph allows, updating state incrementally after each successful operation.
8. **State write-back** — write the new state, bump the **serial**, release the lock.

Everything below is a deeper look at one of these stages.

## 2. Dependency graph construction

Terraform builds two related graphs: a **configuration graph** (from `depends_on`, resource attribute references, and module calls) and a **resource graph** used for the actual plan/apply walk.

**How edges are inferred:**
- **Implicit dependencies**: referencing `aws_subnet.private.id` inside an `aws_instance` resource creates an edge from the instance to the subnet.
- **Explicit dependencies**: `depends_on = [aws_iam_role_policy.example]` forces an edge even when there's no attribute reference — needed when a dependency is enforced by IAM eventual consistency or provider side effects that Terraform can't see in the schema.
- **Module-level dependencies**: a `depends_on` on a `module` block forces every resource inside that module to wait on the listed dependencies.
- **Provider dependencies**: resources implicitly depend on their `provider` configuration being fully evaluated (relevant when provider config itself references resource attributes, e.g., an EKS-derived provider — see [Lab 9](../labs/lab-09-eks-infrastructure/)).

**Why this matters in production:** the graph determines both correctness and parallelism. Terraform applies independent subgraphs concurrently (default `-parallelism=10`). Two resources with no dependency edge between them can and will be created in parallel — if one has a hidden runtime dependency Terraform doesn't know about (e.g., an AWS eventual-consistency race, or a resource that must exist before an API call in another resource's provisioner succeeds), you'll get intermittent apply failures that look like "flaky Terraform" but are actually a missing `depends_on`.

**Failure scenario:** an `aws_iam_role_policy_attachment` and an `aws_eks_node_group` are declared with no explicit dependency, but the node group's IAM role needs the policy attached before nodes can join the cluster. Terraform sees no attribute reference (the node group references the *role*, not the *policy attachment*), so it may create the node group before the policy attachment completes, causing node registration failures that only sometimes reproduce depending on scheduling.

**Fix:** add `depends_on = [aws_iam_role_policy_attachment.eks_worker_node_policy]` on the node group, or better, model the dependency so it's structurally required.

**Troubleshooting:** `terraform graph | dot -Tsvg > graph.svg` renders the actual dependency graph Terraform computed — use it to confirm an edge exists (or doesn't) rather than guessing.

## 3. Resource addressing

Every resource has a unique address: `module.<path>.<resource_type>.<name>[<index>]`.

- Root module resources: `aws_instance.web`
- Indexed resources (`count`): `aws_instance.web[0]`, `aws_instance.web[2]`
- `for_each` resources: `aws_instance.web["primary"]` (string key, always quoted)
- Nested modules: `module.vpc.module.subnets.aws_subnet.private[0]`

**Why this matters:** addresses are what you use with `terraform state mv`, `terraform state rm`, `import` blocks, `moved` blocks, and `-target`. Getting an address wrong during a state surgery (e.g., mixing up `count` index vs. `for_each` key) is one of the most common causes of accidental resource recreation — covered in depth in [`state-management.md`](state-management.md) and [Lab 7](../labs/lab-07-refactoring-state/).

## 4. `count` vs `for_each` — and the index-shifting failure mode

`count` produces a list indexed 0..n-1. `for_each` produces a map keyed by string.

**The classic production incident:** a list of subnets is created with `count = length(var.azs)`. Someone removes the *first* AZ from the list. Every subsequent index shifts down by one — Terraform now believes `aws_subnet.private[0]` (previously az-a) should have az-b's configuration, `[1]` should have az-c's, and so on. This isn't a no-op update; it's a chain of destroy/recreate operations across every subnet after the removed one, because the resource *identity* (the index) stayed the same while the *meaning* of that identity changed.

`for_each` avoids this because the resource identity is the map key (e.g., the AZ name itself), not a position. Removing `"us-east-1a"` from the map only destroys the one resource keyed `"us-east-1a"`; every other key's resource is untouched.

**Rule of thumb for senior engineers:** default to `for_each` for any collection of resources where membership can change over time (subnets, IAM users, security group rules, node groups). Reserve `count` for: (a) the 0/1 conditional-resource pattern (`count = var.enable_flag ? 1 : 0`), and (b) truly fixed-cardinality, order-independent sets where you're certain the list never gets items removed from the middle.

**Interview signal:** candidates who say "always use `for_each`" without understanding the 0/1 conditional idiom, or who don't immediately recognize index-shifting as a `count` problem, are usually mid-level, not senior.

## 5. `depends_on`, `lifecycle`, and the meta-arguments

### `lifecycle { create_before_destroy = true }`
Forces Terraform to create the replacement resource *before* destroying the old one, instead of the default destroy-then-create order. Required whenever something else depends on the resource staying available during replacement (e.g., a launch template referenced by an ASG, or a security group referenced by resources you can't tolerate losing connectivity to, even briefly). Without it, replacing a resource that's a hard dependency of other live infrastructure causes an availability gap.

**Constraint:** `create_before_destroy` requires that any resource depending on the replaced one can tolerate two instances existing simultaneously (e.g., unique-name constraints will break this — you often need a `name_prefix` instead of a fixed `name` when using this pattern).

### `lifecycle { prevent_destroy = true }`
Causes `terraform plan`/`apply` to error out (not just warn) if the plan includes destroying this resource. This is a **plan-time guard implemented entirely in Terraform Core**, not an AWS-side protection — it does nothing to stop a manual console deletion or an `aws cli` call. It also blocks legitimate decommissioning, which is the basis of one of the most common senior-level scenario questions (see [`interview-questions/01-terraform-core.md`](../interview-questions/01-terraform-core.md) and [`docs/troubleshooting.md`](troubleshooting.md)): the standard answer is a **two-step change** — remove or flip `prevent_destroy` to `false` in a reviewed, approved commit, run `plan` to confirm only the intended destroy appears, then apply. Never bypass it with `state rm` + manual deletion as a shortcut; that desyncs state from reality.

### `lifecycle { ignore_changes = [...] }`
Tells Terraform to stop reconciling drift on specific attributes after creation — commonly used for attributes mutated by external systems (autoscaling-adjusted `desired_capacity`, tags added by a tagging-compliance Lambda, AMI IDs rotated by a separate pipeline). **Risk:** overuse hides real drift and creates a false sense that "Terraform matches reality" when it structurally cannot detect divergence on ignored fields. `ignore_changes = all` is a smell — it usually means the resource shouldn't be *fully* managed by this configuration, and adoption boundaries need rethinking (see the drift-handling decision framework in [`docs/troubleshooting.md`](troubleshooting.md)).

### `lifecycle { replace_triggered_by = [...] }`
Forces replacement of a resource when a *referenced* value changes, even if that value isn't otherwise used in the resource's own arguments — e.g., forcing an ASG instance refresh when a launch template's `user_data` hash changes, or forcing a Kubernetes resource to be recreated when a ConfigMap it doesn't directly reference changes. This exists because Terraform's default replacement logic only fires from a resource's *own* schema-level diffs (see §8) — `replace_triggered_by` is the escape hatch for "these two things are logically coupled even though the provider schema doesn't say so."

### `precondition` / `postcondition` (inside `lifecycle` blocks on resources/data sources, and in `check` blocks)
- `precondition` validates an assumption **before** Terraform attempts the operation — e.g., asserting an AMI's architecture matches the instance type's required architecture, failing fast with a clear message instead of letting the cloud API reject it with an opaque error.
- `postcondition` validates the **result** of an operation — e.g., asserting a newly created ALB actually has a non-empty DNS name, or that a data source lookup didn't silently return an unexpected/empty result.
- `check` blocks (top-level, Terraform >= 1.5) run condition assertions **independently of the resource graph**, ideal for ongoing operational assertions ("this ACM certificate is not expired") that shouldn't block a plan but should surface a clear warning.

**Production value:** these convert "the apply succeeded but something is subtly wrong" into a loud, specific, plan-time or apply-time failure — this is what separates configurations that fail safely from configurations that fail silently. See [Lab 4](../labs/lab-04-module-design/) and [Lab 11](../labs/lab-11-testing/).

### Provisioners — and why to avoid them
`local-exec` / `remote-exec` provisioners run arbitrary scripts as part of create/destroy. They are **not tracked by the provider schema**, are **not idempotent by default**, have **no drift detection**, and their failures leave a resource "tainted" in ambiguous states. They exist as a last resort for cases with genuinely no API-driven alternative (rare in mature providers). Prefer: `user_data`/cloud-init for instance bootstrapping, provider-native resources for configuration (e.g., `kubernetes_config_map` instead of `kubectl` via `local-exec`), or a separate, properly idempotent configuration-management tool invoked *outside* the Terraform apply lifecycle. If you must use one, always pair `when = destroy` provisioners with `on_failure` handling and understand they run with the credentials of the machine running Terraform, not the resource.

## 6. Unknown values and plan construction

When a plan references an attribute of a resource that doesn't exist yet (e.g., `aws_instance.web.id` used in a security group description, where the instance hasn't been created), Terraform represents that value as **unknown** (shown as `(known after apply)`). Unknown values propagate through the graph: anything that depends on an unknown value is itself partially or fully unknown at plan time.

**Why this matters:** you cannot fully validate certain conditions until apply time — a `precondition` referencing an unknown value can't be evaluated during plan and effectively defers to apply. This is also why some `count`/`for_each` expressions that depend on unknown values fail with *"The 'for_each' value depends on resource attributes that cannot be determined until apply"* — Terraform must know the **shape** (number of instances / set of keys) of a resource at plan time, and an unknown value can't provide that. This is one of the most common real troubleshooting scenarios for engineers who chain data sources and dynamic resource creation.

**Practical fix pattern:** decouple the count/for_each key from the unknown value — key off something known at plan time (a variable, a literal list) rather than a computed attribute, or split the apply into two `terraform apply` phases / two root modules with a data source boundary between them.

## 7. Refresh behavior

Historically (`terraform plan` pre-0.15) refresh was an implicit, separate first phase. Modern Terraform performs refresh **as an integrated part of plan** by default. Flags of note (verify current flag names/defaults against your installed version):
- `-refresh=false` skips the read-before-plan step — faster, but the plan is only as accurate as the last-known state; risky right before a production apply.
- `-refresh-only` (a plan/apply mode) updates state to match real infrastructure **without proposing any configuration changes** — the correct tool for "sync state to reality after we confirmed manual changes are intentional and should be adopted as-is," distinct from `import` (which addresses one specific unmanaged resource) — see [`state-management.md`](state-management.md#drift).

## 8. Resource replacement, taint, and force-new attributes

A resource is replaced (destroy + create) instead of updated in place when:
- A **force-new** attribute changes — the provider schema marks certain attributes as `ForceNew` because the underlying cloud API has no update operation for that field (e.g., changing an RDS engine in some configurations, changing an EC2 instance's `availability_zone`).
- The resource is explicitly marked with `terraform apply -replace=<address>` (modern replacement for the deprecated `terraform taint` command).
- `replace_triggered_by` fires (see §5).

**"Tainted" resources (legacy concept):** `terraform taint` marked a resource in state as needing replacement on next apply. It's deprecated in favor of `-replace` on `plan`/`apply`, which achieves the same effect without a separate state-mutating command and is visible directly in the plan output before anything happens — a safer pattern for production.

**Investigating an unexpected replacement (classic troubleshooting scenario):** run `terraform plan` and read the `-/+` reason Terraform prints (modern Terraform explains *why* — e.g., `# forces replacement`) next to the specific attribute. Cross-reference against the provider's CHANGELOG if this appeared right after a provider version bump — provider upgrades sometimes change which attributes are `ForceNew`, or normalize values differently (e.g., a provider begins treating an empty string differently from null), which shows up as an unexpected replacement with no configuration change at all. This is exactly the "plan wants to replace a production database after a provider upgrade" scenario — see [`interview-questions/10-troubleshooting.md`](../interview-questions/10-troubleshooting.md) and [Lab 14](../labs/lab-14-drift-and-recovery/).

## 9. Provider RPC communication

Terraform Core and providers communicate over gRPC using the Terraform provider protocol (protocol version 5/6 depending on provider). Core does not know anything about AWS, Kubernetes, or any specific API — it knows only:
- The provider's **schema** (returned via a `GetProviderSchema` RPC at init/plan time): what resource types exist, what attributes they have, which are computed/optional/required, which are sensitive, which force replacement.
- How to call `PlanResourceChange`, `ApplyResourceChange`, `ReadResource`, `ImportResourceState`, etc., and interpret the structured (protobuf) responses.

**Why this matters operationally:**
- A **provider crash** (segfault, panic) during apply is a plugin process failure, not a Terraform Core bug — it's diagnosed via `TF_LOG=trace` provider logs, and the fix is almost always a provider version bump or an upstream bug report, not a state hack.
- **Provider schema changes** across versions are the root cause of most "nothing changed in my `.tf` files but the plan shows changes" incidents after `terraform init -upgrade`. The dependency lock file (`.terraform.lock.hcl`) exists specifically to make provider version changes an explicit, reviewed, committed event rather than a silent floating-version surprise — see [`terraform-architecture.md`](terraform-architecture.md#provider-engineering).

## 10. State serial, lineage, and reconciliation during apply

Covered in full in [`state-management.md`](state-management.md), but the workflow-relevant summary: every state file has a `lineage` (a UUID identifying "this state's family tree," set once at creation) and a `serial` (an incrementing counter bumped on every write). Backends that support locking use these together with the lock to detect and reject a stale write (e.g., someone applying against an out-of-date local plan file against a state that has since moved on). During apply, state is **rewritten incrementally after each resource operation completes** — not just once at the end — which is exactly why a partially-applied run still leaves you with an accurate (if incomplete) state file rather than losing track of what succeeded.

## 11. Exit codes

- `0`: success, no changes (or successful apply/destroy)
- `1`: error (config invalid, provider error, etc.)
- `2`: success, changes present (only relevant for `plan` with `-detailed-exitcode`, and for automation gating logic)

**Why this matters:** `-detailed-exitcode` is the mechanism CI/CD pipelines use to distinguish "plan succeeded with no diff" from "plan succeeded with a diff" from "plan failed," which is foundational to drift-detection jobs and merge-gating logic — see [`cicd.md`](cicd.md) and [Lab 12](../labs/lab-12-cicd-pipeline/).

## 12. Interrupted and partial applies

If `terraform apply` is interrupted (SIGINT/SIGTERM, CI runner killed, network loss to the backend), Terraform:
1. Attempts a graceful stop after the in-flight resource operations finish (a second Ctrl-C forces immediate exit, which is far riskier).
2. Has already written state for every resource operation that completed *before* the interrupt.
3. Leaves the **lock held** if the process is killed hard enough that it can't run its unlock defer — this is the single most common cause of "stale lock" incidents in CI.

**Recovery procedure (see [Lab 14](../labs/lab-14-drift-and-recovery/) for a full runbook):**
1. Determine what actually got created: compare `terraform state list` against the plan that was running, and independently check the cloud provider console/API for anything the plan intended to create.
2. Do **not** immediately re-run apply blind — run `terraform plan` first; a partially-applied run often produces a plan that cleanly finishes the remaining work, but you must read it to confirm it isn't proposing to replace something that partially succeeded in a way Terraform doesn't fully understand yet.
3. If the lock is stuck and you've confirmed (via the backend's own lock metadata — e.g., DynamoDB item, or the lock info in the error message) that no process actually holds it anymore, use `terraform force-unlock <lock-id>` — but only after confirming, never as a first response to a lock-timeout error.

## Common weak understanding vs. senior understanding

| Weak answer | Senior answer |
|---|---|
| "Terraform applies resources top to bottom as written" | Terraform builds a DAG from references and `depends_on`, and applies independent branches in parallel |
| "`count` and `for_each` are basically interchangeable" | `count` uses positional identity (shifts on list mutation); `for_each` uses key identity (stable under insertion/removal) |
| "`prevent_destroy` stops the resource from being deleted" | It's a Terraform Core plan-time guard only — it has no effect on manual cloud-side deletion, and legitimate decommission requires a deliberate config change to remove it |
| "A provisioner failing just means retry the apply" | Provisioner failures taint the resource and its idempotency is not guaranteed; prefer provider-native or bootstrap-time (user_data) alternatives |
| "The plan failed, just apply again" | First determine whether it's a transient API issue, a stale lock, a genuine config error, or drift — blind retries on a partial apply can trigger unintended replacements |

## Related material
- Interview questions: [`interview-questions/01-terraform-core.md`](../interview-questions/01-terraform-core.md)
- Hands-on: [Lab 1 — Terraform Core Workflow](../labs/lab-01-core-workflow/), [Lab 3 — Concurrent Execution and Locking](../labs/lab-03-state-locking/)
- Diagrams: [`diagrams/02-plan-workflow.md`](../diagrams/02-plan-workflow.md), [`diagrams/03-apply-workflow.md`](../diagrams/03-apply-workflow.md), [`diagrams/04-dependency-graph.md`](../diagrams/04-dependency-graph.md), [`diagrams/05-provider-rpc.md`](../diagrams/05-provider-rpc.md)
