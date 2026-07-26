# Cheat Sheet: Common Production Failures

Quick-reference index — see [`docs/troubleshooting.md`](../docs/troubleshooting.md) for the full runbook-style catalog with symptom/cause/investigation/fix/prevention for every entry.

| Category | Failure | One-line fix |
|---|---|---|
| Provider | Failed initialization / checksum mismatch | Never bypass verification; check mirror/cache integrity |
| Provider | Crash mid-apply | `TF_LOG=trace`, check for a known provider bug, pin back |
| Provider | Unexpected replacement after upgrade | Check `ForceNew`/CHANGELOG for that resource type; pin back if unplanned |
| State | Lock timeout / stale lock | Confirm dead via CI status, then `force-unlock` |
| State | Corrupted | Restore from backend version history, never hand-edit JSON |
| State | Deleted | Infrastructure is intact — rebuild via `import`, foundational resources first |
| State | Resource in cloud, missing from state | `import` block, never let apply create a duplicate |
| State | Resource in state, missing from cloud | Check CloudTrail for who deleted it before deciding revert vs. accept |
| State | Duplicate resource address | Merge conflict artifact — rename, add `terraform validate` as a required PR check |
| State | Failed backend migration | Confirm old backend intact before retrying; back up first always |
| Environment | Wrong workspace/account/region | Structural fix: separate root modules/credentials per environment, not workspaces |
| Environment | Expired/denied credentials | Distinguish expired (re-auth) from denied (add the specific missing permission) |
| Language | Dependency cycle | Structural fix only — extract shared concern or merge; `depends_on` can't break a cycle |
| Language | Invalid `for_each` (depends on unknown value) | Key off something known at plan time, not a computed attribute |
| Language | `count` index shifting | Migrate to `for_each` via `moved` blocks |
| Operations | Manual drift | Decision framework: revert / adopt into config / `ignore_changes` / import |
| Operations | Partial/interrupted apply | `plan` first, never blind-retry; state was written incrementally |
| Operations | API throttling | Reduce `-parallelism`; check for provider-side retry/backoff behavior |
| Operations | Long plans / large state | Redesign state boundaries (ownership/blast-radius); `-target` is emergency-only |
| CI/CD | Race condition between pipelines | CI-level concurrency group per environment/state |
| CI/CD | Sensitive data exposed in logs | Rotate immediately regardless of containment confidence; fix root cause (sensitive marking, secrets manager) |
| Module | Upgrade failure | Test in non-prod first; roll back the version pin, don't push through under pressure |
| Import | ID format failure | Check provider docs for the exact format; use `-generate-config-out` |
| Lifecycle | `prevent_destroy` blocking a legitimate decommission | Two-step: remove guard (no-op plan) → remove resource/`removed` block (reviewed destroy plan) |

## The one universal rule
Never take a destructive or state-mutating action based on assumption. Gather evidence (state, cloud console, CloudTrail) → identify root cause → choose least-destructive remediation → validate via plan + independent check → document.
