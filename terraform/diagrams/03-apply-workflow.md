# Diagram 3: Terraform Apply Workflow

Referenced from [`docs/terraform-internals.md`](../docs/terraform-internals.md) and [Lab 1](../labs/lab-01-core-workflow/).

```mermaid
flowchart TD
    Start([terraform apply]) --> PlanSource{Plan file provided?}
    PlanSource -->|Yes, saved plan| Validate[Validate plan still matches\ncurrent state serial/lineage]
    PlanSource -->|No| NewPlan[Generate a fresh plan]
    Validate --> Stale{State changed\nsince plan was saved?}
    Stale -->|Yes| Abort([Abort: stale plan error])
    Stale -->|No| Confirm
    NewPlan --> Confirm{Interactive approval\nor auto-approve?}
    Confirm -->|Rejected| Cancelled([Apply cancelled])
    Confirm -->|Approved| Lock[Acquire state lock]
    Lock --> Graph[Walk apply graph]
    Graph --> Parallel[Execute independent resource\noperations in parallel]
    Parallel --> RPC[Call CreateResource /\nUpdateResource / DeleteResource RPC]
    RPC --> Incremental[Write state incrementally\nafter each successful operation]
    Incremental --> More{More resources\nin graph?}
    More -->|Yes| Parallel
    More -->|No| Serial[Bump state serial]
    Serial --> Unlock[Release state lock]
    Unlock --> End([Apply complete])
    RPC -->|Provider error| Partial[Partial apply:\nstate reflects completed ops only]
    Partial --> Unlock
```

**Key points:**
- Applying a saved plan file re-validates the state's serial/lineage first — this is what prevents applying stale intent against state that moved on.
- State is written incrementally, resource by resource — an interrupted or partially-failed apply never loses track of what actually succeeded.
- Independent branches of the graph run in parallel (`-parallelism`, default 10); a missing `depends_on` for a runtime-only dependency shows up here as intermittent failures.
