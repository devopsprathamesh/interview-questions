# State Management

State is where Terraform interview signal separates mid-level from senior candidates. Anyone can run `terraform apply`. Few engineers have actually recovered a corrupted state file at 2 a.m., split a 5,000-resource monolith, or explained precisely what a stale lock means for the team currently blocked behind it. This document is reference material for [`interview-questions/02-state-management.md`](../interview-questions/02-state-management.md) and is exercised in [Lab 2](../labs/lab-02-remote-state/), [Lab 3](../labs/lab-03-state-locking/), [Lab 6](../labs/lab-06-import-existing-infrastructure/), [Lab 7](../labs/lab-07-refactoring-state/), and [Lab 14](../labs/lab-14-drift-and-recovery/).

## 1. What state actually is

State is a JSON document (schema versioned) that maps **resource addresses** in your configuration to **real-world object attributes** as Terraform last observed them, plus metadata: `lineage`, `serial`, Terraform version, provider versions/schemas used, and the dependency information needed to build the graph without re-parsing config from scratch every time.

State exists because most cloud APIs have no reliable way to answer "which of these thousands of objects does *this specific Terraform configuration* own, and what did it last set attribute X to?" State is Terraform's own source of truth for ownership and last-known-good configuration — **the cloud is the source of truth for current reality; state is the source of truth for intent and ownership.** Confusing these two is the root cause of most state incidents.

## 2. Local vs. remote state

**Local state** (`terraform.tfstate` in the working directory) is fine for solo experimentation and is exactly what [Lab 1](../labs/lab-01-core-workflow/) uses to keep the first lab dependency-free. It fails immediately in any team or CI context: no locking, no shared visibility, trivially lost (laptop dies, directory not backed up), and typically ends up accidentally committed to git (leaking every attribute, including sensitive ones, into version control history).

**Remote state** (S3, Terraform Cloud/Enterprise, Azure Storage, GCS, etc.) provides: a durable, shared, versioned store; often built-in or backend-native locking; and centralized access control. [Lab 2](../labs/lab-02-remote-state/) builds an S3 + native S3 locking backend from scratch, with the deliberate constraint that the **bootstrap** configuration (the S3 bucket and lock table/lock-enabled bucket itself) cannot use the backend it's creating — a chicken-and-egg problem every real organization hits once.

## 3. State locking

**Purpose:** prevent two concurrent operations (two engineers, or an engineer and a CI pipeline, or two CI pipelines) from writing to the same state simultaneously, which would silently corrupt or lose data (last writer wins with no merge).

**Mechanism (S3 backend, modern Terraform):** Terraform's S3 backend now supports native locking using S3 conditional writes (`If-None-Match`) without a separate DynamoDB table, for Terraform/provider versions that support it; the long-standing pattern (and still valid, still widely deployed) uses a **DynamoDB table** with a `LockID` primary key, where Terraform writes a lock item before any state-modifying operation and deletes it on completion. **Always verify which locking mechanism your Terraform and backend versions actually support before asserting behavior in an interview** — this is an area that has changed and you should check the current AWS provider/backend documentation.

**What happens on contention:** a second `plan`/`apply` attempting to acquire the lock while it's held fails fast with a lock error identifying: who holds it (identity/operation), when they acquired it, and the lock ID — by design, so a human can make an informed decision rather than the second process silently queuing or corrupting state.

**Stale locks:** if a process dies without releasing the lock (killed CI runner, SIGKILL, network partition), the lock item/object remains indefinitely — Terraform has no heartbeat/TTL by default. This is why "state lock timeout" and "stale lock" are two of the most common real incidents (see [`interview-questions/10-troubleshooting.md`](../interview-questions/10-troubleshooting.md)).

**Recovery procedure:**
1. Confirm no process is actually still running (check CI job status, ask the team, check process/host if local) — never force-unlock speculatively.
2. Inspect the lock metadata (`Who`, `Created`, `Operation` fields in the error message, or the DynamoDB item / S3 object directly) to identify the stale entry.
3. Run `terraform force-unlock <LOCK_ID>` only after confirmation.
4. If forced unlocks are recurring, the real fix is CI concurrency controls (see [`cicd.md`](cicd.md)) — a single mutex/queue per state so two runs can never even attempt concurrent access — not a habit of forcing locks.

**Risk of forced unlock:** if the original process is *not* actually dead but just slow (e.g., a large apply, network lag), forcing the unlock and starting a second concurrent operation reintroduces the exact corruption risk locking exists to prevent. Treat `force-unlock` as a break-glass action, not routine cleanup.

[Lab 3](../labs/lab-03-state-locking/) simulates this end to end: two operations racing for a real lock, a deliberately induced stale lock, and safe recovery.

## 4. State lineage and serial

- **Lineage**: a UUID assigned when a state file is first created. It's the "family identity" of a state history.
- **Serial**: an integer incremented on every write to state.

**Why they matter:** backends use lineage+serial to detect when a write would be based on stale data — e.g., if you have a locally cached plan file generated against serial 42, but the remote state is now at serial 45 (someone else applied in between), Terraform refuses to apply the stale plan rather than silently reapplying it against outdated assumptions. This is a core safety mechanism for the "saved plan file, review, then apply later" CI/CD pattern — see [`cicd.md`](cicd.md) and [Lab 12](../labs/lab-12-cicd-pipeline/). A **lineage mismatch** (as opposed to a stale serial) means you're looking at a state file from a genuinely different history — e.g., someone replaced the backend's state object with a state file from a different environment or an old backup — and must be resolved by human judgment, not automation.

## 5. State backups

Most backends and the local backend keep a `.tfstate.backup` of the previous state before each write. This is a **single-generation** safety net, not a substitute for real backup/versioning. Production remote-state buckets must have **object versioning enabled** (S3 versioning, GCS object versioning, etc.) so you can restore any prior generation, not just the immediately previous one — see [Lab 2](../labs/lab-02-remote-state/).

## 6. State encryption and access control

State frequently contains **sensitive data in plaintext** inside the JSON — database passwords, private keys, certificates — even for attributes you've marked `sensitive = true` in your configuration (that marking only affects CLI/log output, not what's stored in state). Controls:
- **Encryption at rest**: SSE-KMS on the state bucket (not just default SSE-S3) so you get audit-loggable key usage and can restrict who can decrypt, not just who can read the object.
- **Encryption in transit**: enforced via bucket policy (deny non-TLS requests).
- **Access control**: least-privilege IAM — most engineers and CI roles need `GetObject`/`PutObject` on their environment's state path only, not the whole bucket; a compromised dev-environment credential should not be able to read production state.
- **Native state encryption** (Terraform 1.10+ `encryption` block, if available in your version): encrypts the state content itself at the Terraform Core level, independent of backend-level encryption — verify current availability/support for your backend before relying on it.

See [`security.md`](security.md) for the full treatment of secrets-in-state, including why "just mark it sensitive" is an incomplete answer.

## 7. State corruption, loss, and recovery

**Corruption causes:** manual hand-editing of the JSON without `terraform state` subcommands, a crashed apply combined with a non-atomic backend write, concurrent writes from a locking failure, or restoring an incompatible/malformed backup.

**Recovery approach (also see [Lab 14](../labs/lab-14-drift-and-recovery/) for a full runbook):**
1. **Stop.** Do not run `apply` against corrupted or suspect state.
2. Pull the current state (`terraform state pull > broken.tfstate.json`) and preserve it for forensics before touching anything.
3. Check backend version history (S3 object versions, Terraform Cloud state history) for the last known-good serial.
4. Restore the last good version via the backend's native mechanism (S3: restore/copy the prior version; Terraform Cloud: state version rollback in the UI/API) rather than local hand-repair where possible.
5. Run `terraform plan` against the restored state and **carefully read every proposed change** — a restored-but-slightly-stale state will show a plan reflecting real changes made since that version, which is expected and needs to be reconciled deliberately (via `-refresh-only` apply to adopt reality, or normal apply if the plan matches actual pending work).
6. If no good backup exists at all (true state loss): rebuild via `import` blocks / `terraform import`, prioritizing resources other resources depend on (networking before compute before application layer), validating each import with `terraform state show` and `plan` before moving to the next.

## 8. State migration and splitting/merging

**Migration** (e.g., local → S3, or changing backend config) is done via `terraform init -migrate-state`, which Terraform performs interactively with a confirmation prompt — always run this against a fresh backup and ideally in a maintenance window for anything production-critical, since a migration issue mid-flight is a state-loss risk.

**Splitting a monolithic state** (the "5,000 resources, plan takes 20 minutes" scenario): the tool is `terraform state mv` (or, in newer Terraform, `moved` blocks combined with restructured root modules) to relocate a subset of resources into a new root module/workspace/backend path, without destroying and recreating them. The **architectural** fix is deciding new state boundaries along real ownership/change-frequency lines (see §10 below) — moving resources is mechanical once the boundaries are decided.

**Merging** state (rare, but happens during team/repo consolidation) is the reverse — `state mv` resources from a source state into a target state's namespace, one resource/module at a time, verifying with `plan` after each batch that nothing shows as needing replacement.

[Lab 7](../labs/lab-07-refactoring-state/) proves both directions produce zero-diff plans when done correctly.

## 9. `terraform state` subcommands — what each is actually for

- `terraform state list` — enumerate every resource address currently tracked; the first command to run when investigating "what does Terraform think it owns."
- `terraform state show <address>` — dump the full recorded attributes for one resource; compare against the cloud console/API when investigating drift.
- `terraform state mv <source> <destination>` — relocate a resource's *state entry* (identity), without touching real infrastructure; used for refactors, renames, module restructuring.
- `terraform state rm <address>` — remove a resource from state **without destroying it in the cloud**; used when you want Terraform to forget about something (handing ownership elsewhere, or deliberately un-managing it) — the immediate danger is that if the configuration for that resource still exists, the *next* plan will try to create a duplicate.
- `terraform import <address> <id>` (legacy imperative form) / **`import` blocks** (declarative, reviewable in a plan, Terraform >= 1.5) — bring an existing, unmanaged cloud resource under Terraform management by writing a state entry for it. Import blocks are strongly preferred in modern workflows because the import itself shows up in `terraform plan` output for review before it's applied, and can generate starting configuration (`terraform plan -generate-config-out=`) — removing the old "import blind then hand-write config to match" guesswork.
- **`moved` blocks** (Terraform >= 1.1) — declaratively record "this resource address used to be X, it is now Y" *in configuration*, so `terraform state mv` doesn't need to be run out-of-band by every consumer of a module; critical for module authors doing a refactor that changes internal resource addressing without forcing every consumer to manually run state surgery.
- **`removed` blocks** (Terraform >= 1.7) — declaratively remove a resource from state (optionally also destroying it) as a reviewable, version-controlled configuration change, replacing ad hoc `terraform state rm` runbook steps for planned decommissions.

**Manual state editing risk:** hand-editing the JSON directly is almost never the right answer. It bypasses schema validation, drops resource dependency metadata Terraform relies on for graph construction, and is trivially able to produce a file that *parses* as valid JSON but is semantically broken (wrong provider schema version, missing required computed fields). Use the dedicated subcommands; they exist precisely so you never need to.

## 10. Cross-state dependencies

**`terraform_remote_state` data source**: reads another state file's outputs directly. It works, but tightly couples consuming configurations to the *producing state's internal output shape* and — depending on backend — may expose more of the producer's state data than intended to anyone with data-source read access.

**Preferred alternatives at scale:**
- **A dedicated parameter/registry layer**: publish cross-team values (VPC ID, subnet IDs, shared KMS key ARN) to SSM Parameter Store, AWS Systems Manager, or a similar service, and consume via `data` sources scoped to that service — decouples consumers from the producer's Terraform internals entirely and lets the producer change its own state layout freely.
- **Platform/foundation modules with narrow, versioned output contracts**: treat the foundation layer's outputs as a stable API, documented and versioned, regardless of *how* consumers fetch them.

**Why this matters for blast radius:** `terraform_remote_state` creates an implicit dependency edge between two independently-deployed Terraform configurations that Terraform's own graph can't see across state boundaries — if the producer's state is unreachable (permissions issue, backend outage) every consumer's plan fails too, even though nothing about the consumer's own infrastructure needs to change. This is a primary reason large organizations move to the parameter-store pattern for stable, foundation-layer values while reserving `terraform_remote_state` for tightly coupled configurations within the same team.

## 11. Manual infrastructure changes and drift

**Drift** = the gap between state (Terraform's last-known configuration) and cloud reality (what actually exists now), caused by manual console/CLI changes, other automation, or a provider side effect Terraform doesn't track.

**Decision framework when drift is detected** (`terraform plan` shows unexpected changes with no corresponding config edit):
1. **Determine what changed and who/what changed it** — CloudTrail/audit logs are authoritative here, not guesses.
2. **Was it intentional and should it persist?** → Update the *configuration* to match (not state directly), so the next plan is clean and the change is now version-controlled and reviewable.
3. **Was it intentional but should be reverted?** → Let Terraform's next `apply` revert it (this is the normal, expected behavior — drift correction is one of Terraform's core value props), after confirming the revert won't cause an outage (e.g., someone manually bumped an RDS instance class during an incident — reverting it during business hours would be bad even though it's "correct" per config).
4. **Was it a change Terraform should stop tracking (a field now owned by another system)?** → Add `ignore_changes` for that specific attribute, with a comment explaining why, not `ignore_changes = all`.
5. **Was it made outside a resource Terraform even knows about?** → Use `import` blocks to adopt it (§9), don't hand-edit state.

This exact framework is the correct interview answer to "an engineer manually changed AWS infrastructure and Terraform detects drift — revert, import, ignore, or adopt?" — see [`interview-questions/10-troubleshooting.md`](../interview-questions/10-troubleshooting.md) and [Lab 14](../labs/lab-14-drift-and-recovery/).

## 12. State splitting for blast-radius reduction (the 5,000-resource problem)

Symptoms: multi-minute (or longer) plans, a single lock serializing all changes across unrelated systems, one team's typo able to threaten another team's production resources, and a state file large enough that even `state list`/`show` become slow.

**Redesign approach:**
1. **Identify natural boundaries** — by change frequency (networking changes rarely, application config changes daily), by ownership (platform team vs. application teams), by blast-radius tolerance (a shared VPC vs. a single service's resources), and by lifecycle (foundational/long-lived vs. ephemeral/environment-specific).
2. **Adopt a layered architecture** (see [`terraform-architecture.md`](terraform-architecture.md#enterprise-architecture) and the capstone in [Lab 15](../labs/lab-15-enterprise-capstone/)): bootstrap → foundation (accounts, IAM, core networking) → platform (EKS, shared services) → application, each with its **own state and its own deployment lifecycle**, connected via the parameter-store pattern from §10, not shared state.
3. **Migrate incrementally** using `state mv`/`moved` blocks (§8/§9), validating zero-diff plans at every step — never a big-bang cutover on production state.
4. **Result:** smaller, faster, independently-lockable states; a broken plan in the application layer can no longer even theoretically touch foundation-layer resources; team ownership maps cleanly to state ownership.

## 13. Protecting sensitive state — summary

Full details in [`security.md`](security.md). Minimum bar for any production state backend:
- Encrypted at rest (SSE-KMS) and in transit (TLS-only bucket policy)
- Versioned, with lifecycle rules balancing retention against cost
- Access restricted by least-privilege IAM per environment/team, never a single broadly-shared credential
- No state file ever committed to git (`.gitignore` enforcement, plus pre-commit/CI scanning as a backstop)
- Audit logging enabled (CloudTrail data events on the state bucket) so "who read/wrote state and when" is answerable

## Common weak answer vs. senior answer

| Scenario | Weak answer | Senior answer |
|---|---|---|
| Lock timeout in CI | "Just run `force-unlock`" | Confirm no live process holds it first via lock metadata/CI job status, then force-unlock; fix root cause with concurrency controls |
| Drift detected | "Re-apply to fix it" | Determine intent behind the change first; choose revert, adopt-into-config, ignore, or import based on that, not reflexively re-applying |
| Large state file | "Split it into smaller files" | Redesign state *boundaries* around ownership/blast-radius/change-frequency, migrate with `state mv`/`moved` blocks, verify zero-diff at each step |
| Sensitive value in state | "Mark the variable sensitive" | `sensitive = true` only hides it from CLI/plan output; the value is still in state plaintext — encryption, access control, and rotation are the actual controls |
| Corrupted state | "Delete it and reimport everything" | Recover from the last-known-good backend version first; full reimport is the last resort when no backup exists |

## Related material
- Interview questions: [`interview-questions/02-state-management.md`](../interview-questions/02-state-management.md)
- Hands-on: [Lab 2](../labs/lab-02-remote-state/), [Lab 3](../labs/lab-03-state-locking/), [Lab 6](../labs/lab-06-import-existing-infrastructure/), [Lab 7](../labs/lab-07-refactoring-state/), [Lab 14](../labs/lab-14-drift-and-recovery/)
- Diagrams: [`diagrams/06-remote-state-architecture.md`](../diagrams/06-remote-state-architecture.md), [`diagrams/07-state-locking.md`](../diagrams/07-state-locking.md), [`diagrams/14-drift-detection.md`](../diagrams/14-drift-detection.md)
