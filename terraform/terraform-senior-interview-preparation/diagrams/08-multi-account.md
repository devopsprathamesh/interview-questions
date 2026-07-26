# Diagram 8: Multi-Account AWS Deployment

Referenced from [`docs/terraform-architecture.md`](../docs/terraform-architecture.md#8-multi-account-strategies-landing-zones-and-account-vending) and [Lab 15](../labs/lab-15-enterprise-capstone/).

```mermaid
flowchart TD
    subgraph Identity["CI/Identity account"]
        OIDC[OIDC provider trust]
        CIRole[CI execution role]
    end

    subgraph Mgmt["Management / Org account"]
        SCP[Service Control Policies]
        Vending[Account vending pipeline]
    end

    subgraph Dev["Dev account"]
        DevRole[terraform-execution role]
        DevState[(Dev state - S3 path /dev)]
    end

    subgraph Staging["Staging account"]
        StgRole[terraform-execution role]
        StgState[(Staging state - S3 path /staging)]
    end

    subgraph Prod["Production account"]
        ProdRole[terraform-execution role]
        ProdState[(Prod state - S3 path /production)]
    end

    OIDC --> CIRole
    CIRole -->|sts:AssumeRole| DevRole
    CIRole -->|sts:AssumeRole\napproval gate| StgRole
    CIRole -->|sts:AssumeRole\napproval gate + review| ProdRole
    Vending -.->|provisions with baseline guardrails| Dev
    Vending -.-> Staging
    Vending -.-> Prod
    SCP -.->|non-negotiable guardrails\napplied org-wide| Dev
    SCP -.-> Staging
    SCP -.-> Prod
```

**Key points:**
- A single CI identity assumes different, narrowly-scoped roles per target account — no account-specific long-lived credentials exist anywhere.
- SCPs enforce guardrails (no public S3, approved regions, mandatory encryption) regardless of what any individual account's IAM policies allow — defense in depth.
- Each account has its own state path/backend scoping, so a plan targeting dev cannot structurally touch production resources.
