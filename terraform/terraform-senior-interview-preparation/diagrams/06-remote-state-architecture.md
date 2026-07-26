# Diagram 6: Remote-State Architecture

Referenced from [`docs/state-management.md`](../docs/state-management.md) and [Lab 2](../labs/lab-02-remote-state/).

```mermaid
flowchart TD
    subgraph Engineers["Engineers / CI runners"]
        E1[Engineer laptop]
        E2[CI pipeline]
    end
    subgraph Bootstrap["Bootstrap account (separate state)"]
        IAM[Least-privilege IAM roles\nper environment]
    end
    subgraph Backend["S3 remote backend"]
        Bucket[(S3 bucket\nversioning enabled\nSSE-KMS encrypted)]
        Lock[(Native S3 conditional-write lock\nor DynamoDB lock table)]
    end

    E1 -->|assume role| IAM
    E2 -->|OIDC -> assume role| IAM
    IAM -->|GetObject/PutObject\nscoped to env path| Bucket
    IAM -->|acquire/release lock| Lock
    Bucket -->|object versions| History[(Version history\nfor recovery)]
    Bucket -.->|CloudTrail data events| Audit[Audit log]
```

**Key points:**
- The bootstrap layer that creates the state bucket/lock mechanism cannot itself use that backend — it needs its own separate (often local, carefully-controlled) state, per [Lab 2](../labs/lab-02-remote-state/).
- Access is scoped per environment path within the bucket, not bucket-wide, so a compromised dev credential can't read production state.
- Versioning provides the recovery path for corruption; CloudTrail data events provide the audit trail for "who read/wrote state and when."
