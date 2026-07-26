# Category 2: State Management and Locking

Questions 11–22 of 120. Category weight: 12 questions. Deep-dive reference: [`docs/state-management.md`](../docs/state-management.md).

---

## Question 11: Two pipelines, one state

### Scenario
A platform team's nightly maintenance pipeline and an application team's feature-deployment pipeline both target the same production state within the same minute.

### Interview Question
Explain exactly what happens, the failure modes involved, and the recovery procedure if it goes wrong.

### Strong Senior-Level Answer
**Initial assessment:** this is state locking doing its job, not a failure — the question is really testing whether the candidate understands the mechanics well enough to explain both the happy path and the edge cases.

**Technical reasoning:** whichever pipeline's `plan`/`apply` acquires the backend lock first (S3 conditional write or DynamoDB lock item, depending on backend) proceeds; the second's lock-acquisition attempt is rejected immediately with an error identifying who holds the lock, when, and what operation — it does not queue, retry silently, or corrupt anything.

**Investigation process:** if the second pipeline's job is configured to simply fail on lock rejection (the default), an on-call engineer sees a clear, actionable error, not ambiguous state corruption.

**Recommended solution:** the second pipeline should be designed to either fail fast and re-trigger later (simplest), or — better — sit behind a CI-level concurrency group so it never even attempts to acquire the Terraform lock while the first is running, converting a lock-rejection error into a clean "queued" status.

**Risk controls:** the genuine failure mode to guard against isn't lock contention itself (which fails safely) — it's a process that dies *while holding the lock* (see [Question 12](#question-12-the-lock-that-would-not-die)), which requires human judgment to resolve.

**Validation steps:** after the first pipeline completes and releases the lock, the second's retry (or queued run) should re-plan against the now-current state, not reuse a plan computed before the first pipeline's changes landed (see [Question 20 in category 1](01-terraform-core.md#question-10-the-workflow-gap-between-plan--out-and-a-later-apply) for the stale-plan mechanics).

**Rollback or recovery strategy:** no rollback needed in the normal-contention case — nothing was corrupted; the rejected operation simply never started.

**Long-term prevention:** organize maintenance windows and deployment pipelines with awareness of each other, and implement CI concurrency groups per state/environment as the primary defense, treating the backend lock as a correctness backstop rather than the sole coordination mechanism.

### Step-by-Step Implementation
```yaml
# GitHub Actions - concurrency group ensures serialized access per environment
concurrency:
  group: terraform-production
  cancel-in-progress: false
```
```bash
# What the second pipeline sees if it races the lock directly:
# Error: Error acquiring the state lock
#   Lock Info:
#     ID:        b5f2b1e4-...
#     Path:      prod/terraform.tfstate
#     Operation: OperationTypeApply
#     Who:       ci-runner-42@github-actions
#     Created:   2026-07-24 02:14:03 UTC
```

### Under-the-Hood Explanation
The lock is acquired via a conditional write (S3 native locking) or a conditional `PutItem` (DynamoDB, `attribute_not_exists(LockID)`) before any state read/write for the operation begins, and released (deleted) as part of a `defer`-style cleanup once the operation completes or fails cleanly. A rejected acquisition is a normal, expected API-level conditional-write failure — it carries no risk of partial or corrupted writes because the losing process never proceeds past the lock-acquisition step.

### Common Weak Answer
"They'll conflict and probably corrupt the state, so you should never run two pipelines close together."

### Why the Weak Answer Fails
It's factually wrong about the failure mode — a properly-locked backend cannot be corrupted this way; the second operation is rejected outright, not partially applied. This answer signals the candidate hasn't actually operated a locked remote backend under real concurrent load.

### Follow-Up Questions
1. What would actually cause state corruption in this scenario, if anything?
2. How would you design the pipeline so the "lost the race" job doesn't just fail loudly and need a manual re-trigger?
3. Does a stale plan file interact with lock contention in any way — could a stale plan still be blindly applied if lock timing lined up a certain way?

### Key Interview Signals
Confirms the candidate can precisely describe lock semantics rather than hand-waving "state gets corrupted," and understands that queuing/CI-level coordination is a UX improvement layered on top of, not a substitute for, the lock's correctness guarantee.

### Hands-On Connection
[Lab 3 — Concurrent Execution and Locking](../labs/lab-03-state-locking/).

---

## Question 12: The lock that would not die

### Scenario
A CI runner applying production changes is forcibly terminated mid-apply by the CI platform's own resource-reclamation policy. The next pipeline run, and every one after it for the next hour, fails immediately with a lock-acquisition error. No one is aware of any apply currently running.

### Interview Question
Walk through your recovery process, including how you'd confirm it's actually safe to force-unlock.

### Strong Senior-Level Answer
**Initial assessment:** this is a stale lock — a process died without releasing it. The immediate priority is confirming it's genuinely stale before touching anything, since forcing an unlock on a still-running process reintroduces the exact corruption risk locking exists to prevent.

**Technical reasoning:** the lock error message includes `Who`, `Operation`, and `Created` fields identifying the process and timestamp — this is the primary evidence, not a guess.

**Investigation process:** check the CI platform's job history for the run identified in the lock's `Who`/session metadata — confirm it shows as terminated/failed, not still running or queued for retry. Cross-check the timestamp against how long a normal apply for this configuration typically takes; a lock held for six hours when applies normally finish in ten minutes is strong corroborating evidence of staleness, independent of the CI job status.

**Recommended solution:** once confirmed dead, run `terraform force-unlock <LOCK_ID>` using the exact lock ID from the error message.

**Risk controls:** never force-unlock based on elapsed time alone without checking the actual job status — a genuinely slow but still-running apply (e.g., a large EKS cluster provisioning) could still legitimately hold the lock for an hour or more.

**Validation steps:** immediately after unlocking, run `terraform plan` (not apply) first — since the interrupted process may have been mid-apply, treat this exactly like the partial-apply investigation (state list vs. cloud reality vs. original intended changes) before proceeding to any real apply.

**Rollback or recovery strategy:** if the plan reveals the interrupted apply left something inconsistent, resolve that first (see [Question 7 in category 1](01-terraform-core.md#question-7-the-apply-that-died-halfway-through-a-data-migration)) before treating the lock issue as fully resolved.

**Long-term prevention:** configure CI apply jobs with graceful-termination handling wherever the platform supports it, so a resource-reclamation event sends a termination signal Terraform can catch and clean up after (releasing the lock) rather than a hard kill; also consider a lock-monitoring alert that pages if a lock is held longer than the 95th-percentile normal apply duration for that state, rather than waiting for the next pipeline run to fail and someone noticing.

### Step-by-Step Implementation
```bash
# 1. Read the lock error carefully
terraform plan
# Error: Error acquiring the state lock
#   Lock Info:
#     ID: 8f3a2c10-...
#     Who: ci-runner-17@github-actions
#     Created: 2026-07-24 01:02:11 UTC   <- 58 minutes ago, apply normally takes ~8 min

# 2. Confirm via CI platform: was ci-runner-17's job terminated? Check job logs/status.
gh run list --workflow=terraform-apply.yml --limit 5

# 3. Once confirmed dead:
terraform force-unlock 8f3a2c10-...

# 4. Plan first, never apply blind
terraform plan -out=recovery.tfplan
terraform show recovery.tfplan   # review thoroughly
```

### Under-the-Hood Explanation
The lock item/object stores metadata (who, when, what operation) at acquisition time but has no TTL or heartbeat by default — Terraform's locking model assumes clean release via normal process completion, not automatic expiry. `force-unlock` simply deletes the lock item/object directly, bypassing the normal release path; it performs no verification that the original holder is actually gone, which is exactly why that verification is the human's responsibility before running it.

### Common Weak Answer
"If it's been more than a few minutes, it's probably stale — just force-unlock it."

### Why the Weak Answer Fails
Elapsed time alone is not confirmation. Some applies (large clusters, many resources) legitimately take a long time; force-unlocking a genuinely active apply creates a real concurrent-write race — the exact failure mode locking exists to prevent, now triggered by the "fix."

### Follow-Up Questions
1. How would you build automated detection for stale locks that doesn't risk false positives on legitimately long-running applies?
2. What's different about diagnosing a stale lock on a local-development lock (if using a backend without native cloud locking) versus a team's shared remote backend?
3. If force-unlocking turned out to be wrong (the original process was still running), what would you expect to observe, and how would you recover from that?

### Key Interview Signals
Distinguishes candidates who treat force-unlock as a routine convenience command from those who treat it as a break-glass action requiring actual verification first.

### Hands-On Connection
[Lab 3 — Concurrent Execution and Locking](../labs/lab-03-state-locking/).

---

## Question 13: The state file that stopped making sense

### Scenario
After a backend outage during an apply, `terraform plan` now errors with a JSON parsing failure when reading state, and `terraform state list` fails the same way.

### Interview Question
Walk through your state corruption recovery process end to end.

### Strong Senior-Level Answer
**Initial assessment:** suspected state corruption from a non-atomic write during a backend outage. The absolute first rule: do not run `apply` or attempt to hand-edit the file to "fix" the JSON — preserve evidence and recover from a known-good source first.

**Technical reasoning:** most remote backends (S3 with versioning, Terraform Cloud) retain prior versions of the state object independent of the corrupted latest write, which is the intended recovery path — not manual repair of malformed JSON.

**Investigation process:** pull the current (corrupted) state for forensics (`terraform state pull > corrupted.tfstate.json`, or fetch the object directly from the backend) before touching anything else; then list the backend's version history for this state object (S3: `aws s3api list-object-versions`; Terraform Cloud: state version history in the UI/API) to find the last version that parses as valid JSON and matches a plausible pre-outage timestamp.

**Recommended solution:** restore that last-known-good version via the backend's native mechanism (S3: copy the specific version back as the current object, or use `terraform state push` with a validated local copy as a last resort if the backend lacks native version restore — used cautiously since `state push` bypasses lineage/serial checks). Then run `terraform plan` against the restored state and read every proposed change carefully — the restored version is likely slightly stale (missing whatever the outage-interrupted apply was doing), so a non-empty plan reflecting real pending work is expected and must be reconciled deliberately.

**Risk controls:** do this from a working directory with the state lock held for the duration of the recovery, so no other pipeline can interleave an apply against the state mid-recovery.

**Validation steps:** after restoring, spot check `terraform state list` and `state show` on a sample of resources against the actual cloud console to confirm the restored state accurately reflects a real, coherent point in time, not a half-written version from the same outage.

**Rollback or recovery strategy:** if no valid prior version exists at all (extremely rare with versioning enabled, but possible if versioning was recently enabled or misconfigured), the fallback is full reconstruction via `import` blocks, starting with foundational resources (networking, IAM) and working outward, validating each import with `plan` before continuing.

**Long-term prevention:** confirm object versioning is enabled and has adequate retention on every production state bucket before this ever happens again — this incident is itself the strongest argument for the "Lab 2 must include versioning" requirement, and should prompt an audit of every other state bucket in the organization for the same gap.

### Step-by-Step Implementation
```bash
# 1. Preserve evidence, don't touch backend yet
terraform state pull > /tmp/corrupted-$(date +%s).tfstate.json 2>/dev/null || \
  aws s3 cp s3://tf-state-bucket/prod/terraform.tfstate /tmp/corrupted.tfstate.json

# 2. Find last-good version
aws s3api list-object-versions --bucket tf-state-bucket --prefix prod/terraform.tfstate

# 3. Restore the last version that parses cleanly
aws s3api get-object --bucket tf-state-bucket --key prod/terraform.tfstate \
  --version-id <last-good-version-id> /tmp/restore-candidate.json
python3 -m json.tool /tmp/restore-candidate.json > /dev/null && echo "valid JSON"

aws s3api copy-object --bucket tf-state-bucket \
  --copy-source tf-state-bucket/prod/terraform.tfstate?versionId=<last-good-version-id> \
  --key prod/terraform.tfstate

# 4. Plan carefully, never blind-apply
terraform plan -out=recovery.tfplan
```

### Under-the-Hood Explanation
State is written as a full JSON document on each write (not an incremental diff), so a write interrupted mid-flight by a backend outage can leave a truncated or malformed object if the backend's write isn't atomic at the point of interruption — this is exactly why versioned, immutable object storage (each write creates a new complete version rather than mutating in place) is the real safety net, not any property of Terraform's own write logic.

### Common Weak Answer
"Open the state file and manually fix the broken JSON."

### Why the Weak Answer Fails
Manually repairing truncated/malformed JSON risks producing a file that parses successfully but is semantically wrong (missing resource dependency metadata, incorrect provider schema version markers) — appearing to work until a subsequent operation behaves unexpectedly. Restoring a known-good prior version is strictly safer than reconstructing one by hand.

### Follow-Up Questions
1. What would you do differently if versioning had not been enabled on this bucket?
2. How would you determine whether the outage caused permanent data loss (destroyed cloud resources never reflected anywhere) versus just a corrupted state pointer to resources that are actually fine?
3. How do you validate that the restored state's lineage matches what CI/other consumers expect, and what would a lineage mismatch here specifically indicate?

### Key Interview Signals
Confirms the candidate's first instinct is "restore from a known-good version," not "try to fix the broken file by hand," and that they preserve evidence before acting.

### Hands-On Connection
[Lab 14 — Drift, Failure, and Recovery](../labs/lab-14-drift-and-recovery/).

---

## Question 14: The state file that no longer exists

### Scenario
An engineer, intending to delete a stale feature branch's isolated sandbox state object, instead deletes the production state object from the S3 bucket. There is no versioning enabled on this particular bucket (an older bucket predating your current standards).

### Interview Question
How do you recover, and what does "recover" actually mean here given there's no backup?

### Strong Senior-Level Answer
**Initial assessment:** genuine state loss with no backend-native recovery path — the worst case in the state-corruption spectrum. Recovery means rebuilding state from scratch via import, not restoring anything that still exists.

**Technical reasoning:** the cloud infrastructure itself is very likely untouched (deleting a state *object* doesn't touch the resources it described) — this is a Terraform bookkeeping loss, not necessarily an infrastructure loss, which is the most important thing to establish immediately to calibrate the actual severity.

**Investigation process:** confirm this directly — check the AWS console/CLI for the resources this configuration was known to manage; they should all still be running normally, since nothing about deleting an S3 object affects EC2/RDS/etc. Enumerate every resource the configuration is supposed to manage from the `.tf` files themselves (every resource block/instance), building the authoritative "what needs to be re-imported" list from source, not from memory.

**Recommended solution:** rebuild state via `import` blocks (Terraform >= 1.5), prioritizing foundational/networking resources first, then IAM, then compute/data resources, validating each batch with `terraform plan -generate-config-out=` (if starting truly from scratch with no existing `.tf` to match against) or against existing configuration (if the `.tf` files are intact and only state was lost, which is this scenario) before moving to the next batch.

**Risk controls:** do this work with **no other pipeline permitted to apply** against this configuration until the rebuild is complete and verified — an apply against a partially-rebuilt state could create duplicate resources for anything not yet imported.

**Validation steps:** after every resource is imported, `terraform plan` must show **zero** changes — any diff at this point means either the import captured something incorrectly or the existing `.tf` configuration doesn't actually match the real resource's current attributes (itself worth investigating, since it could indicate undetected drift that predates the state loss).

**Rollback or recovery strategy:** not applicable in the traditional sense — there's nothing to roll back to; the entire exercise *is* the recovery.

**Long-term prevention:** this incident is the direct justification for making bucket versioning and deletion protection (S3 MFA delete, or at minimum, deny `s3:DeleteObject` in the bucket policy for anyone but a break-glass role) a mandatory, audited standard on every state bucket without exception — and for auditing every legacy bucket that predates that standard, exactly as flagged in the scenario.

### Step-by-Step Implementation
```hcl
# Enumerate from source, import in dependency order
import {
  to = aws_vpc.main
  id = "vpc-0abc123"
}
import {
  to = aws_subnet.private["us-east-1a"]
  id = "subnet-0def456"
}
# ... continue for every resource, networking -> IAM -> compute -> application ...
```
```bash
terraform plan   # review the import plan carefully before applying
terraform apply  # writes the imported state entries
terraform plan   # must now show zero changes; investigate any diff before proceeding
```
```
# Prevent recurrence immediately
aws s3api put-bucket-versioning --bucket tf-state-bucket-legacy --versioning-configuration Status=Enabled
```

### Under-the-Hood Explanation
State loss doesn't affect the actual cloud resources at all — Terraform state is purely Core's own bookkeeping of what it believes it manages and what it last observed. `import` blocks work by calling the same `ImportResourceState` provider RPC used by the legacy `terraform import` command, populating a state entry for the given resource address/ID pair, which then participates normally in the next plan's diff calculation against your existing configuration.

### Common Weak Answer
"We'd need to destroy and recreate all the infrastructure since Terraform lost track of it."

### Why the Weak Answer Fails
This confuses state loss with infrastructure loss — destroying and recreating real, running production infrastructure because a bookkeeping file was deleted would cause a far larger, entirely self-inflicted outage. The correct response treats the infrastructure as intact and rebuilds only the tracking.

### Follow-Up Questions
1. How would you handle a resource where you can't find a `.tf` configuration for it at all — is it truly Terraform-managed, or orphaned?
2. What if some of the "missing" resources turn out to have actually drifted (manually modified) since state was last accurate — how does that complicate the import?
3. How would you prioritize which resources to import first if there are hundreds, under time pressure?

### Key Interview Signals
Confirms the candidate immediately separates "state is gone" from "infrastructure is gone" and doesn't panic into a destructive "start over" response.

### Hands-On Connection
[Lab 6 — Import Existing Infrastructure](../labs/lab-06-import-existing-infrastructure/) and [Lab 14 — Drift, Failure, and Recovery](../labs/lab-14-drift-and-recovery/).

---

## Question 15: The plan that took twenty minutes

### Scenario
A single root module's state has grown to roughly 5,000 resources over several years of organic growth. `terraform plan` now takes over twenty minutes, a single lock serializes changes across completely unrelated systems (networking, three different applications, and a shared logging pipeline all live in this one state), and a recent typo in one application's configuration briefly threatened to affect the shared logging pipeline's resources in the same plan.

### Interview Question
Redesign this state architecture.

### Strong Senior-Level Answer
**Initial assessment:** the size and plan time are symptoms; the real problem is that state boundaries don't match ownership or blast-radius boundaries — four unrelated concerns share one state, one lock, and one plan graph.

**Technical reasoning:** child modules don't create state boundaries (see [`module-design.md` §1](../docs/module-design.md#1-root-modules-vs-child-modules)) — even if this configuration is already organized into modules internally, it's still one state, one lock, one blast radius, until it's split into genuinely separate root modules.

**Investigation process:** map the 5,000 resources to natural ownership/change-frequency boundaries — networking (rarely changes, foundational, everything else depends on it), and three applications plus a shared logging pipeline (each independently owned, different change cadence, no legitimate reason to share a lock).

**Recommended solution:** adopt a layered architecture (see [`terraform-architecture.md` §7](../docs/terraform-architecture.md#7-layered-deployment-architecture)): split into a foundation state (networking, shared IAM), a platform state (shared logging pipeline), and one state per application. Cross-references (an application needing the VPC ID) move from same-state resource references to the parameter-store pattern (SSM Parameter Store) or, at minimum, `terraform_remote_state` scoped only to the foundation layer's stable, documented outputs — never a shared state.

**Risk controls:** migrate incrementally, one boundary at a time (e.g., extract the logging pipeline first, since it's likely the most self-contained), using `state mv` to relocate each resource's state entry into its new backend/state path without destroying and recreating it, validating a zero-diff plan after each resource before moving to the next.

**Validation steps:** after each extraction, confirm the extracted state's `plan` is now fast (seconds, not minutes) and confirm the *original* (now-smaller) state's plan is also faster and no longer touches the extracted resources at all.

**Rollback or recovery strategy:** if a `state mv` migration step goes wrong mid-way (a resource ends up orphaned in neither state, or duplicated in both), stop immediately, use `state show` on both states to determine the actual current location of the resource's state entry, and manually reconcile before proceeding — this is exactly why doing the migration resource-by-resource (not a bulk move) with verification at each step matters.

**Long-term prevention:** establish and document real state-boundary guidelines (by ownership, blast radius, change frequency) so new infrastructure is placed correctly from the start, rather than accumulating into whichever state file already exists, which is how this 5,000-resource state got here in the first place.

### Step-by-Step Implementation
```bash
# Extract the logging pipeline into its own state, one resource at a time
terraform state mv -state-out=logging.tfstate 'module.logging.aws_cloudwatch_log_group.app' 'module.logging.aws_cloudwatch_log_group.app'
# ... repeat for every logging-pipeline resource ...
terraform plan   # original state: confirm no diff, logging resources gone from its scope
cd ../logging-pipeline-root/
terraform init -migrate-state   # point at new backend path for logging.tfstate
terraform plan   # new state: confirm zero diff
```
```hcl
# Cross-boundary reference: replace terraform_remote_state with SSM parameter lookups
data "aws_ssm_parameter" "vpc_id" {
  name = "/platform/foundation/vpc_id"
}
```

### Under-the-Hood Explanation
Plan time scales with the number of resources requiring a refresh (`ReadResource` RPC calls, even when parallelized) plus graph construction and diff-calculation overhead across the whole resource set — a single state's plan always walks its *entire* graph, even for a change touching one resource, because Terraform must refresh and re-evaluate the full dependency chain to be sure nothing else is affected. Splitting into separate states means each plan's graph — and its refresh cost — is bounded to just that state's resources.

### Common Weak Answer
"Break it into more modules to organize the code better."

### Why the Weak Answer Fails
Reorganizing code into child modules within the same root module/state changes nothing about plan time, lock contention, or blast radius — all three problems are properties of the *state*, not the code layout. The fix requires separate root modules with separate backend configurations.

### Follow-Up Questions
1. How would you sequence which boundary to extract first when there are several candidates, to minimize risk during the migration itself?
2. What's your strategy for teams that need frequent cross-boundary data (e.g., an application needing something from another application's state) once you've eliminated `terraform_remote_state` as the default pattern?
3. How do you prevent this problem from recurring after the split — what governance or convention keeps new resources landing in the right state going forward?

### Key Interview Signals
Distinguishes a candidate who reaches for "more modules" (a code-organization fix to a state-architecture problem) from one who identifies the actual state-boundary redesign and can describe a safe, incremental, verifiable migration path.

### Hands-On Connection
[Lab 7 — Refactoring Without Recreation](../labs/lab-07-refactoring-state/) and the layered structure demonstrated in [Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).

---

## Question 16: The outage that started in someone else's state

### Scenario
Three application teams each consume the foundation team's VPC ID and subnet IDs via `terraform_remote_state` pointed directly at the foundation team's S3 state object. During an unrelated IAM cleanup, access to the foundation team's state bucket is briefly (accidentally) revoked for the application teams' CI roles. All three application teams' pipelines start failing, even though none of them have any actual infrastructure change to make that day.

### Interview Question
What's the architectural flaw here, and how would you redesign the cross-team data flow?

### Strong Senior-Level Answer
**Initial assessment:** `terraform_remote_state` creates a hard, implicit dependency on the *producer's entire state being both intact and directly readable* by every consumer, for every plan, even when nothing about the consumed values has changed — this is a fragility the scenario just demonstrated concretely.

**Technical reasoning:** the data source doesn't fetch just the two or three output values a consumer actually needs — depending on backend/permissions, it requires read access to the whole state object, and any interruption to that access (permissions, backend outage, even the foundation team choosing to restructure their own state internally) breaks every consumer's plan, regardless of whether the consumer's own infrastructure needs to change.

**Investigation process:** confirm exactly which outputs each consuming team actually uses (typically a small, stable set: VPC ID, subnet IDs, a shared KMS key ARN) — this scoping exercise itself often reveals the dependency is much narrower than "read access to the whole state."

**Recommended solution:** replace `terraform_remote_state` for this cross-team boundary with the foundation team publishing its stable outputs to SSM Parameter Store (or a similar service), and application teams consuming via `data "aws_ssm_parameter"` scoped only to the specific parameter paths they need. This decouples consumers from the producer's state entirely — the foundation team can restructure, split, or even change backends for their own state without any consumer noticing, as long as the published parameters stay stable.

**Risk controls:** treat the published parameters as a versioned, documented contract (see the module-interface discipline in [`module-design.md` §2](../docs/module-design.md#2-designing-the-module-interface-inputsoutputs-as-an-api-contract)) — changing a parameter's meaning or removing one is a breaking change requiring the same deprecation discipline as a module's output removal.

**Validation steps:** after migrating, verify application team plans succeed independent of any simulated foundation-team state/access disruption (this is exactly testable — temporarily revoke test access to the foundation state bucket and confirm application plans are now unaffected).

**Rollback or recovery strategy:** the migration itself is additive (parameters published alongside the existing remote-state outputs) until every consumer has cut over, so rollback during migration is simply continuing to use the old data source path for any team not yet migrated — no risk of a hard cutover breaking someone mid-migration.

**Long-term prevention:** establish this parameter-store (or equivalent) pattern as the org's standard for any cross-team-boundary data flow, reserving `terraform_remote_state` for tightly-coupled configurations genuinely owned by the same team.

### Step-by-Step Implementation
```hcl
# Foundation team: publish stable values
resource "aws_ssm_parameter" "vpc_id" {
  name  = "/platform/foundation/vpc_id"
  type  = "String"
  value = aws_vpc.main.id
}

resource "aws_ssm_parameter" "private_subnet_ids" {
  name  = "/platform/foundation/private_subnet_ids"
  type  = "StringList"
  value = join(",", aws_subnet.private[*].id)
}
```
```hcl
# Application team: consume without needing state-bucket access at all
data "aws_ssm_parameter" "vpc_id" {
  name = "/platform/foundation/vpc_id"
}
data "aws_ssm_parameter" "private_subnet_ids" {
  name = "/platform/foundation/private_subnet_ids"
}

locals {
  subnet_ids = split(",", data.aws_ssm_parameter.private_subnet_ids.value)
}
```

### Under-the-Hood Explanation
`terraform_remote_state` works by having the consumer's Terraform process directly read the producer's state file (via the same backend mechanism the producer uses) and expose its `outputs` map as data — this means the consumer's plan/apply literally cannot proceed without live read access to that specific state object at that specific point in time. An SSM parameter (or similar) lookup is a normal provider data source read against a stable, purpose-built API, with access control (IAM) scoped to the specific parameter path rather than an entire state object, and with no coupling whatsoever to how or where the producer stores its own Terraform state.

### Common Weak Answer
"Just fix the IAM permissions so the application teams can read the foundation state again."

### Why the Weak Answer Fails
This fixes today's specific incident but leaves the structural fragility in place — the next accidental permission change, backend outage, or foundation-team state restructuring will cause the identical cascading failure across every consuming team again.

### Follow-Up Questions
1. What are the trade-offs of SSM Parameter Store versus a dedicated service-discovery/config system for this pattern at very large scale (hundreds of consumers)?
2. How would you version a breaking change to one of these published parameters (e.g., splitting `private_subnet_ids` by AZ instead of a flat list)?
3. Are there cases where `terraform_remote_state` is still the right tool despite this fragility — what characterizes them?

### Key Interview Signals
Tests whether the candidate identifies the architectural coupling problem (not just the immediate IAM misconfiguration) and can propose and implement a genuinely decoupled alternative.

### Hands-On Connection
[Lab 5 — Multi-Environment Architecture](../labs/lab-05-multi-environment/) and [Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).

---

## Question 17: The password in the state export

### Scenario
During a routine audit, a security engineer pulls a copy of production state for review (`terraform state pull`) and discovers plaintext database passwords, even though every relevant variable in the configuration is marked `sensitive = true`.

### Interview Question
Is this a bug? What controls should actually be in place, and what would you do right now?

### Strong Senior-Level Answer
**Initial assessment:** not a bug — this is expected Terraform behavior that the team's mental model was wrong about. `sensitive = true` only redacts values from CLI/log/UI output; it has never protected state file contents, which is a well-documented (if often-missed) limitation.

**Technical reasoning:** the actual controls that should have been in place are state encryption at rest (SSE-KMS) and least-privilege access control on the state backend — neither of which is affected by whether a variable was marked sensitive.

**Investigation process:** immediately check: is the state bucket using SSE-KMS or just default SSE-S3 (weaker access-control granularity)? Who/what currently has `s3:GetObject` access to this specific state path? Has this state ever been exported/copied anywhere else (a local laptop, a shared drive, an old CI artifact) that would need separate remediation?

**Recommended solution:** rotate every credential found in plaintext in this state immediately, regardless of how contained the access appears to have been — a credential that was ever in an unencrypted-at-rest or broadly-accessible location should be treated as potentially exposed. Then implement the actual controls: SSE-KMS on the bucket with a key policy scoped to the specific roles that need it, tightened `s3:GetObject`/`PutObject` IAM policy to just the CI execution role and a small break-glass admin set, and where the resource type supports it, migrate to provider-/service-managed credential generation (e.g., `manage_master_user_password = true` for RDS) so Terraform itself never has plaintext credentials passing through its state in the first place.

**Risk controls:** add this exact check (are secrets present in state that should instead be service-managed) as a recurring audit item, not a one-time fix.

**Validation steps:** after rotation, confirm the application(s) using the rotated credentials were updated (via their own secret-fetch mechanism, ideally Secrets Manager/Parameter Store rather than reading the value out of Terraform outputs) and are functioning correctly before considering the incident closed.

**Rollback or recovery strategy:** not applicable in the traditional sense — this is a hardening response, not an infrastructure change with a rollback path; the "recovery" is the rotation plus access-control tightening described above.

**Long-term prevention:** treat "does this resource type support provider/service-managed credentials instead of a Terraform-supplied plaintext password" as a default design question for every future stateful resource, and document clearly (in onboarding/architecture docs) that `sensitive = true` is a UI control, not a storage control, so this misunderstanding doesn't recur on the next team that inherits this configuration.

### Step-by-Step Implementation
```hcl
# Before: plaintext password flows into state regardless of `sensitive`
resource "aws_db_instance" "app" {
  # ...
  password = var.db_password   # var marked sensitive = true, still plaintext in state
}

# After: AWS manages and rotates the credential; Terraform never sees/stores the plaintext
resource "aws_db_instance" "app" {
  # ...
  manage_master_user_password = true
  master_user_secret_kms_key_id = aws_kms_key.rds_secret.arn
}
```
```bash
# Tighten state bucket encryption/access
aws s3api put-bucket-encryption --bucket tf-state-bucket \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"aws:kms","KMSMasterKeyID":"<key-arn>"}}]}'
```

### Under-the-Hood Explanation
`sensitive = true` is metadata Terraform Core tracks alongside a value purely to control its own CLI rendering logic (redacting it in `plan`/`apply` output and requiring an explicit flag to reveal it via `terraform output`) — it has no effect whatsoever on what gets serialized into the state JSON, which always contains the full, real attribute values returned by the provider so Terraform can correctly diff them on the next plan. Provider-managed secrets (like RDS-managed master passwords) instead store only a reference (e.g., a Secrets Manager ARN) as the resource's state attribute, with the actual secret value generated and held by AWS, never passing through Terraform's plan/apply/state pipeline as plaintext at all.

### Common Weak Answer
"That shouldn't be possible since the variable is marked sensitive — must be a Terraform bug."

### Why the Weak Answer Fails
Assuming this must be a tooling bug rather than recognizing the well-known and correct scope of `sensitive` marking indicates a gap in understanding what actually protects secrets in Terraform-managed infrastructure — exactly the gap that led to the audit finding in the first place.

### Follow-Up Questions
1. Which other resource types in a typical AWS estate support provider/service-managed credentials the way RDS does, and which don't (where you're stuck with a Terraform-supplied secret)?
2. How would you design a policy-as-code check that flags any resource argument likely to contain a plaintext secret, as a backstop against this pattern recurring?
3. If native Terraform state encryption (the 1.10+ `encryption` block) were available, how would you decide whether to adopt it in addition to backend-level SSE-KMS?

### Key Interview Signals
Confirms the candidate doesn't conflate `sensitive` marking with actual secret protection, and can name concrete, resource-specific alternatives (provider-managed secrets) rather than only generic "encrypt everything" advice.

### Hands-On Connection
[Lab 2 — Secure Remote State](../labs/lab-02-remote-state/) and [Lab 10 — Terraform Security Pipeline](../labs/lab-10-security-validation/).

---

## Question 18: Bootstrapping the backend that doesn't exist yet

### Scenario
A brand-new AWS account has no Terraform backend infrastructure at all. You need to create the S3 bucket and locking mechanism that all future Terraform state for this account will use — but that configuration itself needs to store its state somewhere.

### Interview Question
How do you solve this chicken-and-egg problem safely?

### Strong Senior-Level Answer
**Initial assessment:** the bootstrap configuration that creates the shared backend infrastructure cannot use that backend for its own state — it needs an independent, deliberately minimal state management approach of its own.

**Technical reasoning:** the standard pattern is a small, separate root module ("bootstrap") using **local state** (checked into a tightly-access-controlled location, or, more robustly, a separate, pre-existing organization-wide bootstrap state backend if one already exists from account-vending automation) that provisions exactly the backend resources (S3 bucket, versioning, encryption, bucket policy, lock mechanism) and nothing else.

**Investigation process:** confirm whether the organization already has an account-vending/landing-zone pipeline (see [`terraform-architecture.md` §8](../docs/terraform-architecture.md#8-multi-account-strategies-landing-zones-and-account-vending)) that could provision this bootstrap infrastructure as part of standard account creation, rather than a one-off manual bootstrap per account.

**Recommended solution:** keep the bootstrap configuration deliberately tiny (ideally just the bucket, its policies/encryption/versioning, and the lock mechanism) so its local state file is low-risk and rarely touched after initial creation; store that local state file in a secured location (e.g., a dedicated, access-restricted S3 bucket in a separate management account used only for bootstrap states across the org, if available) rather than a raw local file on an individual's laptop.

**Risk controls:** apply this bootstrap configuration through the same CI/OIDC pipeline discipline as everything else where possible — avoid a pattern where "someone runs it from their laptop once" becomes the undocumented, unrepeatable source of truth for how the backend was created.

**Validation steps:** once the backend exists, immediately migrate a trivial test configuration to use it (`init -migrate-state` on a throwaway config) and confirm locking/versioning/encryption all work as expected before any real production configuration relies on it.

**Rollback or recovery strategy:** since the bootstrap state itself has no backend to fall back on, its own recovery relies on whatever storage location it was placed in having its own backup/versioning — this recursive problem is exactly why the bootstrap configuration should be minimal and rarely modified after initial setup, reducing the surface area where this matters.

**Long-term prevention:** if provisioning many AWS accounts over time, invest in a proper account-vending pipeline that automates this bootstrap step consistently, rather than repeating an ad hoc manual bootstrap per account.

### Step-by-Step Implementation
```hcl
# bootstrap/main.tf — deliberately uses only local state
terraform {
  # no backend block here — local state, intentionally
}

resource "aws_s3_bucket" "tf_state" {
  bucket = "my-org-tfstate-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.tf_state.arn
    }
  }
}
# ... bucket policy denying non-TLS, DynamoDB lock table or native S3 locking config ...
```
```bash
cd bootstrap/
terraform init      # local state
terraform apply     # creates the shared backend infrastructure

cd ../actual-environment/
# now configure this and every future config's backend block to point at the bucket above
terraform init
```

### Under-the-Hood Explanation
There's nothing special happening under the hood here — this is purely an ordering/bootstrapping constraint, not a Terraform mechanism. The bootstrap configuration's local `terraform.tfstate` is exactly as capable/fragile as any local state file (see [`state-management.md` §2](../docs/state-management.md#2-local-vs-remote-state)); the design goal is minimizing how much matters depends on that one fragile file by keeping the bootstrap configuration's scope as small as possible.

### Common Weak Answer
"Just use Terraform Cloud's free tier for the bootstrap state so it's not local."

### Why the Weak Answer Fails
This may be a reasonable choice in some organizations, but presented as the *complete* answer it misses the actual point of the question — the candidate needs to recognize the fundamental bootstrapping constraint (bootstrap can't use the backend it creates) and articulate a deliberate, minimal, access-controlled approach to whatever storage the bootstrap state does use, not just relocate the same local-state fragility to a different free-tier service without addressing scope minimization or access control.

### Follow-Up Questions
1. How would you handle bootstrapping this consistently across 50 new AWS accounts without 50 different ad hoc bootstrap processes?
2. What's your process if the bootstrap state itself is lost — is this recoverable, and how?
3. Should the bootstrap configuration's own state ever be migrated into the backend it created, once that backend exists — why or why not?

### Key Interview Signals
Confirms the candidate recognizes this as a genuine structural constraint (not solvable by "just use a different remote backend," which recreates the same bootstrapping problem one level removed) and designs for minimal blast radius given that constraint.

### Hands-On Connection
[Lab 2 — Secure Remote State](../labs/lab-02-remote-state/) — implements exactly this bootstrap-first pattern.

---

## Question 19: The `state rm` that came back to bite

### Scenario
An engineer runs `terraform state rm aws_instance.legacy_cache` intending to hand ownership of this one EC2 instance to a different, newer Terraform configuration that will re-import it. They forget to also remove the resource block from the original configuration. Three weeks later, someone runs `terraform apply` on the original configuration.

### Interview Question
What happens, and how do you prevent this class of mistake going forward?

### Strong Senior-Level Answer
**Initial assessment:** `terraform state rm` only removes the *state entry* — it has no effect on the configuration. Since the resource block `aws_instance.legacy_cache` still exists in the original `.tf` files, Terraform now sees a resource in configuration with no corresponding state entry, which reads as "this needs to be created" — the plan will show a **new** EC2 instance being created, not a no-op, potentially producing a genuine duplicate of whatever the newer configuration re-imported.

**Technical reasoning:** this is exactly the "resource exists in the cloud but missing from state (from this configuration's perspective)" pattern, self-inflicted by an incomplete two-repo ownership handoff.

**Investigation process:** before this reaches apply, `terraform plan` on the original configuration would have shown the create operation clearly — this should have been caught at plan-review time; the actual incident question is why a plan showing an unexpected `+` on a resource everyone assumed was already gone from this configuration wasn't caught.

**Recommended solution:** if caught pre-apply (via plan review), simply also remove the `aws_instance.legacy_cache` resource block (or use a `removed` block for a clean, reviewable record) from the original configuration — no infrastructure impact, since nothing was actually applied. If this reaches apply and a genuine duplicate instance gets created, the fix is to immediately identify the duplicate created, decide (based on whether the newer configuration's instance is the one now actually in use) whether to destroy the accidental duplicate or the older one, and clean up whichever configuration no longer correctly reflects reality.

**Risk controls:** any ownership-handoff operation (`state rm` + re-import elsewhere) should be done as a single atomic, reviewed change spanning **both** configurations in the same PR/change window — not as two independent, separately-timed operations where one team forgets the other half.

**Validation steps:** after any `state rm`, immediately run `terraform plan` on the source configuration as a mandatory next step (not "eventually") to confirm it now shows the resource being *created* (expected, since it's config-still-present/state-now-absent) and use that as the trigger to actually go remove the resource block right then, rather than leaving it as a follow-up task that gets forgotten.

**Rollback or recovery strategy:** for the duplicate-instance case, decide which instance is authoritative (check application traffic/usage against each), migrate any traffic/state to the correct one, then destroy the erroneous duplicate deliberately via Terraform (not a manual console deletion) so its removal is tracked.

**Long-term prevention:** prefer `removed` blocks (Terraform >= 1.7) over ad hoc `state rm` for any planned resource handoff or decommission — a `removed` block is a single, reviewable configuration change, making it structurally harder to forget the corresponding config cleanup, since the state removal and the configuration change are the same commit.

### Step-by-Step Implementation
```hcl
# Instead of a bare `terraform state rm` followed by a forgotten config edit,
# use a removed block so state removal and config change are one reviewable unit:
removed {
  from = aws_instance.legacy_cache

  lifecycle {
    destroy = false   # state entry removed, cloud resource left untouched for re-import elsewhere
  }
}
```
```bash
terraform plan   # shows the removal cleanly, no ambiguity, config change already included
terraform apply
```

### Under-the-Hood Explanation
Terraform's diff calculation compares configuration against state independently for each resource address — it has no memory of *why* a state entry might be missing (a deliberate `state rm` for a handoff vs. accidental loss vs. never-yet-created), so a present-in-config/absent-in-state resource is always interpreted the same way: create it. This is precisely why `removed` blocks (which modify configuration and state together, as one declarative unit processed at plan time) are safer than the imperative `state rm` command for planned removals — there's no window where config and state can drift apart because someone forgot the second step.

### Common Weak Answer
"Just tell the engineer to remember to delete the resource block next time."

### Why the Weak Answer Fails
"Remember next time" is not a control — it's the same failure mode that already happened once. The systemic fix is using a mechanism (`removed` blocks) where forgetting isn't structurally possible, not a reminder to be more careful.

### Follow-Up Questions
1. How would a policy-as-code or CI check catch this specific pattern (resource present in config, absent in state, about to be created) before it's applied?
2. What if the "newer configuration" that re-imported the instance made a different assumption about one of its attributes than the original configuration had — how would that surface, and when?
3. How does this scenario change if it's a stateful resource (like this cache instance, presumably with actual cached data) versus a purely stateless one?

### Key Interview Signals
Confirms the candidate understands `state rm` purely as a state-only operation with zero config-awareness, and prefers structural fixes (`removed` blocks, atomic cross-repo changes) over process reminders.

### Hands-On Connection
[Lab 7 — Refactoring Without Recreation](../labs/lab-07-refactoring-state/) and [Lab 14 — Drift, Failure, and Recovery](../labs/lab-14-drift-and-recovery/).

---

## Question 20: Restoring the wrong history

### Scenario
While recovering from a corrupted production state (see [Question 13](#question-13-the-state-file-that-stopped-making-sense)), an engineer restores a backend object version — but it turns out to belong to a different environment's state that was, at some point in the past, accidentally written to this same object path during a prior backend misconfiguration.

### Interview Question
How would you detect this before it causes further damage, and how would you actually confirm you've restored the correct state?

### Strong Senior-Level Answer
**Initial assessment:** this is a lineage mismatch, not just a stale-serial issue — restoring a version that belongs to a genuinely different state history is a different and more serious problem than restoring a slightly-outdated version of the *correct* history.

**Technical reasoning:** every state file has a `lineage` UUID set once at creation and never changed by normal operations; comparing the restored version's lineage against what CI/other tooling expects (or against a previously-recorded known-good lineage value for this environment) is the definitive check — a serial-only comparison isn't sufficient, since two entirely different state histories could coincidentally have overlapping serial ranges.

**Investigation process:** before treating the restore as complete, run `terraform show -json` (or inspect the raw JSON) on the restored version and check its `resources` block against what this environment's configuration actually declares — a different environment's state will contain resource addresses/attributes (different VPC CIDR, different instance counts, different naming) that don't match this configuration at all, which is usually obvious on inspection even without checking lineage explicitly.

**Recommended solution:** if the restored version is confirmed to be the wrong lineage, discard it and continue searching the version history for a version whose lineage matches the expected one — do not attempt to "merge" or salvage a wrong-lineage state, since it describes fundamentally different infrastructure.

**Risk controls:** never run `plan`/`apply` against a restored state until its lineage and resource contents have both been sanity-checked against what you actually expect this environment to contain — this check should happen every time state is restored from any backup, not just when something already looks obviously wrong.

**Validation steps:** once a version with matching lineage and plausible resource contents is found, cross-check a sample of resources against the actual cloud console (as in [Question 13](#question-13-the-state-file-that-stopped-making-sense)) before considering the restore complete.

**Rollback or recovery strategy:** if the wrong-lineage version was mistakenly written back as the current object (not just inspected), immediately restore the version prior to that mistaken write, and treat the incident as a near-miss requiring a review of why the object path was ever shared between two environments' states in the first place (the actual root cause here — a historical backend misconfiguration that mixed two environments onto one path).

**Long-term prevention:** enforce strict, unique backend state paths per environment (e.g., via naming conventions and, ideally, a policy check on backend configuration itself), and record each environment's expected lineage UUID somewhere accessible (a runbook, a monitoring check) so a lineage mismatch during any future recovery is instantly detectable rather than requiring manual resource-content inspection to notice.

### Step-by-Step Implementation
```bash
# Extract lineage from a candidate restore version before committing to it
aws s3api get-object --bucket tf-state-bucket --key prod/terraform.tfstate \
  --version-id <candidate-version-id> /tmp/candidate.json
python3 -c "import json; print(json.load(open('/tmp/candidate.json'))['lineage'])"

# Compare against the recorded-known-good lineage for this environment
# (kept in a runbook / monitoring check, e.g.:)
# expected lineage for prod: 3f9a2b1c-...

# If mismatched, keep searching version history rather than restoring this one
aws s3api list-object-versions --bucket tf-state-bucket --prefix prod/terraform.tfstate
```

### Under-the-Hood Explanation
`lineage` is generated once, the first time a state file is created for a given configuration, and carried forward unchanged through every subsequent write — it exists specifically so that backends/tooling (and humans) can detect exactly this scenario: a state object at the expected path that actually belongs to a different, unrelated state history, typically from a past misconfiguration writing to the wrong path. Terraform Core itself checks lineage when applying a saved plan (see [`state-management.md` §4](../docs/state-management.md#4-state-lineage-and-serial)) but does **not** automatically check it during a manual backend-level restore — that verification is the operator's responsibility.

### Common Weak Answer
"Restore the most recent version before the corruption and move on."

### Why the Weak Answer Fails
"Most recent before corruption" assumes every version at that object path belongs to the same, correct history — exactly the assumption this scenario shows can be false. Skipping the lineage/content sanity check risks silently adopting a completely wrong environment's state as if it were correct.

### Follow-Up Questions
1. How would you design monitoring/alerting to catch a lineage mismatch automatically, rather than relying on manual inspection during a stressful recovery?
2. What backend/naming conventions would have prevented two environments from ever sharing one object path in the first place?
3. If you discover mid-recovery that production has been silently running against a wrong-lineage state for some time before anyone noticed, how do you assess the blast radius of that?

### Key Interview Signals
Tests whether the candidate treats "restore a version" as a single mechanical step or as a two-part verification (lineage match, plus content sanity-check) — a distinction that matters a great deal more than it initially sounds like it should.

### Hands-On Connection
[Lab 14 — Drift, Failure, and Recovery](../labs/lab-14-drift-and-recovery/).

---

## Question 21: Splitting one state for two teams

### Scenario
A single state currently contains both a shared Redis/caching layer (owned by the platform team) and an application's own compute resources (owned by an application team), because they were originally built together by one engineer who has since left. The two teams now want independent ownership, independent change cadence, and independent CI pipelines.

### Interview Question
Design the state-splitting migration, including how you'd sequence it to avoid any downtime for either the cache or the application.

### Strong Senior-Level Answer
**Initial assessment:** a state-splitting exercise, not a code change — the underlying Redis and application resources should be completely untouched by the migration; only their state location and CI ownership change.

**Technical reasoning:** the migration is a sequence of `state mv` operations (or `moved` blocks plus a root-module restructuring) moving the caching-layer resources into a brand-new state/backend path owned by the platform team, leaving the application resources in a (now-shrunk) state owned by the application team, with any current inter-resource references converted to the parameter-store pattern (see [Question 16](#question-16-the-outage-that-started-in-someone-elses-state)) if the application needs the cache endpoint.

**Investigation process:** enumerate every resource belonging to each side, and specifically identify any resource *attribute references* crossing the boundary (e.g., the application's security group referencing the cache's security group ID directly) — these references need a replacement mechanism before the split, not after.

**Recommended solution:**
1. Platform team publishes the cache's connection details (endpoint, port) as SSM parameters or similar, even before the split, so the application starts consuming via that indirection rather than a same-state reference.
2. Confirm via plan that this indirection produces no diff for the application (no-op, since it's the same value via a different lookup mechanism).
3. Create the new backend/state path for the platform team's state.
4. `state mv` every cache-layer resource, one at a time, into the new state, verifying zero-diff after each.
5. Update CI pipeline configuration/ownership to route platform-owned resources through the platform team's pipeline and application resources through the application team's, going forward.

**Risk controls:** perform step 4 with both teams' pipelines paused, so no concurrent apply can race the migration itself.

**Validation steps:** after the split, confirm each team's `plan` runs independently, on their own schedule, without needing to coordinate with the other, and confirm neither team's plan touches any resource now owned by the other.

**Rollback or recovery strategy:** if a `state mv` step fails partway, the resource may briefly be missing from both states — `state show` on both to locate it before any apply is attempted anywhere, since an apply during this window could attempt to recreate the resource.

**Long-term prevention:** document clear ownership boundaries as new shared infrastructure is built, so future "two teams accidentally share one state because one engineer built it all" scenarios don't recur — state boundaries should be decided at design time, not retrofitted after organizational ownership diverges.

### Step-by-Step Implementation
```bash
# 1. Application consumes cache endpoint via SSM instead of same-state reference (no-op verify)
terraform plan   # confirm zero diff after switching to data "aws_ssm_parameter" lookup

# 2. Pause both teams' pipelines

# 3. Move cache-layer resources to new state, one at a time
terraform state mv -state-out=../platform-cache/terraform.tfstate \
  'aws_elasticache_cluster.main' 'aws_elasticache_cluster.main'
terraform state mv -state-out=../platform-cache/terraform.tfstate \
  'aws_security_group.cache' 'aws_security_group.cache'
# ... continue for every cache-layer resource ...

# 4. Verify both states independently
cd ../platform-cache && terraform init -migrate-state && terraform plan   # expect 0 diff
cd ../application     && terraform plan   # expect 0 diff, no cache resources present

# 5. Resume both pipelines under their new, independent ownership
```

### Under-the-Hood Explanation
`terraform state mv -state-out=<path>` relocates a resource's state entry from the current state into a different state file/backend target, preserving all recorded attributes exactly — from the perspective of the *new* state, the resource simply already existed with the given attributes; from the perspective of the *old* state, the resource address simply no longer appears at all. As long as no configuration attribute for the moved resource changes on either side, the diff engine sees no operation needed (a true no-op), because the comparison is always attribute-value-based, not location-based.

### Common Weak Answer
"Just copy the resource blocks into a new module and re-run apply there."

### Why the Weak Answer Fails
Applying a new configuration for resources with no corresponding state entry in the new location means Terraform will plan to *create* them fresh — this is the destroy/recreate mistake from [Question 1](#question-1-the-subnet-that-shifted) and [Question 9](01-terraform-core.md#question-9-converting-a-legacy-count-fleet-to-for_each-without-downtime) applied to a state-splitting context; without `state mv`/`moved` blocks, the "new" configuration has no relationship to the existing real infrastructure as far as Terraform is concerned.

### Follow-Up Questions
1. How would you handle the case where the cache and application resources have a genuine circular reference (each needs something from the other), not just a one-directional dependency?
2. What CI/pipeline changes are needed beyond the Terraform state split itself, to make the two teams' ownership actually independent day-to-day?
3. How would this migration differ if the two resources were in different AWS accounts already, versus the same account?

### Key Interview Signals
Confirms the candidate can execute a real, safe state split end-to-end (not just describe the concept abstractly) and thinks about the operational/CI ownership handoff, not just the mechanical state move.

### Hands-On Connection
[Lab 7 — Refactoring Without Recreation](../labs/lab-07-refactoring-state/).

---

## Question 22: The merge nobody wanted to do manually

### Scenario
Following a team reorg, two previously-separate application teams (and their two separate Terraform states) are being consolidated into one team with one shared on-call rotation. Leadership wants the two applications' infrastructure eventually managed as a single, simpler state rather than two, to reduce operational overhead for the now-combined team.

### Interview Question
Is merging these two states actually the right call, and if so, how would you do it safely?

### Strong Senior-Level Answer
**Initial assessment:** push back on the premise first — organizational consolidation (one team, one on-call) doesn't automatically mean state consolidation is the right technical decision; the state-boundary guidance from [Question 15](#question-15-the-plan-that-took-twenty-minutes) still applies (blast radius, change frequency, ownership). If the two applications remain independently deployable and have different change cadences, keeping separate states with a shared team operating both may actually be preferable to merging.

**Technical reasoning:** if, after that assessment, merging genuinely makes sense (e.g., the two applications are tightly coupled, always deployed together, and the operational overhead of two states provides no real isolation benefit anymore), the mechanical approach mirrors the split in [Question 21](#question-21-splitting-one-state-for-two-teams) in reverse: `state mv` every resource from the source state into the target state's namespace, one resource/module at a time.

**Investigation process:** check for resource address collisions between the two states first (e.g., both teams happen to have a resource named `aws_security_group.app` — these would need to be renamed during the merge to avoid an address collision in the target state) and check for any environment/naming convention mismatches that would need reconciling.

**Recommended solution:** if merging: pick a target state (typically the larger/more established one), migrate resources from the source state into it with `state mv`, resolving any address collisions by choosing new, non-colliding names as part of the move (which does require a plan showing the rename — a `moved` block-equivalent, non-destructive process, as long as it's expressed as a state move, not a fresh resource declaration), verifying zero-diff at each step, and only decommissioning the source state/backend once every resource has been confirmed moved and the target state's plan is clean.

**Risk controls:** do this with both applications' deployment pipelines paused, and communicate a clear change window to the newly-combined team, since even a well-executed merge changes where future changes need to be made.

**Validation steps:** after the merge, confirm the combined state's `plan` covers exactly the union of what the two separate states previously covered, with no resource duplicated or missing.

**Rollback or recovery strategy:** keep the source state's backend intact (don't delete it) for a defined grace period after the merge, purely as a rollback reference in case an issue is discovered — not as an ongoing dual-source-of-truth, which would be confusing and risky.

**Long-term prevention:** revisit this decision if the two applications' operational coupling changes again in the future (e.g., a subsequent reorg splits them back into separate teams) — state boundaries should track actual technical/ownership boundaries over time, not be treated as a one-time, permanent decision immune to re-evaluation.

### Step-by-Step Implementation
```bash
# Check for address collisions before merging
terraform -chdir=team-a state list > /tmp/team-a-resources.txt
terraform -chdir=team-b state list > /tmp/team-b-resources.txt
comm -12 <(sort /tmp/team-a-resources.txt) <(sort /tmp/team-b-resources.txt)  # collisions

# Merge team-b's resources into team-a's state, resolving any collisions by renaming
terraform -chdir=team-b state mv -state-out=../team-a/terraform.tfstate \
  'aws_instance.app' 'aws_instance.app_b'   # renamed to avoid collision with team-a's aws_instance.app

# Verify
cd ../team-a && terraform plan   # expect 0 diff, now covering both applications
```

### Under-the-Hood Explanation
This is mechanically identical to the state-splitting operation in [Question 21](#question-21-splitting-one-state-for-two-teams), just directionally reversed — `state mv` doesn't care whether it's consolidating or splitting, it only relocates a state entry's address (potentially renaming it) between state files, with the diff engine remaining satisfied as long as the target configuration's computed attributes still match what's now recorded at the new address.

### Common Weak Answer
"Sure, merge them — one state is simpler than two, and the team is unified now anyway."

### Why the Weak Answer Fails
It skips the actual technical assessment (does merging reduce or increase blast radius / plan time / lock contention for this specific pair of applications) in favor of following the organizational chart automatically — team structure and state structure are related but not identical decisions, and a senior engineer should be willing to recommend keeping states separate even when teams merge, if that's genuinely the better technical call.

### Follow-Up Questions
1. What specific technical signals would tell you merging is the wrong call even after a team reorg?
2. How would you handle a resource-address collision that isn't just a naming coincidence, but reflects two genuinely different resources that both need to exist post-merge?
3. How long would you keep the decommissioned source state/backend around as a rollback reference, and what would you actually do with it at the end of that period?

### Key Interview Signals
Tests whether the candidate treats state-boundary decisions as driven by technical/blast-radius reasoning versus reflexively following organizational changes, and whether they can execute a safe merge with the same rigor as a split.

### Hands-On Connection
[Lab 7 — Refactoring Without Recreation](../labs/lab-07-refactoring-state/).
