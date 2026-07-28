# CI/CD and Automation

An Ansible pipeline needs the same discipline as any infrastructure-as-code pipeline: fast, cheap gates on every PR, then a controlled, auditable path to actually touching production hosts. This document backs [`interview-questions/08-cicd-automation.md`](../interview-questions/08-cicd-automation.md) and is exercised in [Lab 12](../labs/lab-12-cicd-pipeline/).

## 1. The PR validation chain

1. `ansible-lint` + `yamllint`
2. `ansible-playbook --syntax-check`
3. Molecule (Docker driver) for every changed role
4. `ansible-playbook --check --diff` against a representative inventory, where feasible — the closest analog to a Terraform plan review, with the same caveat that check mode is only as accurate as every task's own check-mode support (see [`ansible-internals.md` §4](ansible-internals.md#4-check-mode-and-diff-mode))

## 2. The "no saved plan artifact" gap — and how to close it

Terraform's plan-then-apply-the-exact-artifact pattern has **no direct Ansible equivalent** — there's no binary "saved playbook run" you review then replay verbatim. A `--check` run and the later real `ansible-playbook` run are two **separate invocations**; nothing structurally guarantees they'll do the same thing if inventory, variables, or target-host state changed in between. This is a genuine, worth-naming-directly gap compared to Terraform's guarantee.

**The practical mitigations:**
- Pin the **exact same commit/artifact** (playbook, roles, `requirements.yml`-resolved collection versions, inventory) between the `--check` review step and the real apply — never let the "apply" step re-fetch `main` fresh if it might have moved since the check was reviewed.
- Use an Execution Environment image tag pinned for both steps (see [`ansible-architecture.md` §6](ansible-architecture.md#6-execution-environments--the-air-gappedreproducibility-answer)) so the tool version itself can't drift between review and apply either.
- Treat the real apply's own `--diff` output as the actual record of what happened, logged/archived, rather than assuming it must match the earlier check-mode review.

## 3. Approval gates

| Environment | Gate |
|---|---|
| Dev | Auto-run on merge |
| Staging | Review the `--check --diff` output; lightweight approval |
| Production | Mandatory named-reviewer approval, ideally via an AWX/Automation Platform Job Template launch (giving a proper audit trail: who launched it, against which inventory, with which credential) rather than a raw CLI invocation by an individual |

## 4. Concurrency controls — a fleet-level, not just a state-level, concern

Two pipelines targeting the **same hosts** concurrently is a real risk distinct from Terraform's state-locking problem: Ansible has no built-in per-inventory lock. Two simultaneous `ansible-playbook` runs against overlapping hosts can genuinely race — e.g., both restarting the same service in an interleaved, confusing order, or one run's handler-triggered restart landing mid-way through another run's own service-dependent task.

**Mitigation:** CI-level concurrency groups scoped to the **target inventory/environment**, exactly like the Terraform state-lock mitigation:
```yaml
concurrency:
  group: ansible-production-webservers
  cancel-in-progress: false
```
For AWX/Automation Platform specifically, **Job Template concurrency settings** (`allow_simultaneous: false`, or explicit concurrent-job limiting) provide this natively for scheduled/triggered runs.

## 5. OIDC / credential handling in CI

Identical pattern to the companion Terraform repository: no long-lived cloud credentials stored as CI secrets. For AWS-calling roles/dynamic inventory, OIDC federation to an assumed IAM role, scoped to the specific repository/environment/branch. For SSH access to managed hosts, prefer short-lived certificates or a bastion/Session-Manager path over a static private key CI secret (see [`security.md` §5](security.md#5-cicd-credential-handling)).

## 6. Drift detection

A scheduled, `--check`-mode-only run (no real apply) against production inventory, on a cron, flags any host where check mode reports pending changes — the direct analog of the Terraform `-detailed-exitcode` scheduled drift job. The same accuracy caveat applies doubly hard here: a fleet full of unaudited `command`/`shell` tasks with no real check-mode support will under-report drift, giving false confidence.

```bash
ansible-playbook site.yml --check --diff | tee drift-report.log
grep -q "changed:" drift-report.log && echo "::warning::Drift detected - review drift-report.log"
```

## 7. Rollback limitations

Exactly like Terraform, **Ansible has no generic rollback.** "Rolling back" means re-running the playbook with the previous role/playbook version — which reapplies the *old configuration*, not necessarily undoing every side effect of the bad run (a database migration a bad playbook triggered doesn't un-run because you revert the playbook code; a package upgraded to a broken version doesn't automatically downgrade unless the playbook explicitly pins and re-applies the old version). For anything genuinely stateful (a database schema change, a data migration triggered by a playbook task), the same principle from the companion Terraform repository applies: infrastructure/config automation manages *configuration*, not *data* — real data-layer rollback requires a data-layer-specific recovery mechanism (a backup restore), not a playbook re-run.

## 8. GitHub Actions reference pipeline

```yaml
name: ansible-ci
on:
  pull_request:
  push:
    branches: [main]
  schedule:
    - cron: "0 6 * * *"   # scheduled drift detection

concurrency:
  group: ansible-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: false

permissions:
  id-token: write
  contents: read

jobs:
  lint-and-test:
    if: github.event_name != 'schedule'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install Ansible + collections
        run: |
          pip install ansible-core ansible-lint yamllint molecule molecule-plugins[docker]
          ansible-galaxy collection install -r requirements.yml
      - run: yamllint .
      - run: ansible-lint playbooks/ roles/
      - run: ansible-playbook playbooks/site.yml --syntax-check
      - name: Molecule test every changed role
        run: |
          for role_dir in roles/*/; do
            if [ -d "${role_dir}molecule" ]; then
              (cd "$role_dir" && molecule test)
            fi
          done

  check-mode-review:
    needs: lint-and-test
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    environment: staging
    steps:
      - uses: actions/checkout@v4
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ vars.ANSIBLE_ROLE_ARN }}
          aws-region: us-east-1
      - run: ansible-playbook playbooks/site.yml -i inventory/aws_ec2.yml --check --diff

  apply-production:
    needs: lint-and-test
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    environment: production   # manual approval gate configured in repo settings
    steps:
      - uses: actions/checkout@v4
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ vars.ANSIBLE_ROLE_ARN }}
          aws-region: us-east-1
      - run: |
          ansible-vault decrypt --output=/dev/stdout group_vars/production/vault.yml > /dev/null  # confirm vault access works before proceeding
          ansible-playbook playbooks/site.yml -i inventory/aws_ec2.yml --diff

  drift-detection:
    if: github.event_name == 'schedule'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ vars.ANSIBLE_ROLE_ARN }}
          aws-region: us-east-1
      - run: ansible-playbook playbooks/site.yml -i inventory/aws_ec2.yml --check --diff | tee drift-report.log
      - run: grep -q "changed:" drift-report.log && echo "::warning::Drift detected in production fleet"
```

## Common weak answer vs. senior answer

| Scenario | Weak answer | Senior answer |
|---|---|---|
| "How do you guarantee what gets applied matches what was reviewed?" | "We review the playbook code in the PR" | Acknowledge the real gap (no saved-plan-artifact equivalent) and mitigate via pinned commits/EE images between check-mode review and real apply, rather than assuming a code review substitutes for a plan-artifact guarantee |
| Two pipelines targeting the same fleet | "Ansible handles concurrent runs fine" | It doesn't have built-in locking — add CI-level concurrency groups scoped to the target inventory, or AWX Job Template concurrency settings |
| "How do you roll back a bad playbook run?" | "Revert the commit and re-run" | Acknowledge this reapplies old *configuration*, not necessarily undoing side effects (data migrations, package state) — genuine data-layer issues need data-layer recovery, not a playbook re-run |

## Related material
- Interview questions: [`interview-questions/08-cicd-automation.md`](../interview-questions/08-cicd-automation.md)
- Hands-on: [Lab 12 — CI/CD Pipeline](../labs/lab-12-cicd-pipeline/)
- Diagrams: [`diagrams/10-cicd-workflow.md`](../diagrams/10-cicd-workflow.md)
