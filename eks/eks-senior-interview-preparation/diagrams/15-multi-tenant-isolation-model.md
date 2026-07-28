# Diagram 15: Multi-Tenant Cluster Isolation Model

```mermaid
flowchart TB
    subgraph Cluster["Shared EKS Cluster"]
        subgraph NST[Namespace: team-a]
            RBACA[RBAC: team-a RoleBinding]
            QUOTAA[ResourceQuota + LimitRange]
            NETPOLA[NetworkPolicy: deny cross-namespace by default]
            PODSA[Pods - team-a]
        end
        subgraph NST2[Namespace: team-b]
            RBACB[RBAC: team-b RoleBinding]
            QUOTAB[ResourceQuota + LimitRange]
            NETPOLB[NetworkPolicy: deny cross-namespace by default]
            PODSB[Pods - team-b]
        end
        POLICY[Cluster-wide Kyverno/Gatekeeper policies<br/>enforced identically for every tenant]
        NODEPOOL[Optionally: dedicated node pools per tenant<br/>via taints/tolerations for noisy-neighbor isolation]
    end

    POLICY -.governs.-> NST
    POLICY -.governs.-> NST2
    NODEPOOL -.isolates compute for.-> NST
```

## Key points
- Namespace-level isolation combines four layers: RBAC (who can act), ResourceQuota/LimitRange (how much they can consume), NetworkPolicy (what they can reach), and cluster-wide admission policy (baseline rules every tenant is subject to identically).
- Namespace isolation alone does not isolate compute — a noisy-neighbor workload in one namespace can still starve nodes shared with another tenant's namespace unless resource requests/limits and/or dedicated node pools are also in place.
- Cluster-wide policy (Kyverno/Gatekeeper) should apply uniformly across tenants — a tenant-specific policy exception is a deliberate, reviewed decision, not a default.
