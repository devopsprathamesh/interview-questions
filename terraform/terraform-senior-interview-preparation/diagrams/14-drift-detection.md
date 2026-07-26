# Diagram 14: Drift Detection and Reconciliation

Referenced from [`docs/state-management.md`](../docs/state-management.md#11-manual-infrastructure-changes-and-drift) and [Lab 14](../labs/lab-14-drift-and-recovery/).

```mermaid
flowchart TD
    Schedule[Scheduled drift-detection\npipeline run] --> PlanOnly["terraform plan -detailed-exitcode"]
    PlanOnly --> Code{Exit code}
    Code -->|0| Clean[No drift - no action]
    Code -->|1| Fail[Plan error - alert on-call]
    Code -->|2| Diff[Drift detected]
    Diff --> Investigate[Check CloudTrail / audit logs\nfor who/what changed it]
    Investigate --> Decision{Was the change\nintentional?}
    Decision -->|Yes, should persist| UpdateConfig[Update Terraform config\nto match new reality]
    Decision -->|Yes, but should be reverted| RevertApply["terraform apply\n(reverts drifted attribute)"]
    Decision -->|No longer Terraform's concern| IgnoreChanges["Add lifecycle.ignore_changes\nfor that specific attribute"]
    Decision -->|Resource entirely unmanaged| ImportBlock["Adopt via import block"]
    UpdateConfig --> Verify[Re-run plan: expect no diff]
    RevertApply --> VerifyOutage{Revert safe\nright now?}
    VerifyOutage -->|No| Schedule2[Schedule revert for\nmaintenance window]
    VerifyOutage -->|Yes| Verify
    IgnoreChanges --> Verify
    ImportBlock --> Verify
```

**Key points:**
- `-detailed-exitcode` is what turns `terraform plan` into a machine-readable drift signal for a scheduled pipeline, distinguishing "no changes" from "error" from "changes present."
- Every drift finding routes through a deliberate decision (revert / adopt-into-config / ignore / import) informed by *why* the change happened — never a reflexive re-apply.
- Reverting drift that was actually an emergency manual fix (e.g., a scaled-up RDS instance during an incident) without checking timing/impact first can cause a second outage.
