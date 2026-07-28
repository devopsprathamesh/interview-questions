# Diagram 9: Multi-Region Terraform Deployment

Referenced from [`docs/terraform-architecture.md`](../docs/terraform-architecture.md#2-multi-account-multi-region-assume-role-architecture) and [`docs/ha-dr.md`](../docs/ha-dr.md).

```mermaid
flowchart LR
    subgraph Config["Shared configuration (single module set)"]
        Modules[modules/vpc, modules/eks, ...]
    end

    subgraph PrimaryRegion["us-east-1 (primary)"]
        ProvPrimary["provider aws (default)\nregion = us-east-1"]
        ResPrimary[VPC, EKS, RDS primary]
        StatePrimary[(State: /production/us-east-1)]
    end

    subgraph DRRegion["us-west-2 (DR)"]
        ProvDR["provider aws.dr_region\nregion = us-west-2"]
        ResDR[VPC, EKS, RDS read replica]
        StateDR[(State: /production/us-west-2)]
    end

    Modules --> ProvPrimary --> ResPrimary --> StatePrimary
    Modules --> ProvDR --> ResDR --> StateDR
    ResPrimary -.->|cross-region replication\nRDS / S3 / DynamoDB global tables| ResDR
    Pipeline[CI/CD pipeline matrix\nregion = [us-east-1, us-west-2]] --> ProvPrimary
    Pipeline --> ProvDR
```

**Key points:**
- The same tested module set is parameterized by region via provider aliases and a pipeline matrix — never a hand-maintained, drifted-over-time separate copy of the configuration for the DR region.
- Each region has independent state, so a bad apply in one region cannot corrupt or lock the other.
- Data-layer replication (RDS cross-region read replicas, S3 replication, DynamoDB global tables) is a separate concern from infrastructure deployment and must be explicitly modeled, not assumed.
