# Lab 12: CI/CD Pipeline

## Objective
Stand up a production-oriented GitHub Actions pipeline for the `environments/dev|staging|production` configurations: PR validation, module testing, security scanning, a policy-as-code gate, a saved plan artifact, environment-protected manual approval for apply, OIDC authentication, and a scheduled drift-detection job.

## Scenario
Your organization's `environments/` directory (built in [Lab 5](../lab-05-multi-environment/)) currently has no CI/CD at all — every apply is a manual, local `terraform apply`. You're building the pipeline that will replace that, enforcing every gate this repository's `docs/cicd.md` describes, end to end.

## Skills Practised
- GitHub Actions workflow design: `concurrency`, `environment` protection, matrix strategies
- OIDC-based AWS authentication (no stored credentials)
- Plan-artifact-then-apply-the-exact-artifact discipline
- Policy-as-code integration into the plan stage (Conftest, wired to [Lab 13](../lab-13-policy-as-code/))
- Scheduled drift detection via `-detailed-exitcode`
- Concurrency groups preventing simultaneous applies against the same state

## Architecture
See [Diagram 11: CI/CD Workflow](../../diagrams/11-cicd-workflow.md) for the full pipeline shape. This lab's [`../../.github/workflows/terraform.yml`](../../.github/workflows/terraform.yml) implements exactly that diagram: `validate` → `test` → `security-scan` → `plan` (matrixed per environment, policy-gated, artifact-uploaded) → `apply` (main branch only, one environment at a time, environment-protected) plus a separate scheduled `drift-detection` job.

## Prerequisites
- [Lab 2](../lab-02-remote-state/) (remote backend), [Lab 5](../lab-05-multi-environment/) (the `environments/` directory), and [Lab 13](../lab-13-policy-as-code/) (the `policies/` the plan job references) completed
- A GitHub repository (fork or clone this repository) with Actions enabled
- An AWS OIDC identity provider and IAM role configured per [`docs/terraform-architecture.md` §5](../../docs/terraform-architecture.md#5-authentication--avoiding-credentials-in-code) — see Step 1 below
- GitHub Environments named `dev`, `staging`, `production` configured in repository settings, with `production` requiring at least one manual reviewer

## Directory Structure
```text
.github/workflows/terraform.yml   # the pipeline itself (repo-root, not lab-scoped)
.tflint.hcl                        # repo-root TFLint config the pipeline uses
environments/{dev,staging,production}/backend.hcl.example
labs/lab-12-cicd-pipeline/
└── README.md
```

## Step-by-Step Tasks
1. Create the OIDC identity provider and IAM role in your AWS account (see the trust-policy JSON in [`docs/cicd.md` §7](../../docs/cicd.md#7-oidc-based-cloud-authentication-in-pipelines)), scoped to your fork's `repo:OWNER/REPO:environment:*` claims.
2. In your GitHub repository settings, create three Environments (`dev`, `staging`, `production`); add a required reviewer to `production` only.
3. Add a repository variable `TERRAFORM_ROLE_ARN` with the IAM role's ARN.
4. Copy each environment's `backend.hcl.example` → `backend.hcl` with your Lab 2 bucket/table names, and commit them (they contain no secrets, only backend addressing).
5. Open a PR touching `environments/dev/main.tf` (a trivial, reviewable change) and watch the pipeline run `validate` → `test` → `security-scan` → `plan` (all three environments, in parallel) automatically.
6. Merge the PR to `main` and watch `apply` run for `dev`, then `staging`, then pause on `production` awaiting the manual reviewer's approval (per the Environment protection rule).
7. Approve the `production` deployment and confirm it applies the **exact plan artifact** generated during the PR's `plan` job, not a freshly regenerated one.

## Terraform Configuration
This lab reuses [`environments/`](../../environments/) from Lab 5 unchanged — the deliverable here is the pipeline, not new Terraform resources.

## Commands to Execute
```bash
# Local dry-run of what the pipeline's validate job does, before ever pushing:
terraform fmt -check -recursive
for dir in environments/*/; do (cd "$dir" && terraform init -backend=false && terraform validate); done
for dir in modules/*/; do [ -d "${dir}tests" ] && (cd "$dir" && terraform test); done
```

## Expected Output
A PR shows four green checks (validate, test, security-scan, plan×3 via matrix) before it's mergeable. After merge, the Actions tab shows `apply (dev)` completing automatically, `apply (staging)` completing automatically, and `apply (production)` paused with a yellow "Waiting for review" status until the designated reviewer approves.

## Validation
```bash
# Confirm the applied plan matches what was reviewed - compare artifact checksums
gh run download <run-id> -n tfplan-production
sha256sum tfplan   # compare against the value recorded in the plan job's logs
```

## Failure Injection
Merge two small, unrelated PRs to `main` within the same minute (or push directly twice in quick succession) and watch the Actions tab — the second `apply` run for a given environment should show as **queued behind** the first, not failing with a lock error, proving the `concurrency:` group is working as designed (see [Question 72](../../interview-questions/08-cicd.md#question-72-the-queue-nobody-could-see)).

## Troubleshooting Exercise
Temporarily break the OIDC trust policy's `sub` condition (widen it to match any repository) in a **test/sandbox** AWS account only, then narrow it back and confirm via CloudTrail that no unexpected principal was able to assume the role during the window — a hands-on rehearsal of [Question 37](../../interview-questions/04-providers.md#question-37-the-assume-role-trust-policy-that-trusted-too-much). Never do this against a real production trust policy.

## Cleanup
This lab creates no AWS resources of its own — it operates the resources from Labs 5/8/9. Ensure any environments applied purely for this exercise (especially non-representative test changes) are reverted via a follow-up PR, and destroy any lab-only AWS resources per their own labs' Cleanup sections.

## Interview Questions Connected to This Lab
- [Question 69: The apply that wasn't quite what was reviewed](../../interview-questions/08-cicd.md#question-69-the-apply-that-wasnt-quite-what-was-reviewed)
- [Question 70: The plan artifact that got a second opinion](../../interview-questions/08-cicd.md#question-70-the-plan-artifact-that-got-a-second-opinion)
- [Question 72: The queue nobody could see](../../interview-questions/08-cicd.md#question-72-the-queue-nobody-could-see)
- [Question 78: The plan from a stranger](../../interview-questions/08-cicd.md#question-78-the-plan-from-a-stranger)

## Production Considerations
- This workflow triggers on `pull_request`, not `pull_request_target` — external fork contributions get `validate`/`test` feedback but never real AWS credentials, per [Question 78](../../interview-questions/08-cicd.md#question-78-the-plan-from-a-stranger). If you accept external contributions, keep it this way.
- The approver list for the `production` GitHub Environment should be tied to an actively-maintained team/on-call rotation, not a hand-maintained list — see [Question 73](../../interview-questions/08-cicd.md#question-73-too-many-people-who-can-say-yes).
- A real organization would also wire in the fallback-scanner pattern from [Question 77](../../interview-questions/08-cicd.md#question-77-the-scanner-that-took-down-every-deployment) in case the Checkov Action's dependencies have an outage.

## Advanced Challenge
Add a `rollback` workflow_dispatch-triggered job that, given a specific prior plan artifact's run ID, re-applies it — and then deliberately try to use it to "roll back" a resource replacement, observing firsthand why this doesn't restore lost data (per [Question 75](../../interview-questions/08-cicd.md#question-75-cant-we-just-roll-it-back)) even though it does correctly revert the *configuration*.
