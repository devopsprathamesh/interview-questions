# Diagram 12: Progressive Delivery — Canary via Argo Rollouts

```mermaid
flowchart TD
    START[New image version pushed via Git commit] --> ROLLOUT[Rollout controller creates canary ReplicaSet]
    ROLLOUT --> STEP1[Shift 10% traffic to canary]
    STEP1 --> ANALYSIS1{AnalysisRun:<br/>query Prometheus for error rate/latency}
    ANALYSIS1 -->|pass| STEP2[Shift 50% traffic]
    ANALYSIS1 -->|fail| ROLLBACK[Automatic rollback to stable version]
    STEP2 --> ANALYSIS2{AnalysisRun}
    ANALYSIS2 -->|pass| FULL[Shift 100% traffic - promote canary to stable]
    ANALYSIS2 -->|fail| ROLLBACK
    FULL --> DONE[Old stable ReplicaSet scaled down]
```

## Key points
- A standard Kubernetes `Deployment` has no traffic-weighted canary or automated metric-driven rollback — this requires the `Rollout` custom resource (Argo Rollouts) or Flagger.
- Promotion/rollback decisions are automated against real metrics (error rate, latency), not a human watching a dashboard and deciding.
- During an active canary, "what's serving production traffic right now" is only fully described by the Rollout's live status, not the Git-declared end-state alone. See [`docs/cicd-gitops.md`](../docs/cicd-gitops.md) §3 and §7.
