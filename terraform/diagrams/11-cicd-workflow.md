# Diagram 11: CI/CD Workflow

Referenced from [`docs/cicd.md`](../docs/cicd.md) and [Lab 12](../labs/lab-12-cicd-pipeline/).

```mermaid
flowchart TD
    Dev[Developer opens PR] --> Fmt["terraform fmt -check"]
    Fmt --> Val["terraform validate"]
    Val --> Lint[TFLint]
    Lint --> Sec[Security scan\nCheckov / tfsec / Trivy]
    Sec --> Policy["Policy as code\nOPA / Conftest"]
    Policy --> Plan["terraform plan\n-out=tfplan"]
    Plan --> Artifact[Upload plan as\nCI artifact]
    Artifact --> Comment[Post plan summary\nas PR comment]
    Comment --> Review{Human review\n+ approval}
    Review -->|Changes requested| Dev
    Review -->|Approved + merged| Gate{Environment\nprotection gate}
    Gate -->|Dev| AutoApply["terraform apply tfplan"]
    Gate -->|Production| Manual[Manual approval\nrequired reviewer]
    Manual --> ConcurrencyCheck{Concurrency lock\navailable for this state?}
    ConcurrencyCheck -->|No, another run active| Queue[Queue / fail fast]
    ConcurrencyCheck -->|Yes| ApplySaved["terraform apply tfplan\n(exact reviewed plan)"]
    ApplySaved --> Verify[Post-apply verification\n+ drift-detection schedule]
```

**Key points:**
- The plan that gets applied is the **exact saved plan artifact** that was reviewed — not a freshly regenerated plan at apply time — closing the gap between "what was approved" and "what was applied."
- Concurrency controls ensure only one pipeline run can hold the lock for a given state at a time, preventing the race this diagram's lock-contention counterpart (Diagram 7) describes.
- Production applies require a distinct, stricter approval gate than dev/staging, enforced by CI environment protection rules, not convention alone.
