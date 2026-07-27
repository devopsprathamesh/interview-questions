# scripts/

This top-level directory is reserved for organization-wide, cross-lab scripts. It's intentionally empty as of this repository's initial build — every script produced so far is scoped to the specific lab that uses it, which is the correct place for it:

- [`labs/lab-02-remote-state/scripts/state-recovery.sh`](../labs/lab-02-remote-state/scripts/state-recovery.sh)
- [`labs/lab-03-state-locking/scripts/simulate-concurrent-apply.sh`](../labs/lab-03-state-locking/scripts/simulate-concurrent-apply.sh) and `induce-stale-lock.sh`
- [`labs/lab-10-security-validation/scripts/run-security-checks.sh`](../labs/lab-10-security-validation/scripts/run-security-checks.sh)
- [`labs/lab-14-drift-and-recovery/scripts/simulate-drift.sh`](../labs/lab-14-drift-and-recovery/scripts/simulate-drift.sh) and `simulate-accidental-state-removal.sh`

If you extend this repository with something genuinely reusable across many labs (a shared conformance checker, a repo-wide cost-estimation script), this is where it belongs — promote it here only once at least two labs would actually use it, following the same "don't build shared tooling until there's a real second consumer" discipline this repository applies to module design.
