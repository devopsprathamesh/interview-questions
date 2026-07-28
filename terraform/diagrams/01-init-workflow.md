# Diagram 1: Terraform Initialization Workflow

Referenced from [`docs/terraform-internals.md`](../docs/terraform-internals.md) and [Lab 1](../labs/lab-01-core-workflow/).

```mermaid
flowchart TD
    Start([terraform init]) --> Backend{Backend configured?}
    Backend -->|Yes| BackendInit[Initialize backend\nand migrate state if requested]
    Backend -->|No| LocalBackend[Default to local backend]
    BackendInit --> Lock[Read dependency lock file]
    LocalBackend --> Lock
    Lock --> LockExists{.terraform.lock.hcl exists?}
    LockExists -->|Yes| Verify[Verify recorded provider\nversions and checksums]
    LockExists -->|No| Resolve[Resolve provider versions\nfrom required_providers constraints]
    Verify --> Download[Download provider plugins\ninto .terraform/providers]
    Resolve --> Download
    Download --> WriteLock[Write/update .terraform.lock.hcl]
    WriteLock --> Modules[Download and pin\nchild module sources]
    Modules --> Ready([Working directory ready\nfor plan/apply])
```

**Key points:**
- The lock file, once committed, makes provider resolution deterministic across every machine and CI run — `init` without `-upgrade` will never silently pick a newer provider version.
- Backend migration (local → remote, or backend config change) happens here and prompts for confirmation — always back up state first.
- Module source resolution (registry, git, local path) happens on every `init`, but is cached under `.terraform/modules` until sources change.
