# Diagram 9: Multi-Environment Repository/Inventory Structure

Referenced from [Lab 5](../labs/lab-05-multi-environment/) and [`docs/inventory-and-variables.md` §2](../docs/inventory-and-variables.md#2-groups-group_vars-and-host_vars).

```mermaid
flowchart TD
    Roles["roles/ (shared, versioned, applied identically everywhere)"] --> Dev
    Roles --> Staging
    Roles --> Production

    subgraph Dev["environments/dev/"]
        DevInv["inventory (aws_ec2.yml,\nfilters: tag:Environment=dev)"]
        DevVars["group_vars/all.yml\n(smaller instance counts, relaxed settings)"]
    end

    subgraph Staging["environments/staging/"]
        StgInv["inventory"]
        StgVars["group_vars/all.yml"]
    end

    subgraph Production["environments/production/"]
        ProdInv["inventory"]
        ProdVars["group_vars/all.yml\n(HA settings, stricter hardening)"]
    end

    Playbook["playbooks/site.yml\n(identical for every environment)"] --> Dev
    Playbook --> Staging
    Playbook --> Production

    CI["CI/CD pipeline"] -->|"path/branch-based trigger"| Dev
    CI -->|"requires review"| Staging
    CI -->|"requires manual approval"| Production
```

**Key points:**
- The **same playbook and roles** run against every environment — environment-specific behavior comes entirely from `group_vars`, never from `when:` branching inside the playbook itself.
- Each environment has its own inventory (dynamic, scoped by tag) and its own variable overrides — isolation comes from structurally separate inventories, not a shared inventory with an environment "switch."
- CI approval gates tighten by environment exactly as in the companion Terraform repository's pattern.
