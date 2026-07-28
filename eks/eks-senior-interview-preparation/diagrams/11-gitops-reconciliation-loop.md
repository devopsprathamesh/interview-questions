# Diagram 11: GitOps Reconciliation Loop (ArgoCD)

```mermaid
sequenceDiagram
    participant Git as Git Repo (source of truth)
    participant Argo as ArgoCD Controller (in-cluster)
    participant API as Kubernetes API Server
    participant Human as Manual kubectl edit

    loop Continuous reconciliation
        Argo->>Git: Poll/webhook for latest commit
        Argo->>API: Compare live state vs. desired state
        alt Drift detected
            Argo->>API: Apply diff to converge (if auto-sync enabled)
        end
    end

    Human->>API: Out-of-band kubectl patch
    Note over API: Live state now diverges from Git
    Argo->>API: Next reconciliation pass detects drift
    Argo->>API: Reverts to Git-declared state (if self-heal enabled)
```

## Key points
- ArgoCD runs inside the cluster and continuously pulls/reconciles — a fundamentally different model from a CI pipeline pushing `kubectl apply` from outside.
- Any manual, out-of-band change to a GitOps-managed resource gets silently reverted on the next reconciliation pass (if self-heal is enabled) — Git is the actual, enforced source of truth.
- This gives genuinely continuous drift detection/correction, stronger than periodic `plan`/playbook-based drift checking. See [`docs/cicd-gitops.md`](../docs/cicd-gitops.md) §1–2.
