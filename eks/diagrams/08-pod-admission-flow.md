# Diagram 8: Pod Admission Flow

```mermaid
flowchart LR
    REQ[kubectl apply / controller creates Pod] --> AUTHN[Authentication]
    AUTHN --> AUTHZ[Authorization - RBAC]
    AUTHZ --> MUTATE[Mutating Admission Webhooks<br/>e.g. Kyverno auto-inject defaults]
    MUTATE --> PSA{Pod Security Admission<br/>baseline/restricted/privileged}
    PSA -->|pass| VALIDATE[Validating Admission Webhooks<br/>Kyverno/OPA Gatekeeper custom policy]
    PSA -->|fail| REJECT1[Rejected]
    VALIDATE -->|pass| ETCD[(Persisted to etcd)]
    VALIDATE -->|fail| REJECT2[Rejected]
    ETCD --> SCHEDULE[Scheduler places pod on a node]

    WEBHOOKDOWN[Policy engine webhook unreachable] -.failurePolicy: Fail.-> BLOCKALL[All admission blocked cluster-wide]
    WEBHOOKDOWN -.failurePolicy: Ignore.-> BYPASSALL[All policy enforcement silently bypassed]
```

## Key points
- Every pod creation passes through this full chain — authentication, RBAC authorization, mutating webhooks, Pod Security Admission, then validating webhooks — before ever reaching etcd or the scheduler.
- Kyverno can mutate (inject defaults) as well as validate; OPA Gatekeeper's Rego-based Constraints are primarily validating.
- The policy engine's own availability is now a dependency of every admission-controlled operation — `failurePolicy` choice is a genuine, consequential trade-off. See [`docs/security.md`](../docs/security.md) §4 and [`docs/governance-policy.md`](../docs/governance-policy.md) §2.
