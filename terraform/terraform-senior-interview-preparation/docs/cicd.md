# CI/CD and Automation

A Terraform pipeline is not "run `terraform apply` in a cron job." It's a chain of gates — each cheap and fast enough to run on every PR, each catching a class of problem the previous gate couldn't — culminating in an apply that is provably identical to what was reviewed. This document backs [`interview-questions/08-cicd.md`](../interview-questions/08-cicd.md) and is exercised in full in [Lab 12](../labs/lab-12-cicd-pipeline/).

## 1. The pull-request validation chain

In increasing cost/latency order, every PR touching Terraform code should run:

1. **`terraform fmt -check`** — canonical formatting, near-instant, zero false positives.
2. **`terraform validate`** — internal consistency (see [`testing.md`](testing.md#2-terraform-validate--what-it-does-and-doesnt-catch)).
3. **TFLint** — provider-aware linting: deprecated syntax, unused variables/declarations, provider-specific best-practice violations (e.g., an instance type that doesn't exist for the declared provider).
4. **Security scanning** — Checkov/Trivy/Terrascan against the configuration (see [`security.md`](security.md#8-static-analysis-and-iac-scanning)).
5. **Unit tests** — `terraform test` in plan-mode/mocked-mode (see [`testing.md`](testing.md#3-native-terraform-test-tftesthcl--tftestjson)).
6. **`terraform plan`** — the actual proposed diff against the target environment's real state.
7. **Policy as code** — OPA/Conftest or Sentinel evaluated against the plan JSON (see [`security.md`](security.md#9-policy-as-code)).

Each of these should be a **required status check** on the PR (branch protection, §7) — not advisory. A PR that fails `fmt` or `validate` should be structurally unmergeable, not merely flagged.

## 2. Plan generation, plan artifacts, and plan integrity

```yaml
# conceptual pipeline logic
- terraform plan -out=tfplan
- terraform show -json tfplan > plan.json   # for policy engine consumption
- upload artifact: tfplan (binary), plan.json (for human/PR-comment review)
```

**Why the plan is saved as a binary artifact rather than regenerated at apply time:** a saved plan file locks in the exact resolved values (including anything that depended on data sources or provider state at plan time) and — critically — is validated against the target state's serial/lineage before Terraform will apply it (see [`terraform-internals.md`](terraform-internals.md#10-state-serial-lineage-and-reconciliation-during-apply)). This closes the gap between "what a human approved" and "what actually got applied." **Plan artifact integrity**: the artifact must be treated as tamper-sensitive — restrict who can upload/overwrite it, use the CI platform's built-in artifact integrity guarantees, and never apply a plan artifact that didn't come from the same pipeline run that generated and had it reviewed.

**Common anti-pattern to call out in an interview:** a pipeline that runs `terraform plan` for review, gets human approval, and then runs a **fresh** `terraform apply` (no `-out`, no reused artifact) at apply time. Between the reviewed plan and the fresh apply, state may have changed (another process applied, or drift occurred) — the thing that gets approved and the thing that gets applied are not provably the same. Always apply the saved plan file.

## 3. Plan review and human-readable output

Post a formatted plan summary as a PR comment (most CI platforms have an action/integration for this) so reviewers see the diff in context without leaving the PR. For policy-as-code results, surface violations inline with the specific resource/attribute and rule that failed — a raw pass/fail gate with no detail forces engineers to dig through CI logs, which slows the review loop and encourages people to just re-run and hope.

## 4. Apply approvals and environment protection

- **Dev**: often auto-apply on merge to the relevant branch/path — fast iteration, low blast radius.
- **Staging**: plan review required; apply may be automatic post-merge or require a lightweight approval.
- **Production**: **mandatory manual approval** from a specific, restricted set of approvers (CI platform "environment protection rules" / required reviewers), applied against the exact saved plan artifact from the reviewed PR — never a fresh plan at click-to-approve time.

**GitHub Actions** implements this via [environments](https://docs.github.com/actions/deployment/targeting-different-environments/using-environments-for-deployment) with required reviewers and (optionally) wait timers. **GitLab CI** implements it via protected environments and manual jobs with `when: manual` plus approval rules. **Jenkins** implements it via the `input` step (pipeline pauses for interactive approval) combined with role-based access control on who can approve. The mechanism differs; the requirement — a human, not a bot, explicitly authorizes the production apply, against a specific reviewed artifact — is universal.

## 5. Branch protection

Required status checks (§1) enforced via branch protection rules; require PR review before merge; restrict who can push directly to the branch that triggers production applies (ideally: no one — everything through PR). Branch protection is also where you'd require the policy-as-code gate (§9 in `security.md`) to be a required check, not optional.

## 6. Concurrency controls

**The problem:** two pipeline runs (two PRs merged close together, or a manual re-run racing a scheduled run) targeting the *same state* can hit the lock-contention failure mode from [`state-management.md`](state-management.md#3-state-locking) — one fails with a lock error, which is safe but creates pipeline noise and confusion if engineers don't understand why.

**The fix:** a **concurrency group per environment/state** at the CI-platform level (GitHub Actions `concurrency:` key, GitLab `resource_group:`), so the *pipeline itself* serializes runs targeting the same state before they ever attempt to acquire the Terraform lock — the backend lock becomes a defense-in-depth backstop, not the primary serialization mechanism, and engineers get a clear "queued behind another run" status instead of a lock-error stack trace.

```yaml
# GitHub Actions example
concurrency:
  group: terraform-production
  cancel-in-progress: false   # never cancel an in-flight apply
```

**Important:** `cancel-in-progress` must be `false` for apply jobs — cancelling an in-flight `terraform apply` mid-run is exactly the interrupted-apply scenario in [`terraform-internals.md`](terraform-internals.md#12-interrupted-and-partial-applies), and can leave a stale lock plus a partially-applied state.

## 7. OIDC-based cloud authentication in pipelines

Covered in depth in [`terraform-architecture.md`](terraform-architecture.md#5-authentication--avoiding-credentials-in-code) and [`security.md`](security.md#5-aws-iam-roles-and-oidc-authentication). Pipeline-specific detail: configure the OIDC trust policy's condition keys to match your CI platform's token claims precisely —

```json
{
  "Condition": {
    "StringEquals": {
      "token.actions.githubusercontent.com:sub": "repo:my-org/platform-infra:environment:production"
    }
  }
}
```

— so only workflow runs targeting the `production` GitHub Environment (which itself enforces the required-reviewer gate from §4) can assume the production role. A trust policy scoped only to the repository, without the environment/branch claim, would let *any* workflow in that repo assume the production role regardless of approval gates — a common, dangerous misconfiguration.

## 8. Drift detection and scheduled plans

A scheduled pipeline (nightly/hourly, environment-dependent) runs `terraform plan -detailed-exitcode` against each environment's state with **no apply** — exit code 2 (changes present) triggers an alert for investigation via the decision framework in [`state-management.md`](state-management.md#11-manual-infrastructure-changes-and-drift), rather than silently accumulating drift until the next real deployment surfaces it unexpectedly. See [Diagram 14](../diagrams/14-drift-detection.md).

## 9. Rollback limitations

**Terraform does not have a generic "rollback" command.** "Rolling back" an apply means one of:
- **Re-applying the previous configuration version** — works cleanly for most changes, but any resource replacement or destructive change from the "bad" apply already happened; reapplying old config will *recreate* that resource (new resource, not the old one restored) and cannot undo data loss (a destroyed database's data is gone regardless of whether Terraform recreates a database with the same name afterward).
- **Restoring from a data-layer backup** — genuinely necessary for stateful resources (RDS snapshots, etc.); Terraform manages the infrastructure shell, not your data's recovery point.
- **A blue-green traffic shift back to the previous environment** (see [`terraform-architecture.md`](terraform-architecture.md#11-immutable-infrastructure-and-blue-green-patterns)) — the only "rollback" that's genuinely instantaneous and safe, which is precisely why that pattern is valuable for anything where fast rollback matters.

**Interview signal:** candidates who say "we just revert the git commit and re-apply" without acknowledging that this doesn't undo destructive changes or data loss are missing a core operational reality.

## 10. Pipeline failure recovery

When a pipeline run fails mid-apply (see [`terraform-internals.md`](terraform-internals.md#12-interrupted-and-partial-applies) for the state-level mechanics):
1. Do not immediately re-trigger the pipeline. First determine *why* it failed — transient API/throttling error (safe to retry), a genuine config/policy problem (needs a fix, not a retry), or a partial apply (needs the plan-then-apply investigation from the state doc).
2. If a retry is warranted, prefer re-running `plan` fresh (not blindly re-applying the old saved plan artifact, which may now be stale against partially-changed state) and review the new plan before re-applying.
3. Add the specific failure mode to your team's runbook/alerting if it's likely to recur (a known-flaky API call that needs a retry wrapper, a policy that's too strict for a legitimate edge case, etc.).

## GitHub Actions reference pipeline (default for this repository)

See [Lab 12](../labs/lab-12-cicd-pipeline/) and [`.github/workflows/`](../.github/workflows/) for the full, runnable version. Skeleton:

```yaml
name: terraform
on:
  pull_request:
  push:
    branches: [main]

concurrency:
  group: terraform-${{ github.ref }}
  cancel-in-progress: false

permissions:
  id-token: write   # required for OIDC
  contents: read
  pull-requests: write

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
      - run: terraform fmt -check -recursive
      - run: terraform init
      - run: terraform validate
      - run: tflint --recursive

  security-scan:
    needs: validate
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run Checkov
        uses: bridgecrewio/checkov-action@v12

  plan:
    needs: security-scan
    runs-on: ubuntu-latest
    environment: ${{ github.ref == 'refs/heads/main' && 'production' || 'dev' }}
    steps:
      - uses: actions/checkout@v4
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ vars.TERRAFORM_ROLE_ARN }}
          aws-region: us-east-1
      - uses: hashicorp/setup-terraform@v3
      - run: terraform init
      - run: terraform plan -out=tfplan
      - run: terraform show -json tfplan > plan.json
      - uses: actions/upload-artifact@v4
        with:
          name: tfplan
          path: tfplan

  apply:
    needs: plan
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    environment: production   # requires manual approval via environment protection rules
    steps:
      - uses: actions/checkout@v4
      - uses: actions/download-artifact@v4
        with:
          name: tfplan
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ vars.TERRAFORM_ROLE_ARN }}
          aws-region: us-east-1
      - uses: hashicorp/setup-terraform@v3
      - run: terraform apply tfplan
```

## GitLab CI and Jenkins — conceptual equivalents

**GitLab CI**: the same stage sequence (`validate` → `security-scan` → `plan` → `apply`), with `resource_group:` providing concurrency control, protected environments plus `when: manual` providing the production approval gate, and GitLab's native OIDC support for cloud authentication (`id_tokens:` in `.gitlab-ci.yml`).

**Jenkins**: a declarative `Jenkinsfile` with equivalent stages, `input` step for manual production approval, the [Lockable Resources plugin](https://plugins.jenkins.io/lockable-resources/) for concurrency control per environment, and either a credentials-binding-based short-lived-token pattern or Jenkins' own OIDC provider integration for cloud authentication (Jenkins doesn't have first-class OIDC-to-cloud federation as tightly integrated as GitHub Actions by default — verify current plugin support before relying on a specific claim here).

## Common weak answer vs. senior answer

| Scenario | Weak answer | Senior answer |
|---|---|---|
| Approving production apply | "Add a manual approval step" | Approval must gate the exact previously-reviewed plan artifact, with OIDC trust conditions scoped to that specific environment claim, not just repo-level trust |
| Two pipelines race for the same state | "Let the lock handle it" | Add a CI-level concurrency group per environment/state so contention is resolved before it ever reaches the backend lock, with clear queued status instead of a lock-error failure |
| "How do you roll back a bad apply?" | "Revert the commit and re-apply" | Acknowledge Terraform has no generic rollback; destructive changes/data loss require data-layer backup restoration, and blue-green traffic shifts are the only genuinely instant rollback |
| Pipeline apply failed | "Re-run the pipeline" | Diagnose root cause first (transient vs. partial apply vs. config error); a blind retry on a partial apply risks unintended replacements |

## Related material
- Interview questions: [`interview-questions/08-cicd.md`](../interview-questions/08-cicd.md)
- Hands-on: [Lab 12 — CI/CD Pipeline](../labs/lab-12-cicd-pipeline/)
- Diagrams: [`diagrams/11-cicd-workflow.md`](../diagrams/11-cicd-workflow.md), [`diagrams/07-state-locking.md`](../diagrams/07-state-locking.md), [`diagrams/14-drift-detection.md`](../diagrams/14-drift-detection.md)
