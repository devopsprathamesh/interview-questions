# Diagram 5: Handler Notification and Flush Flow

Referenced from [`docs/ansible-internals.md` §5](../docs/ansible-internals.md#5-handlers--deferred-execution-not-immediate).

```mermaid
flowchart TD
    T1["Task 1: update nginx.conf\nnotify: restart nginx"] --> Q{changed?}
    Q -->|yes| Queued["'restart nginx' queued\n(not run yet)"]
    Q -->|no| T2
    Queued --> T2["Task 2: update ssl-params.conf\nnotify: restart nginx"]
    T2 --> Q2{changed?}
    Q2 -->|yes| QueuedAgain["'restart nginx' already queued\n(no duplicate)"]
    Q2 -->|no| T3
    QueuedAgain --> T3["Task 3: unrelated task"]
    T3 --> Fails{Task 3 fails?}
    Fails -->|yes| NeverRuns["Handlers NEVER run -\nplay stopped before reaching\nthe end / a flush point"]
    Fails -->|no| EndOfPlay[End of play reached]
    EndOfPlay --> FlushPoint[Flush queued handlers ONCE]
    FlushPoint --> RestartNginx["'restart nginx' executes\n- exactly one restart,\nnot two"]
```

**Key points:**
- Two tasks notifying the same handler still only trigger **one** execution of it, at flush time — not once per notifying task.
- If any task after the notifying ones fails before a flush point, **queued handlers never run at all** — a config file can be updated with the service never restarted to pick it up, a frequent, confusing incident (see [`docs/troubleshooting.md`](../docs/troubleshooting.md)).
