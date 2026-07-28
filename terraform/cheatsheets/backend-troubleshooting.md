# Cheat Sheet: Backend Troubleshooting

| Symptom | Likely cause | Fast diagnostic | Fix |
|---|---|---|---|
| Lock acquisition error | Another process holds the lock (normal contention) | Read `Who`/`Operation`/`Created` in the error | Wait, or confirm the process is dead → `force-unlock` |
| Lock held for hours, applies normally take minutes | Stale lock from a killed process | Check CI job history for that run | Confirm dead, then `force-unlock <ID>` |
| `init` fails with checksum mismatch | Corrupted download, tampered/incomplete mirror sync | Check `.terraform.lock.hcl` recorded checksum vs. what's served | Clear plugin cache, re-sync mirror; never bypass verification |
| State fails to parse | Corruption from an interrupted/non-atomic write | `terraform state pull` to preserve evidence first | Restore last-good version from backend version history (S3 versioning) |
| Plan shows everything needs creating | Wrong workspace / wrong account / wrong region | `terraform workspace show`; `aws sts get-caller-identity` | Abort before applying; fix backend config/credentials |
| `init -migrate-state` fails partway | Interrupted migration | Check whether the old backend's state is still intact | Restore from old backend if new one is incomplete; retry only once confirmed |
| Access denied on state bucket | IAM policy too narrow, or wrong account entirely | Confirm credentials via `sts get-caller-identity` | Correct IAM policy or backend config, not a broader wildcard grant |
| Two teams sharing one state path accidentally | Backend key/path misconfiguration | Compare `lineage` field of the state to expected value | Never assume "most recent" — verify lineage before restoring/trusting a version |
| Bootstrap chicken-and-egg (can't create the backend the config needs) | Trying to use a backend that doesn't exist yet | N/A — this is structural | Bootstrap config uses **local state only**, deliberately minimal scope (see [Lab 2](../labs/lab-02-remote-state/)) |

## Stale lock recovery procedure
1. Read the lock error's metadata.
2. Confirm via CI job status (or direct communication) the original process is genuinely dead.
3. `terraform force-unlock <LOCK_ID>`.
4. `terraform plan` (never blind `apply`) to check for a partial-apply situation.

## State corruption recovery procedure
1. `terraform state pull > backup.json` (preserve evidence).
2. Check backend version history for the last version that parses cleanly.
3. Restore that version via the backend's native mechanism.
4. Verify **both** lineage match and resource contents look plausible before trusting it (a serial check alone isn't sufficient — see [Question 20](../interview-questions/02-state-management.md#question-20-restoring-the-wrong-history)).
5. `terraform plan` and reconcile any expected staleness deliberately.

Full scenarios: [`interview-questions/02-state-management.md`](../interview-questions/02-state-management.md) and [`interview-questions/10-troubleshooting.md`](../interview-questions/10-troubleshooting.md).
