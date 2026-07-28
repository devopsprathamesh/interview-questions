# Ansible Internals: Execution Model, Idempotency, and the Playbook Lifecycle

This document covers what Ansible is actually doing when you run a playbook — the execution model, why idempotency is a *contract you write*, not something Ansible guarantees for you, and the workflow internals you need to reason about correctly during an incident. This is reference material for [`interview-questions/01-ansible-core.md`](../interview-questions/01-ansible-core.md) and is exercised directly in [Lab 1](../labs/lab-01-core-workflow/) and [Lab 6](../labs/lab-06-error-handling-and-refactoring/).

> Version note: examples target `ansible-core` >= 2.16. Always confirm current behavior against the [official Ansible documentation](https://docs.ansible.com/ansible/latest/) before asserting version-specific claims in a real interview — module locations have moved into collections over several major versions, and several built-in cloud modules (the old `ec2`, `ec2_group`, etc.) have been removed from `ansible-core` entirely in favor of `amazon.aws`/`community.aws`.

## 1. The execution model, end to end

Ansible's core loop for a playbook run is:

1. **Parsing** — load the playbook YAML, resolve `roles:`/`import_playbook`/`include_tasks` references into a flattened task list.
2. **Inventory resolution** — determine the target hosts from the specified inventory (static file, dynamic inventory plugin, or `-i` override), applying any `--limit`/`--tags`/`--skip-tags` filters.
3. **Variable resolution** — merge variables from every source (defaults, group_vars, host_vars, `vars:`, `-e`, facts, role defaults) according to Ansible's fixed precedence order (see [`inventory-and-variables.md`](inventory-and-variables.md#4-variable-precedence-order)).
4. **Fact gathering** (unless `gather_facts: false`) — connect to each target host and run the `setup` module (or a facts-cache lookup) to collect real-world host state before any task runs.
5. **Task execution, per host, per task, in order** — for each task: render any Jinja2 templating in its arguments using the resolved variables, transfer the module code to the managed node (or execute locally for `local_action`/`delegate_to: localhost`), execute it, and collect the JSON result (`changed`, `failed`, `ansible_facts`, etc.).
6. **Handler notification** — any task that reports `changed: true` and has a `notify:` triggers its named handler to run, but handlers are deferred and only actually run **once**, at the end of the play (or at explicit `meta: flush_handlers` points), no matter how many tasks notified them.
7. **Result aggregation and exit** — Ansible reports a per-host summary (ok/changed/unreachable/failed/skipped) and exits non-zero if any host failed.

Everything below is a deeper look at one of these stages.

## 2. Execution strategy and parallelism

By default, Ansible uses the **`linear`** strategy: every host executes the *same* task before *any* host moves on to the next task — a synchronization barrier after every task. This is why one slow or hung host can appear to stall an entire play, even though other hosts finished that task instantly.

**`serial`** limits how many hosts are processed per "batch" (useful for a rolling deployment — do 10% of the fleet, verify, then continue):
```yaml
- hosts: webservers
  serial: "10%"
  max_fail_percentage: 20
```

**`free`** strategy removes the per-task synchronization barrier — each host races ahead through the whole task list independently, at its own pace, useful when hosts have very different task durations and you don't need strict ordering guarantees across hosts.

**`forks`** (default 5) controls how many hosts Ansible connects to **simultaneously** — this is the actual parallelism knob, independent of which strategy you're using. A `linear` strategy with `forks: 50` still processes one task at a time across all hosts, but does so by connecting to up to 50 hosts concurrently for that one task, not one host at a time.

**Why this matters in production:** a fleet of 500 hosts with the default `forks: 5` processes tasks in batches of 5 — meaning a single task with a 2-second connection overhead takes roughly 500/5 × 2s ≈ 200 seconds just in connection overhead, before any real work happens. Raising `forks` (with awareness of control-node CPU/memory and target-side connection limits) is one of the most common, highest-leverage performance fixes for large fleets — see [`interview-questions/12-performance-scale.md`](../interview-questions/12-performance-scale.md).

## 3. Idempotency — a contract you write, not a guarantee Ansible provides

**The single most important internals fact for a senior interview:** Ansible does not make your playbook idempotent. **Individual, well-written modules** are idempotent (e.g., `ansible.builtin.package` checks whether a package is already installed before doing anything), but `command`/`shell` tasks are **not** idempotent by default — Ansible has no way to know whether running `mkdir /app/data` again is safe or whether it would error. This is why `command`/`shell` tasks always report `changed: true` unless you explicitly tell Ansible otherwise:

```yaml
- name: Create a directory only if it doesn't already exist
  ansible.builtin.command: mkdir /app/data
  args:
    creates: /app/data   # skips this task entirely if /app/data already exists
```
```yaml
- name: A shell command whose "changed" status needs to be computed manually
  ansible.builtin.shell: /app/bin/migrate.sh
  register: migrate_result
  changed_when: "'Applying migration' in migrate_result.stdout"
  failed_when: migrate_result.rc not in [0, 2]   # 2 means "no migrations needed", not a failure
```

**The senior-level distinction to state clearly:** prefer purpose-built modules (`ansible.builtin.package`, `ansible.builtin.copy`, `ansible.builtin.lineinfile`, cloud-specific modules) over `command`/`shell` wherever one exists, specifically because purpose-built modules encode the "check first, only change if needed" logic internally — `command`/`shell` pushes that responsibility entirely onto you via `creates`/`removes`/`changed_when`/`failed_when`, and forgetting to do so is one of the most common sources of playbooks that "work" on a fresh host but misbehave on a second run.

## 4. Check mode and diff mode

`--check` runs the playbook **without making any real changes**, reporting what *would* change — the closest Ansible analog to `terraform plan`. `--diff` additionally shows a line-level diff for modules that support it (`template`, `copy`, `lineinfile`, etc.).

```bash
ansible-playbook site.yml --check --diff
```

**Critical limitation:** check mode is only as trustworthy as every task's own support for it. A `command`/`shell` task has no way to simulate its effect — by default, Ansible either skips it entirely in check mode or reports it inaccurately, unless the task explicitly declares `check_mode: false` (meaning "always actually run this, even under --check" — appropriate for genuinely read-only diagnostic commands) or the module has real check-mode support built in. A playbook full of unaudited `shell` tasks gives you a check-mode report that looks complete but silently omits real, unsimulated changes — a specific, common trap.

## 5. Handlers — deferred execution, not immediate

A task with `notify: restart nginx` does **not** immediately trigger the handler — it queues it. The handler named `restart nginx` runs exactly once, at the **end of the play** (or at an explicit `meta: flush_handlers` task), regardless of how many tasks in that play notified it.

```yaml
tasks:
  - name: Update nginx config
    ansible.builtin.template:
      src: nginx.conf.j2
      dest: /etc/nginx/nginx.conf
    notify: restart nginx

  - name: Update a second nginx-related file
    ansible.builtin.copy:
      src: ssl-params.conf
      dest: /etc/nginx/conf.d/ssl-params.conf
    notify: restart nginx

handlers:
  - name: restart nginx
    ansible.builtin.service:
      name: nginx
      state: restarted
```
Both tasks notify the same handler; nginx restarts **once**, not twice, at the end of the play — this batching behavior is intentional (avoid restarting a service repeatedly for multiple related config changes in the same run) but surprises engineers who expect immediate, per-task side effects.

**Common production trap:** if a later task in the same play **fails** before the play reaches its end (and before any `meta: flush_handlers`), queued handlers **never run** — a config file may have been updated, but the service was never restarted to pick it up, leaving the host in an inconsistent, half-applied state until the play is re-run to completion. This is a frequent, confusing source of "the config looks right but the service is still serving the old behavior" incidents.

## 6. Blocks, error handling, and rescue

```yaml
tasks:
  - name: Attempt the risky operation with structured error handling
    block:
      - name: Run the migration
        ansible.builtin.command: /app/bin/migrate.sh
      - name: Verify migration succeeded
        ansible.builtin.command: /app/bin/verify-migration.sh
    rescue:
      - name: Roll back on any failure in the block above
        ansible.builtin.command: /app/bin/rollback-migration.sh
      - name: Fail the play loudly after rollback, don't silently continue
        ansible.builtin.fail:
          msg: "Migration failed and was rolled back — investigate before retrying."
    always:
      - name: Always record the attempt, success or failure
        ansible.builtin.lineinfile:
          path: /var/log/migration-attempts.log
          line: "{{ ansible_date_time.iso8601 }} - migration attempted"
```
`block`/`rescue`/`always` is Ansible's structured exception handling — `rescue` only runs if something in `block` fails, and `always` runs regardless of outcome (success, failure, or even a `rescue` that itself fails). The trap to avoid: a `rescue` block that recovers from the error but doesn't **re-raise** it (via `ansible.builtin.fail`) makes the play report success even though the original operation failed and had to be rolled back — silently masking a real problem unless you deliberately fail loud after handling it.

## 7. Facts, fact caching, and `gather_facts`

Gathering facts (`setup` module) is often the single slowest part of a large playbook run, since it connects to and interrogates every host before any real task runs. Options:
- `gather_facts: false` — skip entirely if the playbook doesn't need any fact (`ansible_distribution`, `ansible_default_ipv4`, etc.) — a real speed win, but silently breaks any task/template that *does* reference a fact.
- `gather_subset:` — narrow which fact categories are collected (e.g., skip the slow hardware/virtualization probes if you only need networking facts).
- **Fact caching** (`redis`, `jsonfile`, or another cache plugin) — persist gathered facts between runs, with a TTL, so a scheduled run doesn't re-gather from scratch every single time. Introduces its own staleness risk: a cached fact can be wrong if the host changed since the cache was populated (a new IP, a resized disk) — a real, recurring troubleshooting scenario (see [`interview-questions/10-troubleshooting.md`](../interview-questions/10-troubleshooting.md)).

## 8. Connection and become — how a task actually reaches the target

Ansible connects via a **connection plugin** (`ssh` by default; `local`, `winrm`, `docker`, `kubectl` for other target types), transfers the module's Python (or PowerShell) code to the target as a temporary file, executes it there, captures JSON output over the same connection, and cleans up the temp file. `become: true` (with `become_user`/`become_method`, typically `sudo`) elevates privileges for that execution — a become failure (wrong password, sudoers misconfiguration, `requiretty` set) is a distinct failure mode from a connection failure, and the two need different diagnosis (see [`interview-questions/10-troubleshooting.md`](../interview-questions/10-troubleshooting.md)).

**`pipelining`** (an SSH connection optimization, `ansible.cfg`'s `[ssh_connection] pipelining = True`) avoids writing the module to a temp file at all, executing it directly over the SSH session instead — a meaningful speed win, but requires `requiretty` to be disabled in `sudoers` on the target, a specific, commonly-missed prerequisite.

## Common weak understanding vs. senior understanding

| Weak answer | Senior answer |
|---|---|
| "Ansible playbooks are idempotent" | Idempotency is a property of well-written modules and careful `command`/`shell` guards (`creates`, `changed_when`) — it is not automatic, and `shell`/`command` tasks are the most common source of non-idempotent behavior |
| "Handlers run right after the task that notifies them" | Handlers are deferred and batched — they run once, at the end of the play (or an explicit flush point), regardless of how many tasks notified them, and never run at all if the play fails before reaching that point |
| "`--check` mode tells you exactly what will happen" | Check mode is only as accurate as every task's own check-mode support; unaudited `command`/`shell` tasks can be silently skipped or inaccurately simulated |
| "Increase forks to make it faster" | Forks control connection concurrency; the `linear` strategy still synchronizes after every task regardless of fork count — a `free` strategy or `serial` batching may be the actually-needed lever depending on the bottleneck |

## Related material
- Interview questions: [`interview-questions/01-ansible-core.md`](../interview-questions/01-ansible-core.md)
- Hands-on: [Lab 1 — Core Workflow](../labs/lab-01-core-workflow/), [Lab 6 — Error Handling and Safe Refactoring](../labs/lab-06-error-handling-and-refactoring/)
- Diagrams: [`diagrams/01-execution-model.md`](../diagrams/01-execution-model.md), [`diagrams/02-playbook-workflow.md`](../diagrams/02-playbook-workflow.md), [`diagrams/03-module-execution-flow.md`](../diagrams/03-module-execution-flow.md), [`diagrams/05-handler-flow.md`](../diagrams/05-handler-flow.md)
