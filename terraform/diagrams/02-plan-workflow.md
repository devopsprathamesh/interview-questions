# Diagram 2: Terraform Plan Workflow

Referenced from [`docs/terraform-internals.md`](../docs/terraform-internals.md).

```mermaid
flowchart TD
    Start([terraform plan]) --> Lock[Acquire state lock]
    Lock --> ReadState[Read current state]
    ReadState --> Refresh[Refresh: call ReadResource RPC\nfor each managed resource]
    Refresh --> Graph[Build resource dependency graph\nfrom config + state]
    Graph --> Walk[Walk graph in dependency order]
    Walk --> Diff{Compare desired config\nvs refreshed state}
    Diff -->|No difference| NoOp[No-op]
    Diff -->|Attribute differs, not ForceNew| Update[Planned: update in place]
    Diff -->|ForceNew attribute differs| Replace[Planned: destroy + create]
    Diff -->|Resource in config, not in state| Create[Planned: create]
    Diff -->|Resource in state, not in config| Destroy[Planned: destroy]
    Update --> Unknowns[Propagate unknown values\nto dependents]
    Create --> Unknowns
    Replace --> Unknowns
    Unknowns --> Output[Render plan output\n+/- ~ annotations]
    Output --> SavePlan{-out= specified?}
    SavePlan -->|Yes| SaveFile[Write binary plan file\nfor later apply]
    SavePlan -->|No| Unlock[Release state lock]
    SaveFile --> Unlock
    Unlock --> End([Plan complete])
```

**Key points:**
- Refresh happens as an integrated part of plan by default; `-refresh=false` skips it and trusts existing state.
- A saved plan file (`-out=`) locks in the exact set of changes, including resolved variable values, for later `apply` — critical for the CI/CD pattern of "review a plan, then apply exactly that plan."
- Unknown values (from not-yet-created resources) propagate through the graph and are shown as `(known after apply)`.
