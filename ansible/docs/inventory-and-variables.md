# Inventory, Variables, and Facts

Getting inventory and variable precedence wrong is the single most common source of "it works on my machine but the pipeline applied the wrong config" incidents in real Ansible estates. This document is reference material for [`interview-questions/02-inventory-variables.md`](../interview-questions/02-inventory-variables.md) and is exercised in [Lab 1](../labs/lab-01-core-workflow/), [Lab 3](../labs/lab-03-dynamic-inventory/), and [Lab 5](../labs/lab-05-multi-environment/).

## 1. Static vs. dynamic inventory

**Static inventory** (INI or YAML) is fine for a small, stable, hand-maintained set of hosts:
```yaml
# inventory/hosts.yml
all:
  children:
    webservers:
      hosts:
        web-01.internal:
        web-02.internal:
      vars:
        http_port: 8080
    dbservers:
      hosts:
        db-01.internal:
```
It fails immediately at real fleet scale: it doesn't reflect reality the moment an Auto Scaling Group launches or terminates an instance, and it becomes yet another thing to keep manually in sync with your actual cloud state — precisely the drift problem covered in depth for infrastructure state in the companion Terraform repository, applied here to *inventory* instead of resource state.

**Dynamic inventory** (a plugin, e.g., `amazon.aws.aws_ec2`) queries the cloud provider live, every run, building the host list and group membership from real tags/filters:
```yaml
# inventory/aws_ec2.yml
plugin: amazon.aws.aws_ec2
regions: [us-east-1]
filters:
  tag:Environment: production
  instance-state-name: running
keyed_groups:
  - key: tags.Role
    prefix: role
  - key: placement.availability_zone
    prefix: az
compose:
  ansible_host: private_ip_address
```
This means the inventory is **never stale** in the way a hand-maintained file can be — see [Lab 3](../labs/lab-03-dynamic-inventory/) for the full setup. The trade-off: a dynamic inventory query is a live API call on every run, adding latency and a new external dependency (if the cloud API is unreachable, you have no inventory at all) — a real, if usually minor, availability consideration.

## 2. Groups, group_vars, and host_vars

```text
inventory/
├── aws_ec2.yml
├── group_vars/
│   ├── all.yml
│   ├── webservers.yml
│   └── role_database.yml      # matches the "role_" prefix from keyed_groups above
└── host_vars/
    └── db-01.internal.yml
```
Ansible automatically loads `group_vars/<groupname>.yml` and `host_vars/<hostname>.yml` for any group/host present in the resolved inventory — no explicit `vars_files:` needed. This is the mechanism behind environment-specific configuration (see [Lab 5](../labs/lab-05-multi-environment/)): `group_vars/production.yml` sets one value, `group_vars/dev.yml` sets another, and the same playbook run against either inventory picks up the right one automatically, with zero playbook-level branching logic.

## 3. Patterns and limiting scope

```bash
ansible-playbook site.yml --limit webservers
ansible-playbook site.yml --limit "webservers:!web-03.internal"   # all webservers except one
ansible-playbook site.yml --limit "role_database:&az_us-east-1a"  # intersection of two groups
ansible-playbook site.yml --limit @retry_hosts.txt                 # only hosts that failed last run
```
`--limit` is the primary tool for narrowing a run's blast radius — the Ansible analog to Terraform's `-target`, with a similar caution: routine reliance on `--limit` for "just fix this one host quickly" without ever running a full, unlimited play risks silent divergence between what the limited runs have actually applied and what a full run would produce, exactly mirroring the `-target` risk discussed in the companion Terraform repository.

## 4. Variable precedence order

This is one of the most-tested pieces of Ansible knowledge at the senior level, precisely because getting it wrong causes confusing, hard-to-diagnose "why is my variable not taking effect" bugs. From **lowest to highest** precedence (later entries win):

1. Role `defaults/main.yml` (the lowest-priority, "safe fallback" layer)
2. Inventory file group vars
3. Inventory `group_vars/all`
4. Playbook `group_vars/all`
5. Inventory `group_vars/<group>`
6. Playbook `group_vars/<group>`
7. Inventory `host_vars/<host>`
8. Playbook `host_vars/<host>`
9. Host facts / cached facts
10. Play `vars:`
11. Play `vars_prompt:`
12. Play `vars_files:`
13. Role `vars/main.yml` (**note: higher precedence than role defaults, but lower than most other things** — a common source of confusion, since both live "inside the role")
14. Block vars
15. Task vars
16. `include_vars`
17. `set_fact` / registered vars
18. Role (and include) parameters
19. Extra vars (`-e` on the command line — **always wins**, regardless of anything else)

**The two facts worth memorizing for an interview:**
- **`-e` (extra vars) always wins**, full stop — this is Ansible's deliberate "escape hatch" for overriding anything, anywhere, from the command line, which is exactly why it's dangerous in CI if used carelessly (an `-e` typo can silently override a carefully-set environment-specific value with no warning).
- **Role `defaults` are the lowest-precedence, role `vars` are much higher** — a module author (or module *consumer*) who expects `roles/webserver/vars/main.yml` to be easily overridden by a caller the way `defaults/main.yml` is will be surprised when it isn't; `vars/main.yml` is for values the role author considers close to fixed/internal, `defaults/main.yml` is the actual public, overridable interface.

## 5. Magic variables and facts

`ansible_facts` (or the flattened top-level `ansible_*` variables, depending on `INJECT_FACTS_AS_VARS`), `hostvars`, `groups`, `group_names`, `inventory_hostname`, `ansible_play_hosts` — these are populated by Ansible itself, not by any `vars:` you write. `hostvars` in particular is how one host's task can reference another host's facts/variables — e.g., a load balancer configuration task referencing every web server's private IP:
```yaml
- name: Configure upstream servers
  ansible.builtin.template:
    src: upstream.conf.j2
    dest: /etc/nginx/conf.d/upstream.conf
  vars:
    upstream_ips: "{{ groups['webservers'] | map('extract', hostvars, 'ansible_default_ipv4', 'address') | list }}"
```

## 6. Fact caching — precision vs. staleness trade-off

```ini
# ansible.cfg
[defaults]
fact_caching = jsonfile
fact_caching_connection = /tmp/ansible_facts_cache
fact_caching_timeout = 86400   # 24 hours
```
Caching facts avoids re-gathering (a real, sometimes significant, per-run cost — see [`ansible-internals.md` §7](ansible-internals.md#7-facts-fact-caching-and-gather_facts)) but introduces a staleness window: if a host's real state changes (resized, re-IP'd, a package installed out-of-band) within that TTL, a play relying on a fact for a conditional (`when: ansible_distribution_major_version == "8"`) can make a decision based on stale information. Choose the TTL deliberately based on how often the underlying facts actually change for your fleet, not a copy-pasted default.

## 7. Secrets in variables — the Vault boundary

Any variable that's a secret (a database password, an API key) should be Ansible Vault-encrypted **at the variable level**, not left in plaintext group_vars — see [`security.md`](security.md) for the full treatment. The common, recommended pattern is a `vault.yml` file per group/host, fully encrypted, referenced indirectly by a plaintext `vars.yml` that only contains variable *names* pointing at vault-defined values:
```yaml
# group_vars/production/vars.yml (plaintext, safe to commit)
db_password: "{{ vault_db_password }}"

# group_vars/production/vault.yml (fully Vault-encrypted)
vault_db_password: "actual-secret-value"
```
This indirection means `git diff`/`git blame` on the plaintext file is still useful (you can see *that* `db_password` exists and is referenced, without needing to decrypt anything), while the actual secret value stays encrypted at rest.

## Common weak answer vs. senior answer

| Scenario | Weak answer | Senior answer |
|---|---|---|
| "A variable isn't taking the value I expect" | "Ansible variables are unpredictable" | Walk the actual precedence order — check whether an `-e`, a role `vars/main.yml`, or a higher-precedence `host_vars` entry is silently winning |
| Managing environment-specific config | "Use `when:` conditionals branching on an environment variable inside the playbook" | Use `group_vars/<environment>.yml` per inventory so the playbook itself never branches — the same playbook run against a different inventory naturally picks up the right values |
| Inventory at real fleet scale | "Keep a big static inventory file, update it when instances change" | Dynamic inventory (e.g., `amazon.aws.aws_ec2`) queried live against tags — inventory is never stale relative to cloud reality |
| Secrets in variables | "Just don't commit the file with secrets in it" | Vault-encrypt the specific secret variables, using the vars/vault split pattern so non-secret context stays diffable |

## Related material
- Interview questions: [`interview-questions/02-inventory-variables.md`](../interview-questions/02-inventory-variables.md)
- Hands-on: [Lab 1](../labs/lab-01-core-workflow/), [Lab 3 — Dynamic Inventory](../labs/lab-03-dynamic-inventory/), [Lab 5 — Multi-Environment Architecture](../labs/lab-05-multi-environment/)
- Diagrams: [`diagrams/04-variable-precedence.md`](../diagrams/04-variable-precedence.md), [`diagrams/06-dynamic-inventory.md`](../diagrams/06-dynamic-inventory.md)
