# Diagram 7: State-Locking Workflow

Referenced from [`docs/state-management.md`](../docs/state-management.md#3-state-locking) and [Lab 3](../labs/lab-03-state-locking/).

```mermaid
sequenceDiagram
    participant P1 as Pipeline A (plan/apply)
    participant Lock as Lock store (DynamoDB / S3 conditional write)
    participant P2 as Pipeline B (plan/apply)

    P1->>Lock: Attempt to acquire lock
    Lock-->>P1: Lock acquired (LockID, Who, Created)
    P2->>Lock: Attempt to acquire lock
    Lock-->>P2: Rejected: lock held by P1\n(Who, Operation, Created shown)
    Note over P2: P2 fails fast with actionable error\ninstead of corrupting state
    P1->>P1: Complete apply, write state
    P1->>Lock: Release lock
    P2->>Lock: Retry: attempt to acquire lock
    Lock-->>P2: Lock acquired
    P2->>P2: Proceed safely

    Note over P1,Lock: Failure mode: P1 is killed (SIGKILL)\nbefore releasing lock
    P1--xLock: Process dies, unlock never called
    P2->>Lock: Attempt to acquire lock
    Lock-->>P2: Rejected: stale lock
    Note over P2: Human confirms P1 is truly dead\nvia CI job status / lock metadata,\nthen runs terraform force-unlock
```

**Key points:**
- A rejected lock acquisition is the *safe* outcome — it fails fast rather than allowing a concurrent write that could corrupt state.
- Stale locks (from a killed process) require human confirmation before `force-unlock`; forcing an unlock on a still-running process reintroduces the exact race the lock exists to prevent.
- CI concurrency controls (a single mutex/queue per state) prevent contention from happening in the first place — see [`docs/cicd.md`](../docs/cicd.md).
