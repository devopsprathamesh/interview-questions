# Diagram 15: Fleet-Scale Execution Strategy

Referenced from [`docs/ansible-internals.md` §2](../docs/ansible-internals.md#2-execution-strategy-and-parallelism) and [`interview-questions/12-performance-scale.md`](../interview-questions/12-performance-scale.md).

```mermaid
flowchart TD
    Play["Play against 500 hosts"] --> Strategy{Strategy?}
    Strategy -->|linear - default| Linear["Every host completes Task N\nbefore ANY host starts Task N+1\n(synchronization barrier per task)"]
    Strategy -->|free| Free["Each host races ahead through\nits own task list independently"]
    Strategy -->|serial: 10%| Serial["Process fleet in batches of 10%,\nverify max_fail_percentage\nbetween batches"]

    Linear --> Forks{forks setting}
    Free --> Forks
    Serial --> Forks
    Forks -->|"default: 5"| SlowConn["500 hosts / 5 forks =\n100 sequential connection batches\nper task - real overhead at scale"]
    Forks -->|"raised, e.g. 50"| FastConn["500 hosts / 50 forks =\n10 batches - much faster,\nwatch control-node CPU/memory\nand target-side connection limits"]
```

**Key points:**
- `strategy` and `forks` are independent levers — `linear` with high `forks` still synchronizes after every task, just with more hosts processed concurrently within each task.
- `serial` with `max_fail_percentage` is the safety mechanism for large rollouts — a systemic bad change halts after a small percentage of the fleet fails, rather than grinding through everything before anyone notices.
- Profiling (the `ansible.posix.profile_tasks` callback) should come **before** tuning any of these — a small number of genuinely slow tasks (unnecessary fact-gathering, a control-node-side lookup plugin call per host) often dominates far more than raw host count or fork settings.
