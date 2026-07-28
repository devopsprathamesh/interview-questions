# Diagram 10: CI/CD Workflow for Ansible

Referenced from [`docs/cicd.md`](../docs/cicd.md) and [Lab 12](../labs/lab-12-cicd-pipeline/).

```mermaid
flowchart TD
    Dev[Developer opens PR] --> Lint["ansible-lint + yamllint"]
    Lint --> Syntax["ansible-playbook --syntax-check"]
    Syntax --> Molecule["Molecule test\n(every changed role, Docker driver)"]
    Molecule --> CheckMode["ansible-playbook --check --diff\nagainst staging inventory"]
    CheckMode --> PostReview[Post check-mode diff\nas PR comment]
    PostReview --> Review{Human review + approval}
    Review -->|Changes requested| Dev
    Review -->|Approved + merged| Gate{Environment\nprotection gate}
    Gate -->|Dev| AutoRun["ansible-playbook site.yml\n(auto, same pinned commit/EE)"]
    Gate -->|Production| Manual[Manual approval\nrequired reviewer]
    Manual --> ConcurrencyCheck{Concurrency group\navailable for this inventory?}
    ConcurrencyCheck -->|No, another run active| Queue[Queue]
    ConcurrencyCheck -->|Yes| Apply["ansible-playbook site.yml --diff\n(same pinned commit + EE as check-mode step)"]
    Apply --> Verify[Post-run verification +\nscheduled drift-detection check-mode run]
```

**Key points:**
- Ansible has no saved-plan-artifact equivalent — the pipeline's own discipline (pinning the exact commit and Execution Environment image between the check-mode review step and the real apply step) is what substitutes for that guarantee.
- Concurrency groups are scoped to the target inventory/environment, preventing two runs from racing against the same fleet — Ansible itself has no built-in per-inventory lock.
