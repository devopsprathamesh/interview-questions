# Diagram 12: Module Dependency Architecture

Referenced from [`docs/module-design.md`](../docs/module-design.md#3-module-composition-and-dependency-design) and [Lab 4](../labs/lab-04-module-design/).

```mermaid
flowchart TD
    Root["Root module (environment)"] --> VPC["module.vpc"]
    Root --> SG["module.security_groups"]
    Root --> IAM["module.iam"]
    Root --> EKS["module.eks"]
    Root --> RDS["module.rds"]
    Root --> ALB["module.alb"]
    Root --> Obs["module.observability"]

    VPC -->|vpc_id, subnet_ids| SG
    VPC -->|vpc_id, subnet_ids| EKS
    VPC -->|vpc_id, subnet_ids| RDS
    VPC -->|vpc_id, subnet_ids| ALB
    SG -->|security_group_ids| EKS
    SG -->|security_group_ids| RDS
    SG -->|security_group_ids| ALB
    IAM -->|role_arns| EKS
    IAM -->|role_arns| RDS
    EKS -->|cluster_oidc_issuer| IAM
    ALB -->|target_group_arns| EKS
    EKS -->|cluster_endpoint| Obs

    classDef bad stroke:#c0392b,stroke-dasharray: 5 5
    Cycle1["module.networking\n(hypothetical)"]:::bad -.->|needs SG id| Cycle2["module.security\n(hypothetical)"]:::bad
    Cycle2 -.->|needs subnet id| Cycle1
```

**Key points:**
- Composition flows one direction from foundational (VPC, IAM) to dependent (EKS, RDS, ALB) modules — no module depends on something that depends back on it.
- The dashed red pair at the bottom illustrates the circular-dependency anti-pattern from [`docs/module-design.md`](../docs/module-design.md#3-module-composition-and-dependency-design): the fix is extracting the shared concern (e.g., both take `vpc_id` from a common ancestor) rather than having networking and security modules depend on each other directly.
- `module.eks`'s OIDC issuer feeding back into `module.iam` (for IRSA/pod identity roles) is **not** a cycle — it's a legitimate two-phase dependency resolved within a single root module's graph, since both are child modules of the same root, not two independent modules depending on each other.
