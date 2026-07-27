# Diagram 14: Drift Detection and Reconciliation

Referenced from [`docs/cicd.md` §6](../docs/cicd.md#6-drift-detection) and [Lab 14](../labs/lab-14-troubleshooting-and-recovery/).

```mermaid
flowchart TD
    Schedule["Scheduled pipeline run\n(cron)"] --> CheckRun["ansible-playbook site.yml\n--check --diff"]
    CheckRun --> Parse["Parse output for any\n'changed' task results"]
    Parse --> Found{Any changed\nreported?}
    Found -->|no| Clean[No drift - no action]
    Found -->|yes| Investigate["Investigate: who/what changed\nthe host outside Ansible?"]
    Investigate --> Decision{Was the change\nintentional?}
    Decision -->|Yes, should persist| UpdatePlaybook["Update the playbook/role\nto match the new reality"]
    Decision -->|Yes, but should revert| RealApply["Real (non-check) apply\nreverts it - check timing/impact first"]
    Decision -->|No longer Ansible's concern| Exclude["Remove the task/attribute\nfrom this role's scope entirely"]
    UpdatePlaybook --> Verify["Re-run --check: expect no diff"]
    RealApply --> Verify
    Exclude --> Verify
```

**Key points:**
- This mirrors the Terraform drift decision framework exactly, adapted to Ansible: check-mode detects the divergence, but the *decision* (update the source of truth, revert, or deliberately exclude) still requires human judgment about intent.
- Because check mode's accuracy depends entirely on every task supporting it (see [`docs/ansible-internals.md` §4](../docs/ansible-internals.md#4-check-mode-and-diff-mode)), a fleet with unaudited `command`/`shell` tasks will under-report drift here — a real, distinct limitation from Terraform's plan accuracy.
