# Diagram 14: Multi-AZ / Multi-Region HA and DR Topology

```mermaid
flowchart TB
    subgraph Primary["Primary Region"]
        direction TB
        PCTRL[EKS Control Plane - AWS multi-AZ managed]
        subgraph PAZ1[AZ-1]
            PN1[Nodes] --- PP1[App Pods]
        end
        subgraph PAZ2[AZ-2]
            PN2[Nodes] --- PP2[App Pods]
        end
        PARGO[ArgoCD Controller]
        PDB[(Database - primary)]
    end

    subgraph DR["DR Region"]
        direction TB
        DCTRL[EKS Control Plane]
        subgraph DAZ1[AZ-1]
            DN1[Nodes - standing by or scaled down]
        end
        DARGO[ArgoCD Controller - independent instance]
        DDB[(Database - replica)]
    end

    GIT[Shared Git Repo - source of truth] --> PARGO
    GIT --> DARGO
    PDB -.async replication.-> DDB
    R53[Route 53 - failover routing] -.normal.-> Primary
    R53 -.failover.-> DR
```

## Key points
- Both regions' clusters reconcile from the *same* Git source independently — configuration convergence is automatic as long as each region's GitOps controller is healthy and reachable, per [`docs/ha-dr.md`](../docs/ha-dr.md) §6.
- Data (databases, PV contents) has no "just re-apply from Git" story — it needs genuine replication/backup-restore (Velero, database-level replication).
- The DR region needs its **own** GitOps controller instance — if only the primary region runs ArgoCD, you lose your reconciliation mechanism exactly when the primary region (and its ArgoCD) is what's down. See [`docs/ha-dr.md`](../docs/ha-dr.md) §7.
- Within each region, workload replicas must be explicitly spread across AZs (topology spread constraints) — the control plane's own multi-AZ resilience doesn't extend to workload placement automatically.
