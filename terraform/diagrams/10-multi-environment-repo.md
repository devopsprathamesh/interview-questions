# Diagram 10: Multi-Environment Repository Structure

Referenced from [`docs/terraform-architecture.md`](../docs/terraform-architecture.md#9-repository-architecture-monorepo-vs-repository-per-environment) and [Lab 5](../labs/lab-05-multi-environment/).

```mermaid
flowchart TD
    Repo["Monorepo root"] --> Modules["modules/ (shared, versioned internally)"]
    Repo --> Envs["environments/"]
    Envs --> Dev["dev/\nown backend config\nown tfvars\nrelaxed approval"]
    Envs --> Staging["staging/\nown backend config\nown tfvars\nrequires plan review"]
    Envs --> Prod["production/\nown backend config\nown tfvars\nrequires manual approval"]

    Modules -->|module source, pinned version| Dev
    Modules -->|module source, pinned version| Staging
    Modules -->|module source, pinned version| Prod

    Dev -->|promote via PR,\nsame module version bump| Staging
    Staging -->|promote via PR,\nafter validation| Prod

    CI["CI/CD pipeline"] -->|path-based trigger| Dev
    CI -->|path-based trigger + approval gate| Staging
    CI -->|path-based trigger + mandatory approval| Prod
```

**Key points:**
- Each environment directory has its own backend configuration and state — not a shared workspace-selected state — so isolation doesn't depend on remembering to select the right workspace.
- Promotion between environments is a version bump (module source ref, image tag, config value) moved through a reviewed PR, not a copy-paste of raw resources.
- CI approval gates tighten by environment: dev may auto-apply, staging requires a plan review, production requires explicit manual approval (see [`docs/cicd.md`](../docs/cicd.md)).
