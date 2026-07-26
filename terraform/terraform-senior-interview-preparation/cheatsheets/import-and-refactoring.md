# Cheat Sheet: Import and Refactoring

## Importing existing infrastructure
1. Check the provider registry docs for the resource type's exact import ID format — never guess (see [Question 92](../interview-questions/10-troubleshooting.md#question-92-the-import-that-needed-three-tries-to-get-the-ide-right)).
2. Write an `import` block (not the legacy imperative command).
3. Run `terraform plan -generate-config-out=generated.tf` if you don't already have matching configuration.
4. Review the generated configuration carefully against the resource's real settings.
5. Apply (writes state only — the resource is untouched).
6. Run `terraform plan` again — **must show zero changes**. Any diff means your config doesn't yet match reality.

## Refactoring without recreation
| Scenario | Tool | Verification |
|---|---|---|
| Renaming a resource / `count` → `for_each` migration | `moved` block or `terraform state mv` | `terraform plan` shows zero diff |
| Splitting one state into two | `terraform state mv -state-out=` per resource | Both states independently show zero diff after |
| Merging two states into one | `terraform state mv` in reverse, resolving name collisions | Combined state's plan covers exactly the union of both originals |
| Flattening nested modules | `moved` blocks mapping old nested address → new address | Zero diff; also confirm reduced `validate`/`plan` time |
| CloudFormation → Terraform adoption | `import` blocks, dependency order, then CloudFormation "retain resources" stack deletion | Zero diff per resource before touching the CFN stack |

## The golden rule
**If a refactor is done correctly, `terraform plan` shows zero changes.** Any create/destroy appearing after a "pure" refactor means the migration was done wrong — Terraform has no innate understanding that a renamed/moved address refers to "the same" resource unless told explicitly via `moved`/`state mv`/`import`.

## Common mistake
Applying new `for_each`/renamed configuration **without** a corresponding `moved` block or `state mv` — Terraform sees a resource address with no state entry (create) and a state entry with no matching config (destroy) → full replacement, not a refactor. See [Question 1](../interview-questions/01-terraform-core.md#question-1-the-subnet-that-shifted) and [Question 9](../interview-questions/01-terraform-core.md#question-9-converting-a-legacy-count-fleet-to-for_each-without-downtime).

Full hands-on: [Lab 6](../labs/lab-06-import-existing-infrastructure/), [Lab 7](../labs/lab-07-refactoring-state/).
