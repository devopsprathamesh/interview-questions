# Recovery Runbook: Drift, Failure, and State Incidents

This is the documented runbook this lab produces as its deliverable. It consolidates the recovery procedures from across `docs/state-management.md` and `docs/troubleshooting.md` into a single, incident-ready reference. Follow the [Interview Response Framework](../../README.md#interview-response-framework) structure for any incident not explicitly covered here.

## 1. Manual infrastructure drift detected

**Symptom:** `terraform plan` shows an unexpected change with no corresponding configuration edit.

**Procedure:**
1. Identify what changed and who/what changed it (CloudTrail, or the change author if known).
2. Decide, per [`docs/state-management.md` §11](../../docs/state-management.md#11-manual-infrastructure-changes-and-drift): was it intentional and should persist (update config to match) / intentional but should revert (let the next apply revert it, checking timing first) / a field that should be permanently externally-owned (`ignore_changes`, scoped narrowly) / or an entirely unmanaged resource (`import`).
3. Never resolve drift by hand-editing state.

**Simulated in this lab:** `scripts/simulate-drift.sh`.

## 2. Stale state lock

**Symptom:** `terraform plan`/`apply` fails immediately with a lock-acquisition error.

**Procedure:**
1. Read the lock error's `Who`, `Operation`, `Created` fields.
2. Confirm via CI job status or direct communication that the identified process is genuinely dead — never force-unlock on elapsed time alone.
3. `terraform force-unlock <LOCK_ID>`.
4. Run `terraform plan` (not apply) first to assess what the interrupted operation left behind.

**Simulated in this lab:** [Lab 3](../lab-03-state-locking/)'s `scripts/induce-stale-lock.sh`.

## 3. Partial / interrupted apply

**Symptom:** An apply is killed mid-run (CI runner terminated, network loss, Ctrl-C).

**Procedure:**
1. Resolve any stale lock first (§2).
2. `terraform state list` — compare against what the interrupted apply intended to create.
3. Independently check the cloud console/API for anything the plan intended to create, to catch any edge-case timing gap between a completed API call and a written state entry.
4. `terraform plan` (never blind-apply) and read every line before proceeding.

## 4. Accidental state removal (`state rm` without config removal)

**Symptom:** A resource that should still be managed shows as needing to be **created** in the next plan, even though it already exists.

**Procedure:**
1. Do not apply the plan yet — a resource type that enforces name/uniqueness constraints will fail to create a duplicate; others may silently create one.
2. Confirm whether this was an intentional hand-off (another team/state now owns this resource) or a genuine mistake.
3. If a mistake: `terraform import <address> <id>` (or an `import` block) to restore the correct state entry.
4. If intentional: remove the resource block from *this* configuration too (or use a `removed` block, which does both atomically) so config and state agree.

**Simulated in this lab:** `scripts/simulate-accidental-state-removal.sh`.

## 5. Incorrect / unintended module version applied

**Symptom:** A `terraform init -upgrade` (deliberate or accidental) resolves a module version nobody intended, producing an unexpected plan.

**Procedure:**
1. Check `.terraform.lock.hcl` and the module's `version` constraint history (`git log`) to identify exactly what changed.
2. Pin back to the last-known-good version explicitly.
3. Re-run `plan` and confirm the diff returns to the expected baseline.
4. If the new version is genuinely needed, follow the contract-testing discipline from [Question 30](../../interview-questions/03-modules.md#question-30-proving-a-new-module-version-wont-break-anyone-before-you-ship-it) before adopting it for real.

## 6. Resource exists in cloud but missing from state

**Symptom:** `terraform plan` proposes to create something that already exists.

**Procedure:** identical to §4 step 3 — `import` (or an `import` block with `-generate-config-out` if no matching configuration exists yet) rather than letting `apply` proceed.

## 7. Resource exists in state but not in the cloud

**Symptom:** `terraform plan` shows a resource being recreated with no configuration change — it was deleted outside Terraform.

**Procedure:**
1. Check CloudTrail for who/what deleted it and when.
2. Confirm this wasn't an intentional decommission that should instead have removed the resource from configuration.
3. If it should be restored, let the next `apply` recreate it (understanding this is a *new* resource, not a restoration of the old one's data if it was stateful — see [Question 75](../../interview-questions/08-cicd.md#question-75-cant-we-just-roll-it-back)).

## General principle underlying every procedure above
Never take a destructive or state-mutating action based on assumption alone. Always: gather evidence (state, cloud console, CloudTrail) → identify root cause → choose the least-destructive remediation → validate via `plan` and an independent cloud check → document what happened and why.
