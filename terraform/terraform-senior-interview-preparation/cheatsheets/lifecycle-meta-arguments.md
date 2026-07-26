# Cheat Sheet: Lifecycle Meta-Arguments

| Meta-argument | What it does | When to use it | Common mistake |
|---|---|---|---|
| `create_before_destroy = true` | Creates the replacement before destroying the old resource | Anything else depends on this resource staying available during replacement (launch templates, referenced security groups) | Forgetting the resource needs a `name_prefix` instead of a fixed `name` to avoid a collision during the overlap |
| `prevent_destroy = true` | Errors the plan/apply if it would destroy this resource | Production stateful resources (databases) | Believing it stops manual/console deletion — it's a **Terraform Core plan-time guard only**, no AWS-side effect |
| `ignore_changes = [attr, ...]` | Stops diffing on specific attributes after creation | An attribute genuinely, narrowly owned by another system (e.g., a tag set by a compliance Lambda) | `ignore_changes = all` — silences drift detection on *everything*, usually a sign the resource shouldn't be fully Terraform-managed |
| `replace_triggered_by = [ref, ...]` | Forces replacement when a referenced value changes, even if not directly used | Forcing an ASG instance refresh when `user_data`'s hash changes | Using this as a substitute for a genuine dependency edge — it's for *triggering* replacement, not *ordering* |
| `precondition { condition = ... }` | Plan-time assertion before an operation, inside a resource/data source/module's `lifecycle` | "This AMI's architecture matches the instance type" | Expecting it to catch drift after apply — it only runs during plan/apply, not continuously |
| `postcondition { condition = ... }` | Plan-time assertion about the *result* of an operation | "The ALB actually has a non-empty DNS name" | Confusing with `check` blocks (below) — postconditions are scoped to one resource's own operation |
| `check` blocks (top-level, >= 1.5) | Standing assertion independent of the resource graph, warns (doesn't fail) | "This ACM certificate isn't within 30 days of expiry" | Expecting a hard failure — `check` blocks warn, they don't block the plan |

## `prevent_destroy` decommission procedure
1. Remove/flip the guard in a reviewed commit alone — confirm the resulting plan is a no-op.
2. In a **separate** step, remove the resource (or use a `removed` block) — confirm the plan shows *exactly* the intended destroy.
3. Never bypass via `state rm` + manual deletion — that desyncs state from reality.

See [Question 3](../interview-questions/01-terraform-core.md#question-3-decommissioning-a-prevent_destroy-protected-resource) and [Question 4](../interview-questions/01-terraform-core.md#question-4-the-launch-template-nobody-could-safely-swap).

## Provisioners
`local-exec`/`remote-exec` are a last resort — no drift detection, no idempotency guarantee, run outside the provider RPC model entirely. Prefer: `user_data`/cloud-init for bootstrapping, provider-native resources for configuration (e.g., `kubernetes_config_map` instead of `kubectl` via `local-exec`).
