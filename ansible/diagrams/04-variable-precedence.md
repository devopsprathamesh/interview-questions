# Diagram 4: Variable Precedence Order

Referenced from [`docs/inventory-and-variables.md` §4](../docs/inventory-and-variables.md#4-variable-precedence-order).

```mermaid
flowchart BT
    A["1. Role defaults/main.yml\n(lowest - the public, overridable interface)"] --> B["2-8. Inventory and playbook\ngroup_vars / host_vars layers"]
    B --> C["9. Facts / cached facts"]
    C --> D["10-12. Play vars / vars_prompt / vars_files"]
    D --> E["13. Role vars/main.yml\n(higher than defaults - often surprising)"]
    E --> F["14-17. Block vars / task vars /\ninclude_vars / set_fact"]
    F --> G["18. Role and include parameters"]
    G --> H["19. Extra vars -e\n(HIGHEST - always wins, no exceptions)"]

    style A fill:#e8f4f8
    style H fill:#f8d7da
```

**Key points:**
- Extra vars (`-e`) always win, which is exactly why an accidental or careless `-e` in a CI job can silently override a carefully-set environment-specific value with no warning.
- Role `defaults/` (lowest) vs. role `vars/` (much higher, step 13) is the single most common source of "why isn't my override taking effect" confusion — see [`docs/role-design.md` §1](../docs/role-design.md#1-standard-role-structure).
