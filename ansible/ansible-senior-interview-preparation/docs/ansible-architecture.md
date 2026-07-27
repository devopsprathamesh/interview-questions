# Ansible Architecture: Modules, Plugins, Connections, and Enterprise Deployment

This document covers two related topic areas: **module/plugin/connection engineering** (how Ansible actually talks to the systems it manages) and **enterprise architecture** (how automation is organized, credentialed, and scaled across teams and environments). It backs [`interview-questions/04-modules-plugins.md`](../interview-questions/04-modules-plugins.md) and [`interview-questions/05-aws-cloud-integration.md`](../interview-questions/05-aws-cloud-integration.md), and is exercised in [Lab 3](../labs/lab-03-dynamic-inventory/), [Lab 7](../labs/lab-07-aws-configuration-management/), and [Lab 15](../labs/lab-15-enterprise-capstone/).

## Part A — Modules, Plugins, and Connections

### 1. Module sources: builtin vs. collections

Since Ansible 2.10, the vast majority of modules live in separately-versioned **collections**, not `ansible-core` itself. `ansible.builtin` (the small, stable core module set — `copy`, `template`, `service`, `package`, etc.) ships with `ansible-core`; everything else (`amazon.aws.ec2_instance`, `kubernetes.core.k8s`, `community.mysql.mysql_db`) is a separate collection you install via `requirements.yml`.

```yaml
# requirements.yml
collections:
  - name: amazon.aws
    version: ">=7.0.0,<8.0.0"
  - name: community.aws
    version: ">=5.0.0,<6.0.0"
  - name: kubernetes.core
    version: ">=3.0.0,<4.0.0"
```
```bash
ansible-galaxy collection install -r requirements.yml
```

**Why this matters operationally:** a playbook referencing `amazon.aws.ec2_instance` will fail with "module not found" if that collection isn't installed on the control node/execution environment running it — a common source of "works on my laptop, fails in CI" when a developer has collections installed globally but the CI execution environment's `requirements.yml` was never updated to match. **Commit and pin `requirements.yml` exactly like a Terraform lock file** — floating/unpinned collection versions reintroduce the same unreviewed-version-drift risk covered in the companion Terraform repository's provider-version material.

### 2. Connection plugins

| Plugin | Use case |
|---|---|
| `ssh` (default) | Standard Linux/Unix remote management |
| `local` | Run directly on the control node (e.g., a task that only makes sense to run where Ansible itself is executing) |
| `winrm` | Windows targets |
| `docker` | Configuring a running container directly (common in Molecule's own test driver — see [`testing.md`](testing.md)) |
| `kubectl` / the `kubernetes.core` collection's connection options | Executing inside a Kubernetes pod |

Connection plugin choice is usually set per-host or per-group (`ansible_connection: docker` in inventory), not per-task — mixing connection types within a single playbook run against different inventory groups is normal and expected (e.g., configuring both real EC2 hosts over `ssh` and a local Molecule test container over `docker` using the same role, different inventories).

### 3. Callback plugins — customizing and integrating output

Callback plugins hook into Ansible's event stream (task start, task result, playbook stats) to customize output or integrate with external systems:
```ini
# ansible.cfg
[defaults]
callbacks_enabled = ansible.posix.profile_tasks, community.general.json
```
`profile_tasks` reports per-task timing (a first-line tool for the performance investigation covered in [`interview-questions/12-performance-scale.md`](../interview-questions/12-performance-scale.md)); a JSON callback lets you pipe structured run results into a log aggregator or CI system rather than parsing human-readable stdout — the equivalent of `terraform show -json` for machine consumption.

### 4. Lookup plugins, filters, and tests — the three kinds of "helper" you'll confuse at first

- **Lookup plugins** (`lookup('file', 'path')`, `lookup('env', 'HOME')`, `lookup('aws_ssm', '/app/db/password')`) — pull data from **outside** Ansible's variable space, evaluated on the **control node**.
- **Filters** (`| default(...)`, `| to_json`, `| map('extract', ...)`) — transform a value you already have, Jinja2-native.
- **Tests** (`is defined`, `is failed`, `is version('2.0', '>=')`) — boolean checks used in `when:`/`assert` conditions.

The practical distinction that trips people up: a **lookup** actually reaches out (to a file, an API, a secrets manager) and can fail/be slow; a **filter** is a pure, local data transformation with no I/O. Reaching for `lookup('pipe', 'some-external-command')` where a filter would do is a common, avoidable source of slow, control-node-dependent plays.

### 5. Custom modules — when to actually write one

Writing a custom module (Python, returning proper JSON with `changed`/`failed` and idempotent check-then-act logic) is justified when: no existing module/collection covers the need, **and** the operation is common enough across your fleet to be worth the investment, **and** you need real idempotency/check-mode support that a `command`/`shell` task fundamentally can't provide cleanly. For a one-off, rarely-run operation, a well-guarded `command`/`shell` task (with `creates`/`changed_when`) is usually the pragmatic choice; a custom module is an investment appropriate for something dozens of playbooks across the organization will call.

### 6. Execution environments — the air-gapped/reproducibility answer

An **Execution Environment** (a container image built with `ansible-builder`, containing `ansible-core`, the required collections, and their Python dependencies, all pinned) is the modern answer to "does this control node have the exact right versions of everything." It's the direct Ansible analog of the Terraform provider mirror / dependency lock file discipline — instead of hoping every engineer's laptop and every CI runner independently has matching `ansible-core`/collection/Python-library versions, you build one image once, pin it, and every run (local dev via `ansible-navigator`, CI, AWX/Automation Platform) uses the identical environment.
```yaml
# execution-environment.yml (ansible-builder input)
version: 3
images:
  base_image:
    name: registry.example.com/ansible-automation-platform-24/ee-minimal-rhel9:latest
dependencies:
  galaxy: requirements.yml
  python: requirements.txt
```
For air-gapped environments, this image (plus a private Automation Hub or offline collection mirror) is the complete answer — exactly mirroring the Terraform provider-mirror pattern for regulated/disconnected networks.

## Part B — Enterprise Architecture

### 7. AWX / Ansible Automation Platform architecture

At team scale, raw `ansible-playbook` CLI runs from individual laptops don't provide credential management, RBAC, scheduling, or audit trail. AWX (open source) / Ansible Automation Platform (commercial) provide:
- **Job Templates** — a named, reusable "playbook + inventory + credentials + extra vars" bundle, launchable via UI, API, or webhook — the Ansible analog of a CI/CD pipeline's saved plan/apply job definition.
- **Credentials** — stored, access-controlled (never plaintext in a playbook or inventory), injected into a job's environment/connection only for the duration of that run — SSH keys, cloud API credentials, Vault passwords, all centrally managed rather than scattered across individual engineers' `~/.ssh` and shell profiles.
- **RBAC** — who can launch which Job Template against which inventory, mirroring the "distributed ownership within guardrails" pattern from the companion Terraform repository's account-vending material.
- **Execution Environments** — every Job Template runs inside a specific, pinned EE (see Part A §6), not whatever happens to be on a shared Tower/AWX host.
- **Surveys** — a structured, validated input form for a Job Template's extra vars, giving less-technical requesters (e.g., an on-call engineer running a "restart this specific service" template) a safe, constrained interface instead of raw CLI access.

### 8. Layered automation architecture

Directly analogous to the Terraform foundation/platform/application layering:
```text
Baseline layer     — OS hardening, users/groups, monitoring agents, common packages
    (roles: security-baseline, common — applied to EVERY host, rarely changes)

Platform layer      — web server / database / container runtime configuration
    (roles: webserver, database — applied per host role, changes moderately)

Application layer   — app-specific config, deployment, feature flags
    (changes frequently, owned by application teams)
```
Just as with Terraform state boundaries, this layering should map to **separate playbooks/Job Templates with separate schedules and separate blast radii** — a baseline hardening run across the whole fleet is a different, higher-blast-radius operation than an application team's frequent app-config deploy, and should not share a single monolithic playbook that makes every run touch everything.

### 9. Repository architecture: monorepo vs. repo-per-team

Same trade-off as the companion Terraform repository's environments discussion: a monorepo (all roles/playbooks together) simplifies cross-cutting role updates and keeps a consistent baseline; repo-per-team gives a stronger natural access-control boundary (who can even propose a change to the production-facing playbook) at the cost of coordinating shared-role updates across repos. Neither is universally correct — decide based on actual team ownership boundaries, not convention alone.

### 10. Credential and multi-account/multi-cloud patterns

Exactly mirroring the Terraform provider-aliasing-per-account pattern: a central automation identity (AWX/Automation Platform, or a CI identity) assumes narrowly-scoped, per-account/per-cloud credentials for the specific job at hand — never one broad, shared credential used across every environment. For AWS specifically, this means per-environment IAM roles assumed via `assume_role` in the dynamic inventory / cloud module configuration, not one static access key used everywhere.

### 11. Push vs. pull automation

**Push** (AWX/Tower/CI dispatches `ansible-playbook` runs against target hosts) is the default, centrally-controlled model — you decide when and what runs.

**Pull** (`ansible-pull`, each host fetches and applies its own configuration from a Git repo on a schedule, typically via cron) inverts this — useful for very large, ephemeral, or intermittently-connected fleets where a central control node reaching out to every host isn't practical. The trade-off: you lose the centralized "one clear run, one clear result" visibility of push-based execution, gaining instead a fleet that's eventually consistent with the repo's current state, each host converging independently on its own schedule.

## Common weak answer vs. senior answer

| Scenario | Weak answer | Senior answer |
|---|---|---|
| "Module not found" in CI but works locally | "Reinstall Ansible" | Check `requirements.yml` pinning against what's actually installed in the CI execution environment — a collection version/pinning mismatch, not an Ansible installation problem |
| Managing credentials for 50 AWS accounts | "Store each account's access key in a separate CI secret" | Centralize via a single automation identity assuming narrowly-scoped, per-account roles — never per-account static long-lived keys scattered across secret stores |
| "How do you keep Ansible + collections consistent across every engineer's laptop and CI?" | "Everyone runs `pip install ansible` and hopes for the best" | Build a pinned Execution Environment image (`ansible-builder`) that every run — local via `ansible-navigator`, CI, AWX — uses identically |
| Should baseline OS hardening and app deploys share one playbook? | "Sure, one playbook is simpler" | Separate layers with separate blast radii and schedules — a baseline hardening run and a frequent app deploy have very different risk profiles and shouldn't be coupled |

## Related material
- Interview questions: [`interview-questions/04-modules-plugins.md`](../interview-questions/04-modules-plugins.md), [`interview-questions/05-aws-cloud-integration.md`](../interview-questions/05-aws-cloud-integration.md)
- Hands-on: [Lab 3 — Dynamic Inventory](../labs/lab-03-dynamic-inventory/), [Lab 7 — AWS Configuration Management](../labs/lab-07-aws-configuration-management/), [Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/)
- Diagrams: [`diagrams/06-dynamic-inventory.md`](../diagrams/06-dynamic-inventory.md), [`diagrams/13-awx-architecture.md`](../diagrams/13-awx-architecture.md)
