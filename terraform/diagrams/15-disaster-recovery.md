# Diagram 15: Disaster Recovery Workflow

Referenced from [`docs/ha-dr.md`](../docs/ha-dr.md) and [Lab 15](../labs/lab-15-enterprise-capstone/).

```mermaid
flowchart TD
    Incident[Primary region/account\nincident declared] --> Assess[Assess: partial degradation\nvs full regional loss]
    Assess -->|Partial| Failover[Shift traffic within\nprimary region if possible]
    Assess -->|Full loss| DRDecision{DR strategy in place}
    DRDecision -->|Pilot light| Scale[Scale up standby resources\nvia terraform apply\nsame module set, DR region vars]
    DRDecision -->|Warm standby| TrafficShift[Shift traffic via\nRoute 53 / Global Accelerator]
    DRDecision -->|Backup/restore| Restore[Provision infra via terraform apply\n+ restore data from backups]
    Scale --> DataCheck[Verify replicated data\nrecency: RPO check]
    TrafficShift --> DataCheck
    Restore --> DataCheck
    DataCheck --> Validate[Run smoke tests /\nhealth checks against DR]
    Validate --> Cutover[Complete cutover:\nupdate DNS / confirm traffic]
    Cutover --> Monitor[Monitor DR environment\nas new primary]
    Monitor --> Postmortem[Post-incident review]
    Postmortem --> Failback{Primary region\nrestored?}
    Failback -->|Yes| PlanFailback[Plan controlled failback\nsame process, reversed]
    Failback -->|No| StayDR[Continue operating\nfrom DR region]
```

**Key points:**
- Which DR strategy (backup/restore, pilot light, warm standby, active/active) is in place determines whether recovery is a `terraform apply` against pre-provisioned-but-scaled-down infrastructure, a traffic shift, or a from-scratch provision-plus-restore — see [`docs/ha-dr.md`](../docs/ha-dr.md) for the RTO/RPO trade-offs of each.
- Because the DR region uses the *same* tested module set (per Diagram 9), the "provision infrastructure" step is a known-good, already-validated operation during an incident, not first-time-ever code.
- Failback is treated as a full, deliberate second exercise of this same workflow in reverse — never an assumption that traffic silently reverts on its own.
