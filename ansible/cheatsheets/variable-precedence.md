# Cheat Sheet: Variable Precedence (Lowest to Highest)

The full, official 19-level order. Memorize the traps, not just the list: **`-e` always wins**, and **role `vars/` beats role `defaults/`** (commonly assumed backwards).

| # | Source | Notes |
|---|---|---|
| 1 | Command-line values (e.g., `-u user`) | Lowest — almost never wins in practice |
| 2 | Role `defaults/main.yml` | The intended, overridable interface — [Question 12](../interview-questions/02-inventory-variables.md#question-12-the-role-that-couldnt-be-overridden) |
| 3 | Inventory file/script group vars | |
| 4 | Inventory `group_vars/all` | |
| 5 | Playbook `group_vars/all` | |
| 6 | Inventory `group_vars/*` | More specific group |
| 7 | Playbook `group_vars/*` | |
| 8 | Inventory `host_vars/*` | |
| 9 | Playbook `host_vars/*` | |
| 10 | Host facts / cached `set_fact` | |
| 11 | Play vars | `vars:` block in a play |
| 12 | Play `vars_prompt` | |
| 13 | Play `vars_files` | |
| 14 | Role vars (`vars/main.yml`) | **Higher than role defaults** — easy to get backwards |
| 15 | Block vars | |
| 16 | Task vars | |
| 17 | `include_vars` | |
| 18 | `set_fact` / registered vars | Runtime-computed, high precedence |
| 19 | Extra vars (`-e` / `--extra-vars`) | **Always wins**, full stop — [Question 16](../interview-questions/02-inventory-variables.md#question-16-the--e-that-nobody-remembered-setting) |

## Key traps
- **Lists never merge across precedence levels** — a shorter list at a higher-precedence source fully replaces a longer one, it doesn't combine. [Question 3](../interview-questions/01-ansible-core.md#question-3-the-loop-that-quietly-skipped-half-its-work)
- **Dicts also default to replace**, not merge, unless `hash_behaviour = merge` is set globally in `ansible.cfg` (rare, and changes behavior for the *entire* codebase — a broad, risky switch).
- **Role `vars/` > role `defaults/`** — `defaults` is the overridable interface; `vars` is role-internal and wins over anything a caller sets in `group_vars`/`host_vars`.
- **`argument_specs.yml`** validates a role's declared inputs at call time — the closest Ansible equivalent to Terraform's typed module variables. [Question 26](../interview-questions/03-roles-collections.md#question-26-the-readme-that-lied)
- **Magic variables** (`hostvars`, `group_names`, `inventory_hostname`) are not part of this precedence chain — they're always computed/available, not "set" at any level.
