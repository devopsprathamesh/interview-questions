# High Availability and Disaster Recovery

For Ansible specifically, HA/DR splits into two distinct questions: **is the automation control plane itself resilient** (AWX/Automation Platform HA, control node redundancy), and **does Ansible help or hinder recovering the infrastructure it manages** during a real incident. This document backs [`interview-questions/11-ha-dr.md`](../interview-questions/11-ha-dr.md) and is exercised in [Lab 15](../labs/lab-15-enterprise-capstone/).

## 1. Control-plane HA: AWX / Ansible Automation Platform

A single AWX/Tower instance is a single point of failure for **all** automation — if it's down, nobody can launch a Job Template, including an emergency one needed to respond to the very incident that might have taken it down. Production deployments run:
- **Multiple AWX/Automation Platform nodes** in a cluster, with jobs distributed across them.
- **A highly-available PostgreSQL backend** (the job history, credentials, inventory data all live there) — this database is arguably more critical to protect than the AWX application nodes themselves, since the application nodes are largely stateless/replaceable while the database holds everything.
- **Execution nodes** that can run jobs even if a control node is temporarily unavailable, depending on topology.

**The parallel to the companion Terraform repository's "the recovery tool shares fate with what it's recovering" lesson**: if your only path to run an emergency remediation playbook is through an AWX instance that's *also* down (e.g., it was hosted in the same region/AZ experiencing the incident), you have no automation path during the exact event you need it most. **Mitigation:** a documented, tested fallback — the ability to run critical playbooks directly via CLI (with credentials sourced from a break-glass path) against a known-good execution environment, independent of AWX being reachable.

## 2. Push automation's dependency on the control node reaching targets

Standard push-based Ansible requires the control node (or AWX execution node) to have network connectivity to every managed host. During a network partition affecting that connectivity specifically (not the hosts themselves, which may be fine), push automation is simply unusable — this is a distinct failure mode from the hosts being down.

**`ansible-pull`** (see [`ansible-architecture.md` §11](ansible-architecture.md#11-push-vs-pull-automation)) sidesteps this specific failure mode: each host independently pulls and applies its own configuration from a Git repo on a schedule, requiring no inbound connectivity from a central control node at all — a genuine architectural resilience trade-off worth naming when a design specifically needs to tolerate control-node-to-target network partitions, at the cost of losing centralized, on-demand "run this specific thing right now" control.

## 3. Does configuration management help you recover infrastructure during a DR event?

Yes, directly — this is one of Ansible's clearest DR value propositions: if your DR strategy (per the companion Terraform repository's tiers) involves standing up compute in a secondary region, the **same playbooks/roles** that configure primary-region hosts should configure the DR region's hosts identically, applied via the same execution environment, differing only in inventory/variables (target region, endpoint URLs). A DR region's hosts configured by a hand-maintained, drifted-over-time separate process is exactly the anti-pattern the companion repository warns against for infrastructure — the same warning applies to configuration.

**The state/inventory nuance specific to Ansible:** unlike Terraform, Ansible has no persistent "state" tracking what it previously did — every run re-converges based on current playbook/role content against current target-host reality. This means a DR region's hosts, configured by the identical playbook, will converge to the identical intended configuration **regardless of whether they were ever previously configured** — a genuine advantage for DR specifically, since there's no "state file" that itself needs replicating/restoring the way Terraform's state does. The actual DR dependency is on the **playbook/role source repository and the execution environment image** being available in/reachable from the DR region — if your Git hosting or your container registry is *also* down, you can't pull the playbooks or the EE image to run them.

## 4. What Ansible does not solve for DR

- **Data recovery** — identical to the Terraform lesson: configuration management manages configuration, not application data. A database's DR strategy (replication, backup/restore) is a separate concern Ansible doesn't address by running a playbook.
- **DNS/traffic cutover** — the actual traffic-shifting step during a failover is typically outside Ansible's scope (a Route 53 change, a load balancer reconfiguration) — though Ansible *can* orchestrate that step too, via the relevant cloud modules, if you choose to include it in your failover playbook.

## 5. HA/DR drills — the same discipline, applied to configuration management

An untested "we'd just run the playbook against the DR region" plan is exactly as much of a hypothesis as an untested Terraform DR plan. Schedule real drills: actually run the full configuration playbook set against a DR-region target (even a temporary, scaled-down one) on a regular cadence, and measure how long it actually takes end-to-end — not just whether it theoretically should work.

## Common weak answer vs. senior answer

| Scenario | Weak answer | Senior answer |
|---|---|---|
| "How does Ansible help with DR?" | "We'd just run the playbooks against the new region" | The same playbooks/roles applied to DR-region inventory converge identically regardless of prior state — but the real dependency is on the source repo and execution environment being reachable, which itself needs its own resilience plan |
| AWX is down during an incident | "We'd wait for it to come back" | A documented, tested break-glass CLI path (with break-glass credentials) to run critical playbooks directly, independent of the AWX control plane being reachable |
| Network partition to managed hosts | "Configuration management doesn't work during a partition" | `ansible-pull` specifically exists for this — each host converges independently on its own schedule, requiring no inbound connectivity from a control node |

## Related material
- Interview questions: [`interview-questions/11-ha-dr.md`](../interview-questions/11-ha-dr.md)
- Hands-on: [Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/)
- Diagrams: [`diagrams/13-awx-architecture.md`](../diagrams/13-awx-architecture.md)
