# Interview Cheat Sheet

A fast pre-interview crib sheet. For deep detailed sheets (CLI commands, roles, Vault, CI/CD, etc.) see [`cheatsheets/`](../cheatsheets/) — this page is the master index plus the one framework you should have fully memorized.

## The Interview Response Framework (memorize this)

1. **Clarify the impact and scope** — what's broken, who/what is affected right now
2. **Protect production before making changes** — stop the bleeding without a second incident
3. **Gather evidence** — `-vvv` output, facts, inventory resolution, CI/CD history
4. **Inspect playbook, inventory, variables, target-host state, and reality** — find where these diverge
5. **Identify the root cause** — not just the symptom
6. **Select the safest remediation** — check mode, `--limit`, prefer reversible actions first
7. **Validate using check mode and independent host checks** — never trust one source of truth
8. **Define rollback or recovery** — know how you'd undo it before you act
9. **Add preventive controls** — a Molecule test, a lint rule, a role interface contract
10. **Document the operational decision** — for the next engineer and for audit

Say this structure out loud in an interview even when confident — it demonstrates operational discipline, not just knowledge.

## Topic → document → questions → lab map

| Topic | Deep-dive doc | Interview questions | Primary lab(s) |
|---|---|---|---|
| Execution model, idempotency, handlers | [`ansible-internals.md`](ansible-internals.md) | [01-ansible-core](../interview-questions/01-ansible-core.md) | 1, 6 |
| Inventory, variables, facts | [`inventory-and-variables.md`](inventory-and-variables.md) | [02-inventory-variables](../interview-questions/02-inventory-variables.md) | 1, 3, 5 |
| Roles, collections, versioning | [`role-design.md`](role-design.md) | [03-roles-collections](../interview-questions/03-roles-collections.md) | 2, 11 |
| Modules, plugins, connections | [`ansible-architecture.md`](ansible-architecture.md) | [04-modules-plugins](../interview-questions/04-modules-plugins.md) | 3, 7, 9 |
| AWS/cloud integration | [`ansible-architecture.md`](ansible-architecture.md) | [05-aws-cloud-integration](../interview-questions/05-aws-cloud-integration.md) | 3, 7, 8 |
| Kubernetes/containers | [`ansible-architecture.md`](ansible-architecture.md) | [06-kubernetes-containers](../interview-questions/06-kubernetes-containers.md) | 9 |
| Security and Vault | [`security.md`](security.md) | [07-security-vault](../interview-questions/07-security-vault.md) | 4, 10 |
| CI/CD and automation | [`cicd.md`](cicd.md) | [08-cicd-automation](../interview-questions/08-cicd-automation.md) | 12 |
| Testing (Molecule) | [`testing.md`](testing.md) | [09-testing-validation](../interview-questions/09-testing-validation.md) | 11 |
| Troubleshooting | [`troubleshooting.md`](troubleshooting.md) | [10-troubleshooting](../interview-questions/10-troubleshooting.md) | 6, 7, 14 |
| HA/DR | [`ha-dr.md`](ha-dr.md) | [11-ha-dr](../interview-questions/11-ha-dr.md) | 12, 15 |
| Performance/scale | [`ansible-internals.md`](ansible-internals.md#2-execution-strategy-and-parallelism) | [12-performance-scale](../interview-questions/12-performance-scale.md) | 14 |
| Governance/policy | [`security.md`](security.md#7-static-analysis-ansible-lint) | [13-governance-policy](../interview-questions/13-governance-policy.md) | 13 |
| Migration/upgrades | [`role-design.md`](role-design.md#10-deprecation-and-upgrade-strategy) | [14-migration-upgrade](../interview-questions/14-migration-upgrade.md) | 6 |
| Leadership/architecture | all of the above, synthesized | [15-leadership-design](../interview-questions/15-leadership-design.md) | 15 |

## The five questions that separate Senior from Staff

1. "A playbook works the first time but misbehaves on a re-run — diagnose it." (idempotency as a contract you write, not a guarantee)
2. "A role change broke a dozen consuming playbooks — what's the systemic fix?" (semver, contract testing, `argument_specs`)
3. "You manage a fleet across many AWS accounts — how do you architect inventory and credentials?" (dynamic inventory, per-account roles, layered automation)
4. "A 500-host play is taking too long — fix it." (profile first; forks/strategy/fact-gathering, not a guess)
5. "How do you know your DR playbooks actually work against the secondary region?" (drills, not an untested assumption)

## Common trap answers to avoid

- "Ansible playbooks are idempotent" — only well-written modules are; `command`/`shell` are not, by default.
- "Just re-run the whole playbook" after a partial failure — use the `.retry` file / `--limit`, understand why it failed first.
- "Use Ansible Vault" as a complete answer to secrets — the vault *password* itself needs real key management.
- "`--check` mode tells you exactly what will happen" — only as accurate as every task's own check-mode support.
- "Ansible is confusing about variables" — walk the actual, fixed precedence order instead.

## Related material
- Full cheat sheets: [`cheatsheets/`](../cheatsheets/)
- Mock interviews: [`mock-interviews/`](../mock-interviews/)
