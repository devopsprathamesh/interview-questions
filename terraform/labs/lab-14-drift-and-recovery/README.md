# Lab 14: Drift, Failure, and Recovery

## Objective
Deliberately simulate the highest-frequency real production incidents — manual drift, a stale lock, an accidental state-only removal — against real (Lab 1) infrastructure, and produce a documented, tested recovery runbook rather than relying on memory during a real incident.

## Scenario
Six months from now, at 2 a.m., someone on your team will hit one of these exact failure modes for real. This lab is where you build the muscle memory and the actual runbook (not a hypothetical one) so that moment is routine instead of a crisis.

## Skills Practised
- Diagnosing and correctly resolving manual infrastructure drift
- Safe stale-lock recovery (building on [Lab 3](../lab-03-state-locking/))
- Recognizing and recovering from an accidental `state rm` without config removal
- Writing an incident runbook that's actually been exercised, not just written

## Architecture
This lab has no new infrastructure of its own — it operates against [Lab 1](../lab-01-core-workflow/)'s existing S3 bucket and `local_file`, deliberately reusing already-applied resources so every exercise here is about **operating** Terraform under failure conditions, not building anything new. See [Diagram 14: Drift Detection and Reconciliation](../../diagrams/14-drift-detection.md) for the drift decision flow this lab exercises directly.

## Prerequisites
- [Lab 1](../lab-01-core-workflow/) applied and still present (do not destroy it until this lab is complete)
- [Lab 3](../lab-03-state-locking/) completed (for the stale-lock recovery exercise, reused here rather than repeated)
- [Lab 7](../lab-07-refactoring-state/) completed (context for the incorrect-module-version-applied scenario in the runbook)

## Directory Structure
```text
lab-14-drift-and-recovery/
├── README.md
├── recovery-runbook.md      # the actual deliverable: a documented, exercised runbook
└── scripts/
    ├── simulate-drift.sh
    └── simulate-accidental-state-removal.sh
```

## Step-by-Step Tasks
1. From your still-applied [Lab 1](../lab-01-core-workflow/) directory, run `../lab-14-drift-and-recovery/scripts/simulate-drift.sh "$(terraform output -raw bucket_name)"`.
2. Run `terraform plan` in the Lab 1 directory and confirm it shows the tag reverting — walk through the [`docs/state-management.md` §11](../../docs/state-management.md#11-manual-infrastructure-changes-and-drift) decision framework out loud (or in writing) before running `apply` to revert it.
3. Run `../lab-14-drift-and-recovery/scripts/simulate-accidental-state-removal.sh local_file.summary` from the Lab 1 directory.
4. Run `terraform plan` and observe the proposed **create** for `local_file.summary` — read [`recovery-runbook.md` §4](recovery-runbook.md#4-accidental-state-removal-state-rm-without-config-removal) and recover using `terraform import` rather than applying the plan blind.
5. Revisit [Lab 3](../lab-03-state-locking/)'s stale-lock scripts once more, this time timing yourself against [`recovery-runbook.md` §2](recovery-runbook.md#2-stale-state-lock) — how long does correct recovery actually take under a stopwatch, versus how long you'd guess during a real incident?
6. Read `recovery-runbook.md` in full and confirm every procedure in it matches what you actually did in Steps 1-5 — if anything is unclear or incomplete, fix the runbook itself; a runbook nobody has followed exactly as written isn't proven yet.

## Terraform Configuration
No new configuration — this lab operates [Lab 1](../lab-01-core-workflow/)'s existing `main.tf`.

## Commands to Execute
```bash
cd ../lab-01-core-workflow
../lab-14-drift-and-recovery/scripts/simulate-drift.sh "$(terraform output -raw bucket_name)"
terraform plan   # observe drift
terraform apply  # revert it, after considering the decision framework

../lab-14-drift-and-recovery/scripts/simulate-accidental-state-removal.sh local_file.summary
terraform plan   # observe the proposed (wrong) create
terraform import local_file.summary "$(terraform output -raw summary_file_path)"
terraform plan   # confirm zero diff after correct recovery
```

## Expected Output
After Step 2's recovery, `terraform plan` in Lab 1 shows no changes. After Step 4's recovery (via `import`, not a blind `apply`), `terraform plan` also shows no changes — proving the state entry was correctly restored without creating a duplicate or losing the resource's real content.

## Validation
```bash
# Confirm Lab 1's state is fully consistent with reality after both recovery exercises
cd ../lab-01-core-workflow
terraform plan   # MUST show "No changes" after every recovery in this lab
terraform state list   # confirm local_file.summary is present again
```

## Failure Injection
This entire lab *is* the failure-injection exercise. For an additional one: run `simulate-accidental-state-removal.sh` again, but this time do **not** recover it — instead, run `terraform apply` and observe what actually happens (a `local_file` resource is idempotent to recreate, so this specific example is survivable; discuss with a peer why the same mistake against `aws_s3_bucket.demo` instead would be far riskier, since bucket names are globally unique and a "duplicate" attempt would simply fail rather than silently succeed).

## Troubleshooting Exercise
Deliberately corrupt Lab 1's local `terraform.tfstate` (if not yet migrated to a remote backend) by manually editing a single character in the JSON, and observe the resulting error. Restore from `terraform.tfstate.backup` and confirm `terraform plan` returns to normal — a hands-on, low-stakes rehearsal of the state-corruption recovery process from [`docs/state-management.md` §7](../../docs/state-management.md#7-state-corruption-loss-and-recovery), safe to do here specifically because Lab 1 uses local state and has nothing production-critical at stake.

## Cleanup
No new resources were created in this lab. Once you're finished with Lab 1 entirely (across all its dependent labs), run `terraform destroy` in the Lab 1 directory per that lab's own Cleanup section.

## Interview Questions Connected to This Lab
- [Question 11: Two pipelines, one state](../../interview-questions/02-state-management.md#question-11-two-pipelines-one-state)
- [Question 12: The lock that would not die](../../interview-questions/02-state-management.md#question-12-the-lock-that-would-not-die)
- [Question 19: The state rm that came back to bite](../../interview-questions/02-state-management.md#question-19-the-state-rm-that-came-back-to-bite)
- [Question 87 through 98 across `10-troubleshooting.md`](../../interview-questions/10-troubleshooting.md) — this lab is the hands-on companion to the entire troubleshooting category

## Production Considerations
- A real incident runbook should be linked from your team's on-call/paging documentation, not left in a repository nobody opens under pressure — make sure whichever tool your team actually uses during an incident links here (or to your organization's equivalent).
- Practice this runbook periodically (a "game day" exercise), not just once when it's written — the same principle as DR drills (see [`docs/ha-dr.md` §4](../../docs/ha-dr.md#4-hadr-testing--the-gap-between-designed-and-proven)) applies to state-incident runbooks too.

## Advanced Challenge
Extend `recovery-runbook.md` with a section for a scenario not simulated in this lab: a **lineage mismatch** during state restoration (per [Question 20](../../interview-questions/02-state-management.md#question-20-restoring-the-wrong-history)). Since this requires two genuinely different state histories to demonstrate safely, design (in writing, without necessarily executing it against real infrastructure) how you'd simulate it in a throwaway sandbox: two separate Lab 1 applies to two different buckets, sharing one local state file path by mistake, and the runbook section describing how you'd detect and recover from that specific confusion.
