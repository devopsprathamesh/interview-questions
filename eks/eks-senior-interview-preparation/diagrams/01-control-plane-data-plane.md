# Diagram 1: EKS Control Plane and Data Plane Architecture

```mermaid
flowchart TB
    subgraph AWS["AWS-Managed Account (invisible to you)"]
        API[API Server - Multi-AZ]
        ETCD[(etcd - AWS-managed, backed up automatically)]
        SCHED[Scheduler]
        CM[Controller Manager]
        API --> ETCD
        API --> SCHED
        API --> CM
    end

    subgraph VPC["Your VPC"]
        subgraph AZ1["AZ-1"]
            N1[Node]
        end
        subgraph AZ2["AZ-2"]
            N2[Node]
        end
        subgraph AZ3["AZ-3"]
            N3[Node]
        end
        ENDPOINT[EKS-managed ENIs for API access]
    end

    CLIENT[kubectl / CI / GitOps controller] -->|Public and/or Private Endpoint| API
    API <-->|kubelet, watch/report state| N1
    API <-->|kubelet, watch/report state| N2
    API <-->|kubelet, watch/report state| N3
    API -.provisions.-> ENDPOINT
```

## Key points
- The control plane (API server, etcd, scheduler, controller manager) runs in an AWS-owned account — you never see or manage its underlying compute, and etcd backup/durability is entirely AWS's responsibility.
- The data plane (nodes) runs in your VPC, across AZs you choose — multi-AZ resilience here is your design responsibility, not automatic.
- All interaction — human or automated — goes through the API server; there is no other path to change or observe cluster state.
- Endpoint access mode (public/private/both) controls where `CLIENT` can even reach the API server from — see [`docs/eks-architecture.md`](../docs/eks-architecture.md) §3.
