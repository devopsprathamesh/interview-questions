# Production Troubleshooting Catalog

This is a consolidated runbook-style catalog of the failure modes senior Terraform interviews probe most often. Several are covered in full depth elsewhere in `docs/` — this document gives every scenario a fast-diagnosis entry point and cross-references the deep dive. It backs [`interview-questions/10-troubleshooting.md`](../interview-questions/10-troubleshooting.md) and is exercised in [Lab 3](../labs/lab-03-state-locking/), [Lab 6](../labs/lab-06-import-existing-infrastructure/), [Lab 7](../labs/lab-07-refactoring-state/), and [Lab 14](../labs/lab-14-drift-and-recovery/).

Every entry follows the same shape: **Symptom → Likely causes → Investigation → Fix → Prevention.** This mirrors the [Interview Response Framework](../README.md#interview-response-framework) — use that structure verbatim when answering any of these live.

## Provider and initialization failures

### Failed provider initialization
**Symptom:** `terraform init` fails to download/verify a provider.
**Likely causes:** network/registry unreachable, provider version constraint unsatisfiable, checksum mismatch against the lock file (tampered mirror, corrupted download, or a legitimate upstream change without `-upgrade`).
**Investigation:** re-run with `TF_LOG=debug`; check whether the org uses a provider mirror (§ [`terraform-architecture.md`](terraform-architecture.md#6-provider-installation-mirrors-and-air-gapped-environments)) that may be down or misconfigured; confirm the lock file's recorded checksums against what's actually being served.
**Fix:** correct the constraint or mirror configuration; only run `init -upgrade` deliberately and with the resulting lock file diff reviewed, never as a blind unblock.
**Prevention:** commit the lock file always; monitor mirror/registry availability as pipeline infrastructure, not an afterthought.

### Provider version incompatibility / unexpected replacement after upgrade
**Symptom:** `terraform plan` proposes replacing resources with no configuration change, immediately after `init -upgrade` or a bumped `required_providers` constraint.
**Deep dive:** [`terraform-internals.md` §8](terraform-internals.md#8-resource-replacement-taint-and-force-new-attributes), [`terraform-architecture.md` §3](terraform-architecture.md#3-provider-version-constraints-and-the-dependency-lock-file).
**Fast fix:** pin back to the last known-good provider version (`required_providers` + lock file), test the new version's plan output against every environment in a non-prod path first, and check the provider's CHANGELOG specifically for `ForceNew`/schema/default-value changes on the affected resource type before deciding whether to accept, work around (e.g., add `ignore_changes` if the "replacement" is actually just a normalization difference), or wait for a provider patch.

### Provider crash
**Symptom:** apply/plan aborts mid-run with a panic/segfault from the provider plugin process, not a clean Terraform error.
**Deep dive:** [`terraform-internals.md` §9](terraform-internals.md#9-provider-rpc-communication).
**Investigation:** `TF_LOG=trace` isolates which RPC call and which resource triggered the crash; check the provider's GitHub issues for a known bug matching the stack trace.
**Fix:** pin to a provider version without the bug, or work around the specific resource/argument combination that triggers it; file an upstream issue with the trace if none exists.
**Prevention:** treat provider upgrades with the same non-prod-first discipline as any other dependency upgrade.

## State-related failures

### State lock timeout / stale lock
**Deep dive:** [`state-management.md` §3](state-management.md#3-state-locking), [Diagram 7](../diagrams/07-state-locking.md), [Lab 3](../labs/lab-03-state-locking/).
**Fast fix:** confirm no live process holds the lock (check CI job status and lock metadata: `Who`, `Created`, `Operation`), then `terraform force-unlock <LOCK_ID>` — never force-unlock speculatively.

### Corrupt state / deleted state / lost state
**Deep dive:** [`state-management.md` §7](state-management.md#7-state-corruption-loss-and-recovery), [Lab 14](../labs/lab-14-drift-and-recovery/).
**Fast fix order:** backend version history restore → `-refresh-only` reconciliation → full rebuild via `import` blocks only as a last resort, networking/foundational resources first.

### Resource exists in the cloud but is missing from state
**Symptom:** `terraform plan` proposes to *create* a resource that already exists — applying it would either fail (name/uniqueness conflict) or silently create a duplicate.
**Likely causes:** a previous `terraform state rm` without corresponding config removal, a failed import that didn't complete, or state loss/restoration from a backup that predates that resource's creation.
**Investigation:** `terraform state list | grep <resource>` confirms it's genuinely absent from state; check the cloud console/API to confirm the resource's actual current configuration before adopting it.
**Fix:** use an `import` block (or `terraform import` for older workflows) to bring it under management — never let `apply` proceed and hope the cloud API rejects the duplicate gracefully; some resource types will happily create a second, conflicting object.
**Prevention:** prefer `removed` blocks over ad hoc `state rm` for planned decommissions, so removal-from-state and removal-from-config happen together, reviewably, in one commit.

### Resource exists in state but not in the cloud
**Symptom:** `terraform plan` shows a resource being *created* even though your configuration hasn't changed, or refresh silently drops it — the resource was deleted outside Terraform (manual deletion, another automation, an expired/reclaimed resource).
**Investigation:** check CloudTrail/audit logs for who/what deleted it and when; confirm this wasn't a legitimate decommission that missed updating Terraform config.
**Fix:** if refresh has already updated state to reflect the deletion, a normal `apply` will recreate it — confirm that's actually wanted before proceeding (a manually-deleted resource might have been an intentional decommission that should instead have its config removed via a `removed` block).
**Prevention:** `prevent_destroy` (see [`terraform-internals.md` §5](terraform-internals.md#lifecycle--prevent_destroy--true)) doesn't help here — it can't stop a deletion that didn't go through Terraform at all. The real prevention is IAM: restrict who/what can delete resources outside the CI pipeline's own execution role.

### Duplicate resource address
**Symptom:** `terraform plan`/`validate` errors with a duplicate resource address, typically after a copy-pasted resource block or a merge conflict resolved incorrectly.
**Fix:** rename one of the conflicting blocks or resolve the `for_each`/`count` collision; if it surfaced from a bad merge, treat it as a code review gap and add `terraform validate` as a required PR check if it isn't already (see [`cicd.md` §1](cicd.md#1-the-pull-request-validation-chain)).

### Failed backend migration
**Symptom:** `terraform init -migrate-state` fails partway, leaving ambiguity about which backend actually holds authoritative state.
**Investigation:** check whether the old backend's state file/object is untouched (migrations typically don't delete the source until the destination write is confirmed — verify this behavior for your specific backend transition) and whether the new backend has a partial/empty write.
**Fix:** restore from the old backend if the new one is incomplete; retry the migration only after confirming the old source state is intact; never manually copy state file contents between backends by hand as a shortcut.
**Prevention:** always back up state (pull a local copy) immediately before any backend migration, and perform migrations during a change window with no concurrent pipeline activity against that state.

## Environment and identity failures

### Wrong workspace / wrong AWS account / wrong AWS region
**Symptom:** a plan shows an unexpectedly large diff (everything looks like it needs creating) or targets resources that don't match the intended environment.
**Deep dive on why this happens structurally:** [`terraform-architecture.md` §10](terraform-architecture.md#10-why-cli-workspaces-are-not-sufficient-for-production-isolation) — CLI workspaces and shared provider configuration are exactly what makes this mistake possible.
**Investigation:** `terraform workspace show`; check the assumed role ARN/account ID actually in use (`aws sts get-caller-identity` under the same credentials Terraform is using); check the backend config's region/key path.
**Fix:** abort immediately if a plan looks wrong before typing "yes" — this is precisely why plans should always be reviewed, never blindly approved.
**Prevention:** separate root modules/backends per environment (not shared workspaces) with distinct, narrowly-scoped credentials per environment so the *credential itself* structurally cannot reach the wrong account.

### Expired credentials / access denied
**Symptom:** provider RPC calls fail with 401/403-class errors mid-plan or mid-apply.
**Investigation:** distinguish **expired** (session token TTL exceeded — common with long-running plans against short-lived assumed-role sessions) from **denied** (the role genuinely lacks a permission it needs, often surfacing only when a plan touches a resource type/action it hasn't needed before).
**Fix (expired):** re-authenticate/re-assume-role; for long-running applies, ensure session duration is provisioned generously enough for the expected apply time, or split into smaller applies.
**Fix (denied):** identify the exact missing action/resource from the error, add it to the role's policy following least privilege (the specific action/resource, not a wildcard), re-run.
**Prevention:** for CI, OIDC-issued short-lived credentials should be scoped with a session duration matched to realistic pipeline run times; alert on repeated access-denied patterns as a signal the role's policy is drifting out of sync with what the configuration actually needs.

## Language and logic failures

### Dependency cycles
**Deep dive:** [`terraform-internals.md` §2](terraform-internals.md#2-dependency-graph-construction), [`module-design.md` §3](module-design.md#3-module-composition-and-dependency-design), [Diagram 4](../diagrams/04-dependency-graph.md).
**Fast fix:** a genuine cycle is a plan-time error with no flag to bypass; extract the shared concern into a common ancestor layer, or merge the two overly-coupled resources/modules.

### Invalid `for_each` (depends on unknown values)
**Deep dive:** [`terraform-internals.md` §6](terraform-internals.md#6-unknown-values-and-plan-construction).
**Fast fix:** key the `for_each` off something known at plan time (a variable, a literal list, a data source that doesn't depend on a same-apply resource) rather than a computed attribute of a resource being created in the same apply.

### `count` index shifting
**Deep dive:** [`terraform-internals.md` §4](terraform-internals.md#4-count-vs-for_each--and-the-index-shifting-failure-mode).
**Fast fix:** this is a design flaw, not a one-time bug — migrate the collection to `for_each` keyed by a stable identifier, using `moved` blocks or `terraform state mv` to avoid recreating every resource during the migration itself (see [Lab 7](../labs/lab-07-refactoring-state/)).

## Operational and scale failures

### Manual infrastructure changes / drift
**Deep dive:** [`state-management.md` §11](state-management.md#11-manual-infrastructure-changes-and-drift), [Diagram 14](../diagrams/14-drift-detection.md), [Lab 14](../labs/lab-14-drift-and-recovery/).

### Partial apply / interrupted apply
**Deep dive:** [`terraform-internals.md` §12](terraform-internals.md#12-interrupted-and-partial-applies).
**Fast fix:** never blind-retry; run `plan` first, compare `state list` against what the original apply intended, cross-check the cloud console for anything the plan intended to create that may already partially exist.

### API throttling
**Symptom:** apply slows dramatically or fails with rate-limit errors on large applies (many resources of the same type created/updated in one run).
**Investigation:** check provider/API-side error messages for explicit throttle signals; check whether `-parallelism` is set unusually high for the target account's actual API rate limits.
**Fix:** reduce `-parallelism` (default 10) for accounts with lower API quotas; some providers implement their own backoff/retry for throttling — confirm current behavior rather than assuming Terraform Core retries automatically, since retry behavior is provider-implemented, not universal across all resource types.
**Prevention:** for very large applies, consider whether the resource count itself indicates a state-splitting need (see below) rather than only tuning parallelism.

### Long-running plans / large state files
**Deep dive:** [`state-management.md` §12](state-management.md#12-state-splitting-for-blast-radius-reduction-the-5000-resource-problem), [`docs/`](.) performance guidance in interview questions category 12.
**Fast fix:** this is fundamentally an architecture problem, not a flag to tune — redesign state boundaries along ownership/change-frequency lines; in the interim, `-target` can narrow a single plan's scope for an urgent fix, but should never become the routine way of operating (it bypasses full-graph consistency checking and accumulates hidden drift risk if used repeatedly instead of fixing the underlying state size).

### CI/CD race condition
**Deep dive:** [`cicd.md` §6](cicd.md#6-concurrency-controls).
**Fast fix:** add a CI-level concurrency group per environment/state so contention is resolved before pipelines even attempt the backend lock.

### Sensitive data exposure
**Deep dive:** [`security.md` §3](security.md#3-a-sensitive-value-exposed-in-a-plan--ci-logs--investigation-and-remediation).

### Module upgrade failure
**Deep dive:** [`module-design.md` §9](module-design.md#9-upgrade-and-deprecation-strategies).
**Fast fix:** test the target version's plan output in non-prod first; if it fails there, do not attempt it directly against production regardless of time pressure — roll back the version pin and re-plan the upgrade path with the vendor/module author's migration guide.

### Import failure
**Symptom:** an `import` block or `terraform import` fails, or succeeds but produces a plan showing unexpected changes immediately after import.
**Investigation:** confirm the resource ID format matches exactly what the provider expects (this varies by resource type and is a common source of import failures); after a successful import, always run `plan` immediately — a non-empty plan means your *configuration* doesn't yet match the resource's actual attributes (expected right after import unless you used `-generate-config-out`) and needs to be hand-aligned before this is a clean, fully-adopted resource.
**Fix:** use `terraform plan -generate-config-out=generated.tf` (Terraform >= 1.5) where supported, to have Terraform draft the matching configuration for you, then review and refine it — far less error-prone than hand-writing config to match an imported resource's attributes from scratch.

### Resource deletion protection (the `prevent_destroy` decommission scenario)
**Deep dive:** [`terraform-internals.md` §5](terraform-internals.md#lifecycle--prevent_destroy--true).
**Fast fix:** decommissioning a `prevent_destroy`-protected resource requires a deliberate, reviewed two-step change — remove/flip the lifecycle guard in one reviewed commit, confirm via `plan` that only the intended resource is now slated for destruction, then apply. Never work around it via `state rm` plus manual cloud deletion; that desyncs state from reality and leaves no clean record of the decommission.

## Common weak answer vs. senior answer (cross-cutting)

| Pattern across many scenarios above | Weak answer | Senior answer |
|---|---|---|
| Any unexpected plan diff | "Just apply it, Terraform knows what it's doing" | Always read *why* before approving — the plan output explaining forced-replacement reasons, or an unexpectedly large diff, is the primary signal something is wrong before it becomes an incident |
| Any failure mid-pipeline | "Re-run the pipeline" | Diagnose root cause category first (transient/config/partial-apply/drift) — blind retries are how partial applies turn into bigger incidents |
| Any state anomaly | "Edit the state file directly" | Manual JSON editing bypasses schema validation and dependency metadata; use the dedicated `state`/`import`/`moved`/`removed` subcommands instead |

## Related material
- Interview questions: [`interview-questions/10-troubleshooting.md`](../interview-questions/10-troubleshooting.md)
- Hands-on: [Lab 3](../labs/lab-03-state-locking/), [Lab 6](../labs/lab-06-import-existing-infrastructure/), [Lab 7](../labs/lab-07-refactoring-state/), [Lab 14](../labs/lab-14-drift-and-recovery/)
