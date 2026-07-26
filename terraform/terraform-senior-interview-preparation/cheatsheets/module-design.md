# Cheat Sheet: Module Design

## Interface design
- Treat `variables.tf`/`outputs.tf` as a versioned API contract, not an internal implementation detail.
- Use `optional()` type constraints to add new object-type fields without breaking existing consumers (Terraform >= 1.3).
- Add `validation` blocks that fail fast with a clear message — never let a bad input reach a cryptic provider error.
- Outputs should expose what the module *guarantees*, not just the minimum technically sufficient (a VPC module should expose subnet IDs by AZ, not force consumers to re-derive them via fragile tag-based data sources).

## Opinionated vs. flexible
| | Opinionated | Flexible |
|---|---|---|
| Best for | Application-facing modules most teams consume directly | Low-level platform primitives for other module authors |
| Trade-off | Faster, harder to misuse; needs real org consensus | More powerful; every consumer must get security/compliance right themselves |
| Escape hatch | A single, narrow, reviewed override, not a blanket pass-through | N/A — flexibility *is* the design |

## Versioning discipline (semver)
- **Patch**: bug fix, no interface change, **no plan diff** for any correct consumer — including no unexpected *replacement*, which depends on the provider schema, not just the module's own diff (see [Question 28](../interview-questions/03-modules.md#question-28-the-patch-that-forced-replacement-everywhere)).
- **Minor**: backward-compatible addition (new optional input/output).
- **Major**: any removal/rename/behavior change that could break an existing consumer.
- Consumers pin with `~>`, never unconstrained `>=`.
- Before any major release: run a **contract test matrix** — the new version's plan against a representative sample of real consumer configurations, checking specifically for unexpected replacement (see [Question 30](../interview-questions/03-modules.md#question-30-proving-a-new-module-version-wont-break-anyone-before-you-ship-it)).

## Composition rules
- Child modules do **not** create state boundaries — they don't reduce blast radius by themselves (see [state-splitting cheat sheet content in state-commands.md](state-commands.md)).
- A genuine circular dependency between two modules can't be fixed with `depends_on` — extract the shared concern into a common layer, or merge the modules.
- Avoid nesting more than 2-3 levels deep — each layer must add real composition value, not just relay a variable unchanged (costs both debugging time and `validate`/`plan` performance).
- Reusable modules never declare their own `provider` block — inherit or require an explicit `configuration_aliases` pass-through.

## Deprecation
Mark deprecated modules **visibly at the point of discovery** (registry listing, not just team-internal knowledge), set a real sunset date, and provide a migration guide. See [Question 34](../interview-questions/03-modules.md#question-34-sunsetting-the-module-nobody-was-supposed-to-still-be-using).
