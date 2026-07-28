# Cheat Sheet: The Interview Response Framework

The ten-step structure every strong answer in this repository follows — memorize this, then apply it to any scenario you haven't seen before.

1. **Clarify blast radius** — one host, one group, one environment, or the whole fleet?
2. **Protect production** — is there an active incident risk right now?
3. **Gather evidence** — `-vvv`, `PLAY RECAP`, `ansible-inventory --graph`, logs, before changing anything.
4. **Inspect actual state** — desired state (playbook/Git) vs. live host state vs. actual AWS/Kubernetes-side state.
5. **Root cause, not symptom** — why did this happen, not just what broke.
6. **Safest remediation path** — least invasive, most reversible fix first.
7. **Validate the fix** — prove it worked (a positive-control test), don't assume.
8. **Rollback plan** — what if the fix makes things worse.
9. **Preventive controls** — a guardrail (assert, policy check, alert) so this class of failure can't recur silently.
10. **Document and communicate** — postmortem, runbook update, team knowledge-share.

## The recurring meta-lessons across this entire repository
- **Idempotency is a contract you write, not a guarantee the platform provides.** (Category 1)
- **Silent gaps are the most dangerous failure mode** — a zero-host match, a skipped conditional, a swallowed rescue, a missing alert — all fail with no error, discoverable only by deliberate, active checking. (Categories 1, 2, 10)
- **A passing check only proves what it actually checks** — `--check` mode's command/shell blindness, `no_log`'s scoped coverage, a shallow Molecule `verify.yml`, a clean drift report against unmanaged config — none of these prove more than their own narrow scope. (Categories 1, 7, 9)
- **Never trust a rarely-exercised recovery path you haven't tested** — a break-glass credential, a DR drill run only by its own author, an untested `rescue` block. (Categories 7, 11)
- **Least privilege applies to the automation identity itself, not just what it manages** — the CI runner's own IAM role and credential storage deserve the same scrutiny as the target infrastructure. (Categories 5, 7)
- **Shared, organization-wide artifacts (a role, a CI template, a policy set) deserve the *highest* testing rigor, not the lowest** — their blast radius spans every consumer simultaneously. (Categories 3, 9, 13)
- **Honesty about capability gaps beats false confidence** — Ansible's `--check` is not a Terraform plan file; there's no `mock_provider` equivalent. Say so plainly, then mitigate. (Category 8)

## Five questions that separate Senior from Staff
1. Can you explain precisely why role `vars/` beats role `defaults/` in precedence, and why that surprises almost everyone the first time?
2. Can you name the specific difference between `--check` mode's guarantee and a Terraform plan file's guarantee, and design a mitigation for the gap?
3. Can you diagnose a silently-skipped `when` condition from an undefined-variable typo, distinguishing it from a genuine platform bug?
4. Can you design a least-privilege, cross-account automation-identity architecture using explicit role-chaining, not a shared broad credential?
5. Can you design a DR process for the automation platform itself that doesn't share fate with the disaster it's meant to recover from?
