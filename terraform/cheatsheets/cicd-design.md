# Cheat Sheet: CI/CD Design

## The PR validation chain (in order)
1. `terraform fmt -check`
2. `terraform validate`
3. TFLint
4. Security scan (Checkov/Trivy)
5. Unit tests (`terraform test`, plan-mode)
6. `terraform plan`
7. Policy-as-code (Conftest/OPA against plan JSON)

Every step should be a **required** status check, not advisory.

## Plan artifact integrity
- Save the plan (`-out=tfplan`), upload as a CI artifact.
- **Apply the exact saved plan file** — never regenerate at apply time. Terraform's own serial/lineage check will fail loudly if state moved on since the plan was saved.
- Checksum the artifact for defense-in-depth against tampering between plan and apply jobs.

## Approval gates
| Environment | Gate |
|---|---|
| Dev | Auto-apply on merge |
| Staging | Plan review, lightweight/automatic approval |
| Production | **Mandatory named-reviewer approval**, against the exact reviewed plan artifact |

Tie the production approver list to an actively-maintained team/on-call rotation, never a hand-maintained list (it will drift).

## Concurrency
```yaml
concurrency:
  group: terraform-production
  cancel-in-progress: false   # NEVER true for apply jobs
```
CI-level concurrency groups serialize runs *before* they attempt the backend lock — the lock remains a correctness backstop, not the primary UX.

## OIDC authentication
- No stored long-lived cloud credentials, ever.
- Trust policy conditioned on `sub`/`aud` claims scoped to the exact repo **and environment** — a repo-only condition lets any workflow in that repo assume the role regardless of environment-protection rules.

## Drift detection
Scheduled job: `terraform plan -detailed-exitcode`, no apply. Exit code 2 → alert (severity-tiered, not one noisy channel — see [Question 74](../interview-questions/08-cicd.md#question-74-the-drift-alert-everyone-learned-to-ignore)).

## Rollback reality check
Terraform has no generic rollback. "Rolling back" = reapplying old config, which recreates resources but does **not** restore lost data. Real rollback for stateful resources = data-layer backup restoration. The only genuinely instant rollback is a blue-green traffic shift.

## Fork PR safety
`pull_request` (not `pull_request_target`) for fork-originated PRs — no secrets exposed to untrusted code. Full credentialed plans for forks only via an explicit, maintainer-triggered path (e.g., a `/plan` comment restricted to `MEMBER`/`OWNER` association).

Full reference: [`docs/cicd.md`](../docs/cicd.md), [`interview-questions/08-cicd.md`](../interview-questions/08-cicd.md), [Lab 12](../labs/lab-12-cicd-pipeline/).
