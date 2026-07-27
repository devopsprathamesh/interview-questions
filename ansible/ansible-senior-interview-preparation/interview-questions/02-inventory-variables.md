# Category 2: Inventory, Variables, and Facts

Questions 11–22 of 120. Category weight: 12 questions. Deep-dive reference: [`docs/inventory-and-variables.md`](../docs/inventory-and-variables.md).

---

## Question 11: The play that matched zero hosts

### Scenario
A scheduled production patching playbook silently matched **zero hosts** last night — no error, no failure, just "PLAY RECAP" showing nothing, and nobody noticed until this morning. The dynamic inventory filter is `tag:Environment: production`, but someone recently renamed the tagging convention from `Environment` to `environment` (lowercase) across the fleet as part of an unrelated tagging cleanup.

### Interview Question
Why did this fail silently instead of loudly, and how would you redesign the pipeline so a zero-host match is never silently tolerated again?

### Strong Senior-Level Answer
**Initial assessment:** a dynamic inventory filter that matches nothing is not, by default, an error to Ansible — "zero hosts matched" is a valid, silent outcome (an empty play is not a failure condition), which is exactly why a tag-casing change elsewhere in the organization produced total silence here instead of an obvious break.

**Technical reasoning:** `ansible-playbook` exits 0 (success) for a play that matched zero hosts, unless something explicit checks for and rejects that condition — the tool has no built-in opinion that "a production patching run should always match at least some hosts."

**Investigation process:** `ansible-inventory -i inventory/aws_ec2.yml --list` run independently confirms the actual resolved host count for the filter as currently written, immediately surfacing the mismatch against the renamed tag.

**Recommended solution:** add an explicit host-count assertion at the start of any playbook where "zero hosts" should always be treated as a failure:
```yaml
- name: Fail loudly if this production run unexpectedly matches no hosts
  hosts: localhost
  connection: local
  gather_facts: false
  tasks:
    - name: Assert the production inventory group is non-empty
      ansible.builtin.assert:
        that:
          - groups['tag_Environment_production'] | default([]) | length > 0
        fail_msg: "Zero hosts matched the production filter - inventory tag/filter mismatch likely. Investigate before assuming this run is correct."
```
Additionally, update the filter to match the renamed tag, and coordinate future tag-schema changes with everyone consuming those tags for inventory filtering — this incident is really a cross-team communication gap (a tagging convention changed without checking who depends on the old convention) surfacing through Ansible.

**Risk controls:** treat any change to a tagging convention used by dynamic inventory as a breaking change requiring the same coordinated-rollout discipline as any other shared-interface change — not something one team can silently rename without checking consumers.

**Validation steps:** re-run the assertion-guarded playbook against the corrected filter and confirm it now matches the expected host count; separately, deliberately test the assertion by pointing it at a filter guaranteed to match nothing, confirming the play now fails loudly instead of silently succeeding.

**Rollback or recovery strategy:** not applicable to the assertion itself; for the missed patching window, run the corrected playbook immediately and assess whether the missed night's patching created any compliance/security gap needing separate remediation.

**Long-term prevention:** make a zero-host-match assertion (or an equivalent CI/scheduling-level check) a standard, required pattern for every scheduled production playbook, and require any organization-wide tagging-convention change to be communicated to and coordinated with every team whose automation depends on it.

### Step-by-Step Implementation
See the `assert` example above; run `ansible-inventory --list` as the first diagnostic step whenever a play's host count looks wrong.

### Under-the-Hood Explanation
`ansible-playbook` resolves the play's target hosts from the inventory and any `--limit` filtering, then proceeds to the (possibly empty) task execution phase — an empty host list is treated as a legitimate, if unusual, resolved state, not a distinct error condition, precisely because there are legitimate reasons a filter might match zero hosts on a given run (e.g., a genuinely empty environment). This is why the responsibility for deciding "zero hosts here means something is wrong" falls on the playbook author via an explicit assertion, not on Ansible's own default behavior.

### Common Weak Answer
"Ansible should have errored automatically when no hosts matched."

### Why the Weak Answer Fails
This wishes away a real, if easy-to-overlook, aspect of Ansible's design rather than addressing it — the correct answer is recognizing this behavior explicitly and designing an assertion-based guard for it, not assuming the tool should have caught it automatically on your behalf.

### Follow-Up Questions
1. How would you design a similar guard for a `--limit`-based CLI invocation, not just a dynamic-inventory filter?
2. What process would you put in place organizationally so a tagging-convention change is never made without checking who depends on it?
3. How would you distinguish a genuinely-expected zero-host scenario (e.g., a brand-new environment with no hosts yet) from an unexpected one, in your assertion logic?

### Key Interview Signals
Confirms the candidate knows zero-host matches are silently tolerated by default and designs an explicit assertion-based guard, while also identifying the real organizational root cause (an uncoordinated tagging-convention change).

### Hands-On Connection
[Lab 3 — Dynamic Inventory](../labs/lab-03-dynamic-inventory/).

---

## Question 12: The role that couldn't be overridden

### Scenario
A shared `webserver` role sets `worker_processes` in `roles/webserver/vars/main.yml`. A consuming playbook tries to override it by passing `worker_processes: 4` as a role parameter, but the role stubbornly always uses its own internal value regardless of what the caller passes.

### Interview Question
Explain precisely why the caller's override isn't taking effect, and how you'd fix the role to actually be configurable the way its consumers expect.

### Strong Senior-Level Answer
**Initial assessment:** this is the `defaults` vs. `vars` precedence trap — role `vars/main.yml` has **higher** precedence than role parameters/most caller-supplied overrides in Ansible's fixed variable precedence order, which is the reverse of what most engineers intuitively expect from something living inside a "configurable role."

**Technical reasoning:** Ansible's precedence order specifically places role `vars/main.yml` above role/include parameters (see [`docs/inventory-and-variables.md` §4](../docs/inventory-and-variables.md#4-variable-precedence-order)) — `vars/main.yml` is meant for the role's own internal constants that a caller should *not* easily override, while `defaults/main.yml` is the intentionally-low-precedence, "safe fallback" layer specifically meant to be the public, overridable interface.

**Investigation process:** confirm by checking exactly where `worker_processes` is defined in the role — if it's in `vars/main.yml` rather than `defaults/main.yml`, that single fact fully explains the behavior without needing any other hypothesis.

**Recommended solution:** move the variable to `defaults/main.yml`, where it belongs as the role's actual public interface:
```yaml
# roles/webserver/defaults/main.yml
worker_processes: "auto"   # safe default, meant to be overridden by callers
```
Reserve `roles/webserver/vars/main.yml` for genuinely internal constants the role author does not want (and does not expect) callers to casually override — e.g., a fixed internal file path the role's own templates depend on.

**Risk controls:** audit the rest of the role for any other "should be configurable" variable mistakenly placed in `vars/main.yml` instead of `defaults/main.yml` — this is rarely an isolated instance once one is found, since it usually reflects the role author's incomplete understanding of the precedence distinction at the time the role was written.

**Validation steps:** after moving the variable, re-run the consuming playbook with `worker_processes: 4` passed as a parameter and confirm it now actually takes effect — a Molecule test asserting the rendered config reflects an overridden value (not just the default) is the durable, automated version of this check.

**Rollback or recovery strategy:** not applicable — a variable-location fix with no infrastructure-state risk of its own.

**Long-term prevention:** document this precedence distinction clearly in the organization's role-authoring guidelines (`defaults/` = public interface, `vars/` = internal constants), and consider adding `argument_specs.yml` (see [`docs/role-design.md` §3](../docs/role-design.md#3-argument_specsyml--validated-role-interfaces-ansible-core--211)) so a role's actual configurable surface is explicit and validated, not something callers have to discover by reading task source.

### Step-by-Step Implementation
```yaml
# Before: unintentionally not overridable
# roles/webserver/vars/main.yml
worker_processes: 2

# After: the actual public interface
# roles/webserver/defaults/main.yml
worker_processes: "auto"
```

### Under-the-Hood Explanation
Ansible resolves each variable to a single value by walking its full, fixed precedence order and taking the highest-precedence source that defines that variable name — role `vars/main.yml` sits considerably higher in this order than role parameters passed by a caller (and higher than `defaults/main.yml`, obviously), which is precisely why a variable defined in `vars/main.yml` silently "wins" over anything a consumer attempts to pass in, with no error or warning indicating the override was ignored.

### Common Weak Answer
"Just use `-e worker_processes=4` to force the override."

### Why the Weak Answer Fails
`-e` does sit at the very top of precedence and would work as a one-off workaround, but it doesn't fix the actual role design problem — every future consumer of this role hits the identical confusing behavior unless they also happen to discover the `-e` workaround, and the role's own interface remains broken. The correct fix addresses the role's actual variable placement, not a per-invocation escape hatch.

### Follow-Up Questions
1. Why does Ansible have both `defaults/` and `vars/` at all, rather than a single variables directory — what's the actual design intent behind the precedence difference?
2. How would `argument_specs.yml` have made this role's actual configurable surface clearer to consumers from the start?
3. How would you audit an entire role library for this specific mistake (a variable that should be a public default, sitting instead in `vars/main.yml`) at scale?

### Key Interview Signals
Confirms the candidate knows the specific, often-surprising precedence relationship between role `defaults` and `vars`, and fixes the actual interface design rather than reaching for a per-invocation `-e` workaround.

### Hands-On Connection
[Lab 2 — Roles and Structure](../labs/lab-02-roles-and-structure/).

---

## Question 13: The cached fact that lied about an IP

### Scenario
A load-balancer configuration playbook uses `hostvars[item]['ansible_default_ipv4']['address']` to build an upstream server list, sourced from cached facts (fact caching enabled with a 24-hour TTL). One web server was replaced (terminated and relaunched with a new private IP) six hours earlier. The load balancer config still points at the old, now-nonexistent IP, and nobody notices until health checks start failing.

### Interview Question
Explain exactly why the cached fact was wrong, and redesign the fact-caching strategy so a host replacement doesn't silently propagate a stale IP into dependent configuration.

### Strong Senior-Level Answer
**Initial assessment:** fact caching trades freshness for speed — a cached fact reflects whatever was true when it was last actually gathered, not necessarily current reality, and a host replacement within the cache's TTL window is exactly the scenario where that trade-off produces a genuinely wrong, silently-propagated value.

**Technical reasoning:** the 24-hour TTL means facts gathered before the replacement remain "valid" (from the cache's perspective) for up to 24 hours after they've actually gone stale — nothing about the cache mechanism itself detects that the underlying host has changed; it simply serves whatever was last stored until the TTL expires.

**Investigation process:** confirm the cache's actual last-gathered timestamp for the affected host against the actual replacement time — if the cache entry predates the replacement and is still within its TTL, that fully explains the stale IP without needing any other hypothesis.

**Recommended solution:** for anything genuinely dynamic and consequential (an IP address feeding into load-balancer configuration), don't rely on a long-TTL fact cache at all — either force a fresh fact-gather specifically before this configuration task (`ansible.builtin.setup` re-run, or `meta: clear_facts` plus a fresh gather), or, better, source the IP from the **dynamic inventory** itself (which reflects live cloud-API reality, not a potentially-stale cache) rather than from a cached fact:
```yaml
- name: Configure upstream servers from live inventory, not cached facts
  ansible.builtin.template:
    src: upstream.conf.j2
    dest: /etc/nginx/conf.d/upstream.conf
  vars:
    upstream_ips: "{{ groups['webservers'] | map('extract', hostvars) | map(attribute='ansible_host') | list }}"
    # ansible_host here is populated by the dynamic inventory plugin's
    # `compose: ansible_host = private_ip_address`, always current as of
    # THIS run's live inventory resolution - not a fact cached hours ago
```

**Risk controls:** reserve long-TTL fact caching for genuinely slow-changing facts (OS version, hardware specs) where staleness risk is low and speed benefit is high; never cache anything that directly drives configuration for a *different* host (like a load balancer depending on backend IPs) with a TTL longer than you're comfortable with that dependency being wrong.

**Validation steps:** after the fix, deliberately replace a test host and confirm the load-balancer config correctly picks up its new IP on the very next run, with no TTL-related lag.

**Rollback or recovery strategy:** immediately force a fresh configuration run (bypassing the stale cache) to correct the current load-balancer config; separately, audit for any other configuration depending on potentially-stale cached facts from other hosts.

**Long-term prevention:** establish a clear guideline distinguishing "facts safe to cache with a long TTL" from "values that must always be sourced live" (dynamic inventory attributes, cross-host networking details), and default cross-host dependent configuration to the live-inventory-sourced pattern rather than cached facts.

### Step-by-Step Implementation
See the `ansible_host`-from-inventory example above, contrasted with the cached-fact approach that caused the incident.

### Under-the-Hood Explanation
A fact cache plugin (`jsonfile`, `redis`, etc.) stores the result of the `setup` module's last successful gather for each host, keyed by hostname, with a configured TTL — subsequent runs within that TTL skip re-gathering and simply read from the cache, which is precisely the performance benefit but also precisely the staleness risk: the cache has no mechanism to detect that the underlying host it describes no longer exists (or has changed), since detecting that would require actually re-gathering, defeating the purpose of caching in the first place.

### Common Weak Answer
"Just disable fact caching entirely to avoid this problem."

### Why the Weak Answer Fails
This solves the staleness risk by discarding the entire performance benefit fact caching provides for facts that genuinely don't need to be this fresh (most hardware/OS facts) — the better answer distinguishes which facts are safe to cache long-TTL from which specific, consequential, fast-changing values (like cross-host networking dependencies) should bypass the cache or be sourced from dynamic inventory instead.

### Follow-Up Questions
1. How would you choose an appropriate TTL for different categories of facts, rather than one blanket setting for everything?
2. What's the trade-off between forcing a fresh fact-gather for specific tasks versus disabling caching for the whole play?
3. How would you detect, proactively, that a cached fact has become stale relative to real host state, before it causes a downstream configuration issue?

### Key Interview Signals
Confirms the candidate understands fact caching's genuine speed/staleness trade-off precisely, and designs a differentiated strategy (cache slow-changing facts, source fast-changing cross-host dependencies live) rather than an all-or-nothing caching decision.

### Hands-On Connection
[Lab 3 — Dynamic Inventory](../labs/lab-03-dynamic-inventory/) and [Lab 7 — AWS Configuration Management](../labs/lab-07-aws-configuration-management/).

---

## Question 14: The group_vars nobody loaded

### Scenario
A new environment (`qa`) is added to the inventory, and a `group_vars/qa.yml` file is created with QA-specific overrides. Running the playbook against the `qa` group, none of the overrides take effect — the playbook behaves as if `group_vars/qa.yml` doesn't exist at all.

### Interview Question
What are the most likely, specific causes of Ansible not loading a `group_vars` file that clearly exists on disk, and how would you diagnose which one applies here?

### Strong Senior-Level Answer
**Initial assessment:** `group_vars`/`host_vars` auto-loading depends on exact naming and location conventions matching the inventory's actual group/host names precisely — a mismatch anywhere in that chain (a typo, a wrong directory relative to the playbook/inventory, a group name that doesn't actually match) silently results in the file simply never being discovered, with no error indicating a file was found but ignored.

**Technical reasoning:** the most common concrete causes, in rough order of likelihood: (a) the inventory group is actually named something slightly different (`QA` vs. `qa` — group names are case-sensitive), (b) `group_vars/qa.yml` lives in the wrong directory (Ansible looks for `group_vars/` adjacent to the **inventory file** or the **playbook**, depending on invocation — a `group_vars/` directory in an unrelated location is silently never discovered), (c) using a dynamic inventory plugin whose actual resolved group name differs from a naive assumption (e.g., `keyed_groups` producing `tag_Environment_qa` rather than the bare `qa` you assumed).

**Investigation process:** `ansible-inventory --list` (or `--graph`) shows the *actual* resolved group names Ansible is working with — comparing this against the literal filename `group_vars/qa.yml` immediately reveals a naming mismatch if one exists, without needing to guess.

**Recommended solution:** once the actual group name is confirmed via `ansible-inventory`, rename the `group_vars` file (or, for a dynamic-inventory-produced group name like `tag_Environment_qa`, either use that exact name or add a `keyed_groups` `prefix`/`separator` configuration producing the name you actually want to use for `group_vars`).

**Risk controls:** treat "does the group_vars filename exactly match a real, confirmed inventory group name" as a standard checklist item whenever adding a new environment, rather than assuming naming will just work out.

**Validation steps:** after correcting the name/location, add a simple `ansible.builtin.debug: var=some_qa_specific_variable` task and confirm it now resolves to the expected QA-specific value, proving the file is genuinely being loaded now.

**Rollback or recovery strategy:** not applicable — a naming/location correction with no infrastructure-state risk.

**Long-term prevention:** document the exact `group_vars`/`host_vars` directory location convention your team uses (adjacent to inventory vs. adjacent to playbook) clearly, and consider a lightweight CI check confirming every `group_vars`/`host_vars` filename corresponds to an actual, currently-resolved inventory group/host name — catching a typo'd or orphaned vars file before it ships silently unused.

### Step-by-Step Implementation
```bash
# The definitive diagnostic - shows Ansible's ACTUAL resolved group names
ansible-inventory -i inventory/aws_ec2.yml --graph

# Compare against the group_vars filename
ls group_vars/
# If the graph shows "tag_Environment_qa" but the file is named "qa.yml",
# that mismatch is the entire explanation
```

### Under-the-Hood Explanation
Ansible auto-loads `group_vars/<groupname>.yml` (or `.yaml`, or a directory of the same name containing multiple files) by scanning a fixed set of locations (relative to the inventory source and/or the playbook directory, depending on configuration and invocation style) and matching filenames exactly against the inventory's actually-resolved group names — there is no fuzzy matching, no case-insensitivity, and no error raised for an unmatched `group_vars` file sitting unused in the directory; it's simply never considered, silently, exactly as if it didn't exist.

### Common Weak Answer
"Just double-check the file is spelled correctly."

### Why the Weak Answer Fails
This treats it as a single typo-checking exercise rather than identifying the actual, more general set of possible causes (case mismatch, wrong directory, dynamic-inventory-produced group names differing from assumption) and the correct diagnostic tool (`ansible-inventory`) that definitively settles which specific cause applies, rather than guessing through each possibility manually.

### Follow-Up Questions
1. What's the difference in `group_vars`/`host_vars` discovery behavior between running `ansible-playbook` from different working directories?
2. How would you design a CI check that catches an orphaned, never-loaded `group_vars` file before it ships?
3. How does this same class of issue manifest for `host_vars` instead of `group_vars` — what's a realistic scenario there?

### Key Interview Signals
Confirms the candidate reaches for `ansible-inventory` as the definitive diagnostic tool rather than guessing, and understands the specific, mechanical (not fuzzy) nature of group_vars/host_vars file-to-group-name matching.

### Hands-On Connection
[Lab 5 — Multi-Environment Architecture](../labs/lab-05-multi-environment/).

---

## Question 15: Two inventories, one confused host

### Scenario
A team combines a static inventory file (for a handful of legacy, non-cloud hosts) with a dynamic AWS inventory plugin, using an inventory *directory* containing both sources. One host appears twice — once from the static file (added years ago during a migration that was never fully completed) and once from the dynamic plugin — with two different, conflicting sets of resolved variables depending on which source "wins."

### Interview Question
How would you diagnose and resolve this, and what would you do to prevent overlapping inventory sources from silently conflicting again?

### Strong Senior-Level Answer
**Initial assessment:** combining multiple inventory sources in one directory is a supported, common pattern, but it creates a real risk of exactly this kind of silent overlap when the same underlying host is represented differently by two sources (a static entry using a hostname, a dynamic entry using the same host's private IP or a different identifier) without either source being aware of the other.

**Technical reasoning:** Ansible merges all sources in an inventory directory into one combined view — if two sources produce what Ansible considers *different* host identities (even if they're the same real machine, addressed differently), you get two separate host entries in the combined inventory, each with their own variables, rather than one deduplicated host.

**Investigation process:** `ansible-inventory --list` on the combined inventory directory shows definitively whether this is genuinely two separate host entries (a naming/deduplication issue) or one host with conflicting variables from two sources both matching it (a precedence issue) — these are different problems with different fixes.

**Recommended solution:** if it's genuinely two separate entries for the same real host, the durable fix is completing the migration this static entry was left over from — remove the stale static entry entirely once confirmed the dynamic inventory correctly covers that host, rather than maintaining two competing sources of truth for the same machine indefinitely. If some legacy hosts genuinely can't move to dynamic inventory (truly non-cloud), keep them in a clearly-separated, clearly-named static file with no risk of overlapping identity with anything the dynamic plugin could ever also match.

**Risk controls:** treat "does any static inventory entry risk being also matched or overlapped by the dynamic inventory plugin" as a standing audit item, specifically whenever cloud migration work is ongoing and some hosts are mid-transition between static and dynamic management.

**Validation steps:** after cleanup, `ansible-inventory --list` should show exactly one entry for this host, with an unambiguous, single set of resolved variables.

**Rollback or recovery strategy:** not applicable — an inventory-hygiene cleanup with no infrastructure-state risk of its own, though any playbook run that unknowingly targeted this host twice (once under each identity) in the past should be reviewed for whether that caused any actual double-application issues.

**Long-term prevention:** avoid leaving "temporary" static inventory entries in place indefinitely during a migration to dynamic inventory — track migration completion explicitly and remove the stale static source promptly once dynamic inventory fully covers what it's replacing.

### Step-by-Step Implementation
```bash
ansible-inventory -i inventory/ --list   # combined view of the whole inventory directory
# Look for the same real host appearing under two different inventory_hostname values
```

### Under-the-Hood Explanation
When multiple inventory sources are combined (a directory containing both a static file and a dynamic plugin config), Ansible processes each source independently and merges the resulting host/group/variable data into one combined inventory — there is no cross-source deduplication based on "is this actually the same physical/cloud host," only based on exact `inventory_hostname` string matching; two sources using different naming/addressing for what is, in reality, the same machine will produce two distinct entries in the combined inventory with no warning that this occurred.

### Common Weak Answer
"Just delete whichever entry looks wrong."

### Why the Weak Answer Fails
Without first confirming (via `ansible-inventory --list`) which entry is actually current/correct and which is the stale leftover, deleting the wrong one risks losing legitimate configuration for a host that's still genuinely managed via that source — the correct approach investigates and confirms before removing anything.

### Follow-Up Questions
1. How would you design your inventory structure from the start to make this class of overlap structurally impossible, rather than discovering it after the fact?
2. What's the risk of a playbook run that unknowingly applies configuration to the "same" real host twice, once under each identity — what could go wrong?
3. How would you handle a genuinely permanent need for both static and dynamic inventory sources to coexist long-term, without this overlap risk?

### Key Interview Signals
Confirms the candidate investigates via `ansible-inventory` to distinguish "two entries for one host" from "one host with conflicting sources" before acting, and addresses the underlying incomplete-migration root cause rather than just picking one entry to delete.

### Hands-On Connection
[Lab 3 — Dynamic Inventory](../labs/lab-03-dynamic-inventory/).

---

## Question 16: The `-e` that nobody remembered setting

### Scenario
A CI pipeline's production deployment job has run correctly for months. One day, a deployment silently uses a much older application version than intended, with no error. Investigation reveals a `-e app_version=2.3.1` was added to the pipeline's Ansible invocation eight months ago, for one specific, one-time hotfix deployment, and never removed — every subsequent run has been silently pinned to that same old version regardless of what `group_vars` or the playbook's own logic specified.

### Interview Question
Explain precisely why this `-e` silently overrode everything else for eight months, and redesign the pipeline to prevent a "temporary" override from becoming permanent and unnoticed again.

### Strong Senior-Level Answer
**Initial assessment:** `-e` (extra vars) sits at the **absolute top** of Ansible's variable precedence order, unconditionally — this is deliberate (it's meant to be a genuine, intentional override escape hatch), but it means a leftover `-e` in a CI pipeline's invocation silently wins over every other, more-carefully-managed variable source (`group_vars`, role defaults, everything) indefinitely, with nothing in Ansible itself distinguishing "this was meant to be temporary" from "this is now permanent."

**Technical reasoning:** there's no expiration, no warning, and no visible flag distinguishing an intentional, permanent `-e` from an accidental leftover one — from Ansible's perspective, every `-e` is just the highest-precedence variable source, full stop, for as long as it remains part of the invocation.

**Investigation process:** confirm the exact CI pipeline definition/script that invokes `ansible-playbook` for production deployments, and check its full command-line history/diff over time — this concretely reveals when the `-e app_version=2.3.1` was added and confirms it as the actual cause, rather than assuming.

**Recommended solution:** remove the leftover `-e` immediately, and — more importantly — redesign the pipeline so `app_version` (and anything else genuinely meant to vary per-deployment) is passed as an **explicit, required pipeline input parameter** visible in the pipeline's own configuration/UI (e.g., a GitHub Actions workflow input, or an AWX Job Template survey field), rather than embedded as a hardcoded `-e` flag buried in a shell script that nobody reviews on every run:
```yaml
# GitHub Actions - app_version as an explicit, visible workflow input,
# not a hardcoded -e flag lost in a shell script
on:
  workflow_dispatch:
    inputs:
      app_version:
        required: true
        description: "Application version to deploy"

jobs:
  deploy:
    steps:
      - run: ansible-playbook site.yml -e "app_version=${{ github.event.inputs.app_version }}"
```
This makes the value visible and reviewed on every single invocation, rather than a silent, static leftover.

**Risk controls:** for any one-time, temporary `-e` override used for an emergency/hotfix scenario, treat removing it afterward as an explicit, tracked follow-up task — the same discipline as tracking and reverting any other incident-time out-of-band change.

**Validation steps:** after the fix, confirm a production deployment run correctly picks up the intended, current `app_version` (from a properly-managed source, not a stale `-e`), and confirm the pipeline now requires an explicit, visible input for this value on every invocation.

**Rollback or recovery strategy:** deploy the actually-intended current application version immediately once discovered — this is a real, if quiet, production incident (running an eight-month-old version) requiring its own assessment of what was missed during that window (security patches, bug fixes, feature updates the "current" version should have included).

**Long-term prevention:** never embed a "temporary" `-e` override directly into a CI pipeline's persistent configuration/scripts without an explicit, tracked expiration/removal plan, and prefer pipeline-level, visible input parameters over ad hoc CLI flags for anything meant to vary per-run.

### Step-by-Step Implementation
See the GitHub Actions `workflow_dispatch` input example above.

### Under-the-Hood Explanation
`-e`/extra vars are parsed and applied after every other variable source has been resolved, specifically because they're designed as the deliberate, final override mechanism for ad hoc, per-invocation customization — this design choice (unconditional highest precedence, no expiration) is exactly right for genuine one-off overrides but is precisely what makes an accidentally-persistent `-e` in a repeatedly-invoked CI script so dangerous: the override doesn't fade or get questioned over time, it simply continues silently winning for as long as the flag remains in the invocation.

### Common Weak Answer
"Just remind whoever adds a temporary `-e` flag to remove it afterward."

### Why the Weak Answer Fails
This is the same "remember to be careful" non-control that already failed for eight months — the systemic fix is making the value an explicit, visible, required pipeline input every single run (so its current value is always reviewed, not a hidden, static leftover), not a reminder that depends on someone remembering a cleanup step months after an emergency fix.

### Follow-Up Questions
1. How would you audit an existing CI pipeline for other "temporary" `-e` flags that may have become permanent, unnoticed overrides?
2. What's the trade-off between passing a value as a pipeline input parameter versus a `group_vars`-managed variable — when is each appropriate?
3. How would you design the pipeline to make it structurally obvious, on every single run, exactly which variable values are actually being used, rather than needing to inspect the invocation script?

### Key Interview Signals
Confirms the candidate understands `-e`'s absolute, unconditional precedence and its specific danger in persistent CI scripts, and redesigns the pipeline to make per-run values explicit and reviewed rather than relying on remembering to clean up a temporary override.

### Hands-On Connection
[Lab 12 — CI/CD Pipeline](../labs/lab-12-cicd-pipeline/).

---

## Question 17: The `default()` filter that hid a real bug

### Scenario
A role's task references `{{ db_connection_pool_size | default(10) }}` throughout. A production incident traces back to the connection pool being sized far too small for actual load — investigation reveals `db_connection_pool_size` was **supposed** to be set explicitly per-environment in `group_vars/production.yml`, but a refactor accidentally removed that specific line, and the `default(10)` silently masked the fact that the intended, production-specific value was never actually being applied at all.

### Interview Question
What's the risk in this pattern of using `default()` pervasively, and how would you redesign the role's variable handling to catch this specific class of "the intended override silently disappeared" bug?

### Strong Senior-Level Answer
**Initial assessment:** `| default(...)` is a legitimate, useful filter for genuinely-optional variables where a sensible fallback is appropriate — but using it as a blanket safety net for variables that **should always be explicitly set per environment** actively hides exactly the class of bug that occurred here: a value that was supposed to be intentionally configured silently fell back to a generic default with zero indication anything was wrong.

**Technical reasoning:** `default()` provides no way to distinguish "this variable is genuinely optional, and 10 is a fine default for everyone" from "this variable is required in every real environment, and the fallback exists purely to prevent an ugly undefined-variable error" — both cases render identically at runtime, with the same silent, unremarkable behavior.

**Investigation process:** confirm exactly what `db_connection_pool_size` resolves to on affected production hosts (`ansible-inventory --host <host> --vars`) — finding it resolves to the generic `10` fallback rather than any environment-specific value confirms the override was indeed missing, not just misconfigured.

**Recommended solution:** for variables that are conceptually required-per-environment (even if Ansible's own type system doesn't distinguish "optional with a sensible default" from "required, but currently just falling back"), use an explicit `assert` (or `argument_specs.yml`'s `required: true`, for role-level parameters) rather than a silent `default()`:
```yaml
- name: Require an explicit, environment-specific connection pool size - no silent fallback
  ansible.builtin.assert:
    that:
      - db_connection_pool_size is defined
    fail_msg: "db_connection_pool_size must be explicitly set per environment in group_vars - no default is appropriate for this value."
```
Reserve `default()` specifically for values where "10 is genuinely fine for literally every environment, forever" is actually true — not as a generic safety net against undefined-variable errors for values that matter.

**Risk controls:** audit the rest of the role/codebase for other pervasive `default()` usage on variables that are conceptually required-per-environment rather than genuinely-optional — this is rarely an isolated instance once the underlying habit (defaulting everything to avoid undefined-variable errors) is identified.

**Validation steps:** after adding the `assert`, deliberately remove the environment-specific override in a test and confirm the play now fails loudly with a clear message, rather than silently falling back — this is the concrete proof the guard works.

**Rollback or recovery strategy:** correct the production connection pool size immediately via the properly-restored `group_vars/production.yml` entry; separately assess what load-related impact the undersized pool actually caused during the incident window.

**Long-term prevention:** establish a design convention distinguishing genuinely-optional variables (safe to `default()`) from conceptually-required-per-environment variables (should `assert`/fail loudly if missing, never silently fall back) as a standard part of role variable design review.

### Step-by-Step Implementation
See the `assert`-based guard above, contrasted with the original pervasive `default()` usage.

### Under-the-Hood Explanation
The `default()` Jinja2 filter simply substitutes a fallback value whenever the referenced variable is undefined (or, with the second boolean argument, also for falsy values) — it has no concept of *why* the variable might be undefined, and specifically cannot distinguish "genuinely never meant to be set, fallback is correct" from "meant to be set, but a refactor accidentally broke that" — both produce the exact same, silent, unremarkable runtime behavior, which is exactly the gap that let this incident go undetected until real production load exposed the undersized pool.

### Common Weak Answer
"Just increase the default from 10 to a larger number."

### Why the Weak Answer Fails
This treats the symptom (an undersized default) rather than the actual root cause (a required, environment-specific value silently and undetectably fell back to *any* generic default at all) — a larger hardcoded default might mask the next occurrence of this same refactor-accidentally-removed-the-override bug just as effectively as the original one did, rather than actually surfacing it.

### Follow-Up Questions
1. How would you distinguish, systematically, which variables in a role are genuinely safe to `default()` versus which should always fail loudly if unset?
2. How would `argument_specs.yml`'s `required: true` provide a more structural version of this same guard, compared to a hand-written `assert`?
3. How would you catch this exact class of "a refactor silently removed an intended override" bug via a CI check, before it ever reaches production?

### Key Interview Signals
Confirms the candidate recognizes `default()` as a tool that can mask exactly the kind of bug that occurred here when misapplied to conceptually-required values, and designs an explicit, loud-failure guard instead of just adjusting the fallback value.

### Hands-On Connection
[Lab 5 — Multi-Environment Architecture](../labs/lab-05-multi-environment/).

---

## Question 18: The inventory that grew too large to plan around

### Scenario
Your organization's single Ansible inventory has grown to over 3,000 hosts across a dozen applications and every environment, managed by one shared set of playbooks and one shared CI pipeline. A single typo in one application's `group_vars` recently caused a scheduled patching run to briefly threaten an unrelated application's hosts in the same inventory, and every routine run now takes a long time to even resolve the full inventory before any real task begins.

### Interview Question
Redesign this inventory/playbook architecture to reduce blast radius and improve performance — what's the actual structural fix, not just a performance tweak?

### Strong Senior-Level Answer
**Initial assessment:** this is the direct Ansible analog of the "5,000-resource monolithic Terraform state" problem covered in the companion repository — one shared inventory/playbook/pipeline scope means every change, regardless of which application it's actually meant for, has access to and potential blast radius across the *entire* fleet, and every run pays the cost of resolving the *entire* inventory even for a change touching one application.

**Technical reasoning:** the fix is architectural, not a performance tweak — split by ownership/blast-radius boundaries (per-application inventories/playbooks/pipelines, mirroring the Terraform state-splitting principle), not just by trying to make the one shared inventory resolve faster.

**Investigation process:** map actual ownership boundaries — which applications/teams genuinely need to be able to affect which hosts, and which are currently only sharing an inventory out of historical convenience rather than genuine need.

**Recommended solution:** split into per-application (or per-team) inventories and playbooks, each with its **own** CI pipeline/Job Template, own credentials scoped to only that application's hosts, and own dynamic inventory filter scoped tightly (e.g., `tag:Application: billing` in addition to `tag:Environment`) — mirroring the layered/scoped architecture already established for the companion Terraform repository's foundation/platform/application state split, applied here to inventory/pipeline boundaries instead.

**Risk controls:** during the split, verify each new, narrower inventory resolves to exactly the expected host set (via `ansible-inventory --list`) before cutting any real pipeline over to it, so the split itself doesn't introduce a scoping mistake.

**Validation steps:** after the split, confirm a typo/mistake in one application's `group_vars` can no longer even theoretically reach another application's hosts, since they're now structurally different inventories/pipelines with different scoped credentials — not just organizationally discouraged from interfering.

**Rollback or recovery strategy:** perform the split incrementally, one application at a time, keeping the shared inventory's coverage of not-yet-migrated applications intact until each is fully cut over and validated.

**Long-term prevention:** establish per-application/team inventory and pipeline ownership as the standard going forward for any new application, rather than adding it to a growing shared inventory "because it's already there and convenient."

### Step-by-Step Implementation
```text
Before: one shared inventory, one shared pipeline, 3000+ hosts, every app

After:
inventories/
├── billing/aws_ec2.yml       (filter: tag:Application=billing)
├── billing-pipeline/          (own CI job, own scoped credentials)
├── shipping/aws_ec2.yml       (filter: tag:Application=shipping)
├── shipping-pipeline/
└── ...per application
```
```bash
# Verify each new, narrower inventory before cutting a pipeline over
ansible-inventory -i inventories/billing/aws_ec2.yml --list
```

### Under-the-Hood Explanation
Inventory resolution time scales with the number of hosts/groups Ansible must query and process (especially for a dynamic inventory plugin making a live API call across the entire matched fleet) — a single, unscoped inventory covering 3,000 hosts pays this resolution cost on every single run, even one intended to touch ten hosts belonging to one application, because the inventory *itself* has no concept of "only resolve the subset I actually need" beyond whatever filter is configured; splitting into genuinely separate, narrowly-filtered inventories bounds both the resolution cost and the theoretical reachable-host blast radius to just that application's scope.

### Common Weak Answer
"Just add more `--limit` filtering to routine runs to make them faster and safer."

### Why the Weak Answer Fails
`--limit` narrows what a *specific invocation* targets, but doesn't change the underlying shared inventory's full scope, shared credentials, or shared pipeline — a mistake in shared `group_vars` or a credential with unnecessarily broad reach still threatens the whole fleet regardless of how any one run happens to be limited; the actual fix is structural (separate inventories/pipelines/credentials per ownership boundary), exactly mirroring why `-target` isn't a substitute for real Terraform state splitting.

### Follow-Up Questions
1. How would you sequence which application to split out of the shared inventory first, to minimize risk during the migration?
2. How do teams needing cross-application information (e.g., a shared load balancer's config referencing multiple applications' hosts) get that after the split, if not via one shared inventory?
3. How would you prevent this same "grew organically into one shared, oversized inventory" problem from recurring for the next several new applications?

### Key Interview Signals
Confirms the candidate recognizes this as a structural, ownership-boundary problem (directly analogous to Terraform state splitting) rather than a performance tuning exercise, and designs a genuine split rather than a `--limit`-based workaround.

### Hands-On Connection
[Lab 5 — Multi-Environment Architecture](../labs/lab-05-multi-environment/) and [Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).

---

## Question 19: The fact-gathering timeout that stalled the whole fleet

### Scenario
A scheduled playbook run against 300 hosts hangs for over an hour before anyone kills it, far longer than its usual few minutes. Investigation shows a small number of hosts (about a dozen) have become unresponsive (not fully down, but very slow to respond to SSH) due to an unrelated infrastructure issue, and the default `linear` strategy's per-task synchronization means the entire fleet's progress is gated on these dozen slow hosts finishing fact-gathering before *any* host can proceed to the next task.

### Interview Question
Diagnose why a small number of slow hosts stalled the entire 300-host run, and redesign the playbook's execution approach to be resilient to this exact failure mode.

### Strong Senior-Level Answer
**Initial assessment:** this is the `linear` strategy's synchronization-barrier behavior working exactly as designed, just in a scenario that exposes its real cost — every host must complete a given task (including the implicit fact-gathering "task") before *any* host proceeds to the next, meaning the slowest dozen hosts in the batch structurally gate the other 288 perfectly healthy hosts' progress.

**Technical reasoning:** without a timeout configured, an unresponsive-but-not-fully-down host can hang a connection attempt for a very long time (bounded by underlying SSH/TCP timeout defaults, which are often much longer than you'd want for this purpose) — and under `linear`, that hang blocks the whole play's progress on that task for every host, not just the slow ones.

**Investigation process:** confirm via connection-level logs/timing which specific hosts were the slow ones, and confirm the play strategy/timeout configuration currently in use — the combination of `linear` (default) and no explicit, tight connection timeout is what turns "a dozen slow hosts" into "the entire fleet stalls."

**Recommended solution:** set an explicit, deliberately tight connection timeout appropriate for your environment, so a genuinely unresponsive host fails fast rather than hanging indefinitely:
```ini
# ansible.cfg
[defaults]
timeout = 15   # SSH connection timeout, seconds - tune based on your normal connection latency

[persistent_connection]
connect_timeout = 15
```
Additionally, consider the `free` strategy for large, fault-tolerant fleet runs where strict per-task ordering across hosts isn't actually required — healthy hosts then proceed independently rather than waiting on the slow dozen:
```yaml
- hosts: all
  strategy: free
  # ...
```
Or use `serial` with a reasonable `max_fail_percentage`, so a batch containing several unresponsive hosts fails that batch quickly and clearly (visible as failed/unreachable hosts) rather than hanging silently for an hour.

**Risk controls:** whichever fix is chosen, ensure it converts "unresponsive host" into a **fast, visible failure** for that specific host (so it can be investigated and excluded/retried) rather than either hanging the whole run or silently succeeding despite the underlying host issue.

**Validation steps:** deliberately simulate a slow/unresponsive host in a non-production test (e.g., a firewall rule introducing artificial latency to one test host) and confirm the tuned timeout and/or strategy change correctly isolates that host's failure without stalling the rest of the fleet.

**Rollback or recovery strategy:** for the stalled run, once identified, kill it and re-run with `--limit @<retry-file>` or explicitly excluding the known-unresponsive dozen, rather than assuming a blind full re-run will behave any differently against the same unresponsive hosts.

**Long-term prevention:** make an explicit, tuned connection timeout a standard part of every fleet's `ansible.cfg`, and choose `linear` vs. `free` vs. `serial` deliberately based on whether strict cross-host task ordering is actually required for that specific playbook, rather than leaving every playbook on the default `linear` strategy without considering the trade-off.

### Step-by-Step Implementation
See the `ansible.cfg` timeout configuration and `strategy: free` example above.

### Under-the-Hood Explanation
The `linear` strategy's core guarantee — every host completes task N before any host begins task N+1 — is implemented as an actual synchronization barrier in Ansible's execution engine; a host that hasn't yet returned a result for the current task (whether still connecting, still executing, or genuinely hung) is, by definition, still "in progress" for that barrier, and the engine waits for it (up to whatever timeout is or isn't configured) before allowing any host to proceed — this is precisely why a small number of slow/unresponsive hosts, absent a tight timeout, can stall an entire large fleet's progress under the default strategy.

### Common Weak Answer
"Just increase forks so the slow hosts don't block as many others."

### Why the Weak Answer Fails
`forks` controls how many hosts connect concurrently — it does nothing to address the `linear` strategy's per-task synchronization barrier, which is the actual mechanism causing the stall; more concurrent connections doesn't help if the whole play is still waiting on the slowest host in the current batch to finish before any host (healthy or not) can move to the next task.

### Follow-Up Questions
1. What's the trade-off of switching to the `free` strategy — what ordering guarantees do you lose, and when would that matter?
2. How would you tune the connection timeout value appropriately for your specific environment's normal latency characteristics, without setting it so tight that genuinely-healthy-but-slightly-slow hosts get falsely marked as failed?
3. How would you build monitoring/alerting to catch "a subset of the fleet is becoming unresponsive" proactively, before it's discovered via a stalled scheduled run?

### Key Interview Signals
Confirms the candidate understands the `linear` strategy's synchronization-barrier mechanism precisely (not just "Ansible is slow sometimes") and designs a targeted fix (timeout tuning, strategy choice) addressing the actual cause, rather than an unrelated lever like `forks`.

### Hands-On Connection
[Lab 14 — Troubleshooting, Drift, and Recovery](../labs/lab-14-troubleshooting-and-recovery/).

---

## Question 20: The migration from static to dynamic that broke silently

### Scenario
A team migrates from a hand-maintained static inventory to a dynamic AWS inventory plugin. The cutover appears successful — the playbook runs without error — but two weeks later, someone notices a handful of hosts that were in the old static inventory (and should still exist and be managed) are no longer being touched by any scheduled run at all, because they don't carry the specific tag the new dynamic inventory filter expects.

### Interview Question
How would you have caught this gap during the migration itself, rather than two weeks after the fact, and how do you recover now?

### Strong Senior-Level Answer
**Initial assessment:** this is a coverage-verification gap — the migration was validated by "the playbook runs without error against the new inventory," which says nothing about whether the new inventory's *host set* actually matches the old one's, only that whatever hosts it *did* match were processed successfully.

**Technical reasoning:** a dynamic inventory filter based on tags is only as complete as the tagging coverage across your fleet — any host missing the expected tag (an older host provisioned before the tagging convention existed, or one where tagging automation itself has a gap) is simply invisible to the new inventory, with no error, exactly as happened here.

**Investigation process:** the verification step that should have happened during migration, and that settles this retroactively now: diff the **complete host list** from the old static inventory against the complete resolved host list from the new dynamic inventory (`ansible-inventory --list`), rather than just confirming the new inventory's playbook runs cleanly.
```bash
comm -23 <(sort old-static-hosts.txt) <(ansible-inventory -i inventory/aws_ec2.yml --list | jq -r '._meta.hostvars | keys[]' | sort)
# Any output here is a host the old inventory had that the new one is missing
```

**Recommended solution:** for the hosts revealed missing, apply the correct tags so they're properly covered by the dynamic inventory's filter, then re-run the diff to confirm full parity. Going forward, tag every host at provisioning time as a mandatory, automated step (part of the account-vending/provisioning pipeline, not a manual, easily-forgotten afterthought), so this gap can't recur for future hosts.

**Risk controls:** treat any inventory-source migration (static → dynamic, or a filter-criteria change to an existing dynamic inventory) as requiring an explicit before/after host-list diff as part of the migration's own acceptance criteria — never just "the playbook ran without error."

**Validation steps:** after correcting the tags, confirm the diff now shows zero missing hosts, and confirm a real scheduled run now actually touches the previously-missed hosts.

**Rollback or recovery strategy:** for the two-week gap, assess what configuration drift or missed patching may have accumulated on the untouched hosts during that window, and remediate via a normal corrective run once they're correctly included.

**Long-term prevention:** make host-list parity verification (via an explicit diff, not just "it ran cleanly") a required step in any future inventory-source migration or dynamic-inventory-filter change, and enforce tagging at provisioning time as a mandatory, automated pipeline step rather than a convention that individual hosts can silently fail to follow.

### Step-by-Step Implementation
See the `comm`-based diff example above — the concrete verification step that should be standard for any inventory migration.

### Under-the-Hood Explanation
A dynamic inventory plugin's resolved host set is entirely determined by its configured filter criteria matched against live cloud API data — it has no awareness of what a *previous*, different inventory source (a static file) used to contain, and no way to flag "this host existed in the old source but doesn't match my filter" without an explicit, deliberate comparison being performed by the migrating engineer; a clean, error-free playbook run against the new inventory only proves the hosts it *did* match were processed successfully, saying nothing about coverage completeness relative to what should be managed.

### Common Weak Answer
"If the playbook ran successfully against the new inventory, the migration worked."

### Why the Weak Answer Fails
This conflates "ran without error" with "achieved full coverage parity with the old inventory" — exactly the gap that let a real subset of hosts silently fall out of management for two weeks; the correct verification is an explicit host-list diff, not just observing a clean run against whatever the new inventory happened to resolve.

### Follow-Up Questions
1. How would you design an ongoing, automated check (not just a one-time migration verification) confirming dynamic inventory coverage stays complete as new hosts are provisioned over time?
2. What would you do if some hosts genuinely can't be tagged consistently (e.g., a legacy system outside your automated provisioning pipeline) — how do you handle them going forward?
9. How would you extend this same coverage-verification discipline to a filter-criteria change on an already-dynamic inventory, not just a static-to-dynamic migration?

### Key Interview Signals
Confirms the candidate insists on an explicit coverage-parity verification (a real diff) for any inventory migration, rather than treating "the playbook ran cleanly" as sufficient proof of a successful cutover.

### Hands-On Connection
[Lab 3 — Dynamic Inventory](../labs/lab-03-dynamic-inventory/).

---

## Question 21: The dynamic inventory cache that leaked into git

### Scenario
To speed up repeated local runs during development, an engineer enables dynamic inventory caching (`cache = true`, a local `jsonfile` cache plugin) and, without realizing it, the cache directory ends up inside the repository's working tree and gets accidentally committed — containing private IP addresses, instance IDs, and tag values for the entire production fleet, now sitting in git history.

### Interview Question
Is this a real security exposure, and what's your response?

### Strong Senior-Level Answer
**Initial assessment:** yes, a real, if moderate-severity, exposure — private IPs, instance IDs, and tags aren't credentials, but they're real infrastructure topology information that shouldn't be broadly, permanently visible in git history (accessible to anyone with repo access, indefinitely, including anyone who ever clones or forks it), and depending on tag contents (some organizations embed more sensitive metadata in tags than they realize), the actual sensitivity could be higher than "just IPs."

**Technical reasoning:** inventory caching writes the plugin's resolved result (the full host/group/variable data) to local disk specifically to avoid re-querying the cloud API on every run — this cache directory is not inherently different from any other local working file, and will be committed exactly like anything else if it's not explicitly excluded and someone runs a broad `git add`.

**Investigation process:** confirm exactly what's in the committed cache file(s) — cross-reference against your organization's actual sensitivity classification for infrastructure topology data (private IPs alone may be low-severity if the network isn't reachable from untrusted locations; instance IDs plus tags revealing application/environment structure may be more revealing than assumed).

**Recommended solution:** immediately add the cache directory to `.gitignore` (`inventory_cache/` or wherever it's configured to write), and — since git history retains the committed version regardless of a future `.gitignore` addition — treat this the same as any other accidentally-committed sensitive file: assess whether history needs to be rewritten (for a private repo with a small, known set of clones, more tractable; for anything broadly cloned/forked, treat the exposure as permanent and focus on whether anything genuinely sensitive was in it that needs a different response, like rotating anything the exposed topology data could have helped someone target).

**Risk controls:** configure the cache directory location explicitly, outside the repository's working tree entirely (e.g., `/tmp/ansible-inventory-cache` or a directory under `~/.cache/`), removing the possibility of an accidental commit at the source, rather than relying solely on `.gitignore` to catch it after the fact.

**Validation steps:** confirm the corrected cache location is genuinely outside the repo (test with `git status` after a cached inventory run — it should show no new untracked files related to the cache at all).

**Rollback or recovery strategy:** for the already-committed history, assess repo visibility/clone count to decide whether a history rewrite is proportionate; regardless, ensure the cache location fix prevents any recurrence.

**Long-term prevention:** add a secret/sensitive-data scanner (the same gitleaks-style CI gate discussed in the companion repositories' security material) covering this repository too, catching not just credential-shaped strings but potentially this class of "infrastructure topology data accidentally committed" issue if your scanner rules are configured to flag it (e.g., patterns matching private IP ranges at volume).

### Step-by-Step Implementation
```ini
# ansible.cfg - cache location explicitly OUTSIDE the repo working tree
[inventory]
cache = true
cache_plugin = jsonfile
cache_connection = /tmp/ansible-inventory-cache   # NOT a path inside the repo
cache_timeout = 3600
```
```bash
# .gitignore, as defense-in-depth even with the corrected location
inventory_cache/
.ansible_cache/
```

### Under-the-Hood Explanation
Ansible's inventory caching mechanism writes the dynamic inventory plugin's fully-resolved result (host list, group memberships, all composed variables) to whatever location the configured cache plugin/connection string specifies — this is ordinary local file I/O with no special protection or exclusion from version control by default; if that location happens to fall inside a git working tree with no `.gitignore` entry excluding it, it will be committed exactly like any other file the moment someone runs a broad `git add`.

### Common Weak Answer
"Just add it to .gitignore and move on."

### Why the Weak Answer Fails
This prevents *future* commits of the cache but does nothing about the version already sitting in git history, which remains permanently accessible to anyone with repo access (or anyone who already cloned/forked it) regardless of a later `.gitignore` addition — the complete answer needs to assess whether history rewriting or some other remediation is proportionate to the actual sensitivity of what was exposed.

### Follow-Up Questions
1. How would you decide whether rewriting git history is proportionate here, versus accepting the exposure and focusing on preventing recurrence?
2. What's the difference in risk between this and a similar accidental commit of a Terraform state file (covered in the companion repository) — is the severity comparable?
3. How would you extend your secret-scanning CI gate to catch this specific class of "infrastructure topology data," which doesn't look like a typical credential pattern?

### Key Interview Signals
Confirms the candidate treats this as a genuine (if moderate) exposure requiring real assessment, not dismissed as "just add to gitignore," and fixes the cache location at the source rather than relying solely on `.gitignore` as the only safeguard.

### Hands-On Connection
[Lab 3 — Dynamic Inventory](../labs/lab-03-dynamic-inventory/) and [Lab 10 — Security Hardening Pipeline](../labs/lab-10-security-hardening/).

---

## Question 22: The variable that meant two different things

### Scenario
Two teams both use a variable named `region` in their respective roles — one team's `region` refers to an AWS region (`us-east-1`), the other's refers to a sales/business region (`emea`). When both roles are composed into the same playbook for a shared host, one role's tasks silently receive the wrong value for `region`, since Ansible has a single, flat variable namespace per host, not one scoped per role.

### Interview Question
Explain why this collision happened, and how you'd redesign variable naming to prevent it — both for this specific case and as a general practice across a growing role library.

### Strong Senior-Level Answer
**Initial assessment:** Ansible variables are **not** namespaced per role by default — every role sharing the same host resolves into the same flat variable space, meaning two roles independently choosing the same generic variable name for two genuinely different concepts will collide, with whichever value has the higher effective precedence silently winning for both roles' usage.

**Technical reasoning:** this is directly analogous to a naming collision in any shared global namespace in general-purpose programming — the fix is the same in spirit: prefix/scope variable names to their owning role/domain, rather than relying on generic names that any other role author might independently choose too.

**Investigation process:** confirm via `ansible-inventory --host <host> --vars` (or a debug task inside each role) exactly what `region` resolves to for the affected host, and trace which role's `group_vars`/`defaults` is actually winning — this concretely demonstrates the collision rather than just theorizing about it.

**Recommended solution:** rename each role's variable to be explicitly namespaced/prefixed by its own domain, following the same convention already used correctly elsewhere in a well-designed role (e.g., `webserver_port`, `webserver_enable_ssl` from [`docs/role-design.md` §2](../docs/role-design.md#2-designing-the-role-interface) — the prefix convention *is* the namespacing mechanism):
```yaml
# Before: generic, collision-prone
region: "us-east-1"   # aws-infra role
region: "emea"         # sales-reporting role

# After: explicitly namespaced per role/domain
aws_infra_region: "us-east-1"
sales_reporting_region: "emea"
```

**Risk controls:** establish and enforce (via a lint check or code-review convention) that every role's variables carry a role/domain-specific prefix, exactly mirroring the `argument_specs.yml`/`defaults` interface discipline already covered — a generic, unprefixed variable name in any shared role library is a latent collision risk waiting for a second role to independently pick the same name.

**Validation steps:** after renaming, confirm via `ansible-inventory --host <host> --vars` that both variables now resolve independently and correctly, with no shared name at all to collide.

**Rollback or recovery strategy:** not applicable — a variable-naming fix with no infrastructure-state risk, though confirm which role was silently receiving the wrong value in production and assess what impact that had before the fix.

**Long-term prevention:** adopt a mandatory role-prefix naming convention for every variable across the entire role library (not just newly-written roles), and treat this as a standing `ansible-lint`-enforceable rule (custom rules can check for this pattern) rather than a one-time cleanup.

### Step-by-Step Implementation
See the `aws_infra_region`/`sales_reporting_region` renaming example above.

### Under-the-Hood Explanation
Ansible resolves variables into one flat namespace per host for a given play, built by merging every applicable source (group_vars, host_vars, role defaults/vars, facts, etc.) — there is no concept of a role-scoped or module-scoped variable namespace isolating one role's `region` from another's; whichever source defines a variable of a given name at the highest effective precedence for that host "wins" for **every** consumer of that variable name in that run, regardless of which role's task happens to reference it.

### Common Weak Answer
"Just have the two teams agree not to both use `region`."

### Why the Weak Answer Fails
This is a one-time, ad hoc negotiation that doesn't scale — the next new role added by a third team could just as easily choose `region`, or `environment`, or any other generic name already in use elsewhere, reintroducing the identical collision; the systemic fix is a mandatory, lint-enforceable naming convention (role-prefixed variables) applied consistently across the entire role library, not a one-off agreement between two specific teams.

### Follow-Up Questions
1. How would you retrofit this naming convention across an existing, large role library without a risky, simultaneous mass-rename?
2. How would you design an `ansible-lint` custom rule to catch a new role introducing an unprefixed, generic variable name before it merges?
3. Are there any variable names that legitimately *should* be shared/unprefixed across roles (like Ansible's own magic variables) — how do you distinguish those from role-specific variables that need namespacing?

### Key Interview Signals
Confirms the candidate understands Ansible's flat, per-host variable namespace (no automatic role-scoping) and designs a systemic, lint-enforceable naming convention rather than a one-time negotiation between the two specific teams involved in this incident.

### Hands-On Connection
[Lab 2 — Roles and Structure](../labs/lab-02-roles-and-structure/).
