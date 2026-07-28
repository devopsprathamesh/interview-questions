# Diagram 2: Playbook Run Workflow

Referenced from [`docs/ansible-internals.md`](../docs/ansible-internals.md#1-the-execution-model-end-to-end).

```mermaid
flowchart TD
    Start([ansible-playbook site.yml]) --> Parse[Parse playbook YAML,\nflatten roles/imports/includes]
    Parse --> Inventory[Resolve inventory\napply --limit/--tags filters]
    Inventory --> Vars[Merge variables per\nprecedence order]
    Vars --> Facts{gather_facts?}
    Facts -->|true| GatherFacts[Connect to each host,\nrun setup module or read fact cache]
    Facts -->|false| TaskLoop
    GatherFacts --> TaskLoop[For each task, per host,\nin strategy order]
    TaskLoop --> Template[Render Jinja2 in task args\nusing resolved variables]
    Template --> Transfer[Transfer module code\nto managed host]
    Transfer --> Execute[Execute module,\ncollect JSON result]
    Execute --> Notify{Task reports changed\nand has notify?}
    Notify -->|yes| Queue[Queue handler]
    Notify -->|no| NextTask
    Queue --> NextTask{More tasks?}
    NextTask -->|yes| TaskLoop
    NextTask -->|no| Flush[Flush queued handlers\nonce, at end of play]
    Flush --> Report[Report per-host summary:\nok/changed/unreachable/failed/skipped]
```

**Key points:**
- Variable merging happens once, per host, before any task executes — this is why a variable precedence mistake affects every task uniformly, not just one.
- Handlers are collected throughout the play but only flushed once, at the natural end (or an explicit `meta: flush_handlers`) — see [Diagram 5](05-handler-flow.md).
