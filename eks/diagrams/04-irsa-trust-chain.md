# Diagram 4: IRSA Trust Chain

```mermaid
flowchart LR
    OIDC[EKS Cluster OIDC Provider - registered once in IAM] -->|trust relationship| ROLE[IAM Role]
    ROLE -->|Condition: namespace + ServiceAccount subject must match| TRUST{Trust Policy Evaluation}
    SA[Kubernetes ServiceAccount<br/>annotated: eks.amazonaws.com/role-arn] -.associated with.-> POD[Pod using this ServiceAccount]
    POD -->|projected OIDC token mounted by API server| TOKEN[Short-lived, audience-scoped token]
    TOKEN -->|sts:AssumeRoleWithWebIdentity| TRUST
    TRUST -->|if conditions match| CREDS[Temporary AWS Credentials]
    CREDS --> POD
    TRUST -.rejects if subject mismatch.-> DENY[AccessDenied]
```

## Key points
- The chain has four links: OIDC provider → IAM role trust policy → ServiceAccount annotation → pod's projected token. Every link must be correct for least-privilege to actually hold.
- The trust policy's `Condition` block must check both the OIDC provider **and** the specific namespace/ServiceAccount subject — omitting the subject check lets any ServiceAccount in the cluster assume the role.
- Tokens are short-lived and audience-scoped (via `TokenRequest`), automatically rotated by the kubelet — not a static, long-lived credential.
- A pod without an IRSA-annotated ServiceAccount silently falls back to the **node's** IAM role instead — see [`docs/iam-irsa.md`](../docs/iam-irsa.md) §2 and §7.
