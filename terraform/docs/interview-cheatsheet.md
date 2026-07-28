# Interview Cheat Sheet

A fast pre-interview crib sheet. For deep detailed sheets (CLI commands, state commands, lifecycle meta-arguments, etc.) see [`cheatsheets/`](../cheatsheets/) — this page is the master index plus the one framework you should have fully memorized.

## The Interview Response Framework (memorize this)

Every scenario question should be answered in this order:

1. **Clarify the impact and scope** — what's broken, who/what is affected right now
2. **Protect production before making changes** — stop the bleeding without a second incident
3. **Gather evidence** — logs, state, plan output, cloud console, CI/CD history
4. **Inspect configuration, plan, state, provider, and cloud reality** — find where these four diverge
5. **Identify the root cause** — not just the symptom
6. **Select the safest remediation** — prefer reversible, low-blast-radius actions first
7. **Validate using plan and independent cloud checks** — never trust one source of truth
8. **Define rollback or recovery** — know how you'd undo it before you act
9. **Add preventive controls** — policy, CI gate, module contract, or documentation change
10. **Document the operational decision** — for the next engineer and for audit

Say this structure out loud in an interview even when you're confident of the answer — it demonstrates operational discipline, not just knowledge.

## Topic → document → questions → lab map

| Topic | Deep-dive doc | Interview questions | Primary lab(s) |
|---|---|---|---|
| Language internals, meta-arguments, workflow | [`terraform-internals.md`](terraform-internals.md) | [01-terraform-core](../interview-questions/01-terraform-core.md) | 1, 3 |
| State: locking, corruption, splitting, drift | [`state-management.md`](state-management.md) | [02-state-management](../interview-questions/02-state-management.md) | 2, 3, 6, 7, 14 |
| Modules: interface design, versioning, composition | [`module-design.md`](module-design.md) | [03-modules](../interview-questions/03-modules.md) | 4, 5, 7 |
| Providers: aliases, auth, upgrades, air-gapped | [`terraform-architecture.md`](terraform-architecture.md) | [04-providers](../interview-questions/04-providers.md) | 8, 9 |
| AWS/enterprise architecture, multi-account/region | [`terraform-architecture.md`](terraform-architecture.md) | [05-aws-architecture](../interview-questions/05-aws-architecture.md) | 5, 8, 15 |
| Kubernetes/EKS | (Phase 3 EKS content, this doc + `terraform-architecture.md`) | [06-kubernetes-eks](../interview-questions/06-kubernetes-eks.md) | 9 |
| Security and secrets | [`security.md`](security.md) | [07-security](../interview-questions/07-security.md) | 10, 13 |
| CI/CD and automation | [`cicd.md`](cicd.md) | [08-cicd](../interview-questions/08-cicd.md) | 12 |
| Testing and validation | [`testing.md`](testing.md) | [09-testing](../interview-questions/09-testing.md) | 11 |
| Troubleshooting and incidents | [`troubleshooting.md`](troubleshooting.md) | [10-troubleshooting](../interview-questions/10-troubleshooting.md) | 3, 6, 7, 14 |
| HA/DR | [`ha-dr.md`](ha-dr.md) | [11-ha-dr](../interview-questions/11-ha-dr.md) | 8, 9, 15 |
| Performance and scale | [`state-management.md`](state-management.md#12-state-splitting-for-blast-radius-reduction-the-5000-resource-problem) | [12-performance-scale](../interview-questions/12-performance-scale.md) | 14 |
| Governance and policy as code | [`security.md`](security.md#9-policy-as-code) | [13-governance](../interview-questions/13-governance.md) | 13 |
| Migration, import, upgrade | [`state-management.md`](state-management.md#9-terraform-state-subcommands--what-each-is-actually-for), [`module-design.md`](module-design.md#9-upgrade-and-deprecation-strategies) | [14-migration-upgrade](../interview-questions/14-migration-upgrade.md) | 6, 7 |
| Leadership and architecture decisions | all of the above, synthesized | [15-leadership-design](../interview-questions/15-leadership-design.md) | 15 |

## The five questions that separate Senior from Staff

If you only prep five things, prep the ability to answer these with a real framework, not a definition:

1. "Your plan wants to replace a production database after a provider upgrade — walk me through it." (state, providers, ForceNew, non-prod validation discipline)
2. "A team's module change broke 40 consumers — what's the systemic fix?" (semver, deprecation windows, contract testing, `moved` blocks)
3. "You operate 100 AWS accounts across multiple regions — describe the architecture." (assume-role, state separation, landing zones, policy as code, pipeline matrices)
4. "A 5,000-resource state file takes 20 minutes to plan — redesign it." (state splitting along ownership/change-frequency boundaries, layered architecture)
5. "How do you know your DR plan actually works?" (scheduled drills with measured RTO/RPO, not an untested diagram)

## Common trap answers to avoid

- "Just re-apply" — for almost any failure scenario, this is never the first move. Diagnose first.
- "Mark it `sensitive`" — as a complete answer to secrets-in-state. It's a UI control, not a storage control.
- "Split into more modules" — as a complete answer to blast radius. Child modules aren't state boundaries.
- "Use workspaces" — as a complete answer to environment isolation. Workspaces share configuration; production isolation needs separate root modules/backends.
- "Force-unlock it" — as a first response to a lock timeout, without confirming the original process is actually dead.

## Related material
- Full cheat sheets: [`cheatsheets/`](../cheatsheets/)
- Mock interviews: [`mock-interviews/`](../mock-interviews/)
