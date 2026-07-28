# Category 4: Modules, Plugins, and Connection Types

Questions 35–42 of 120. Category weight: 8 questions. Deep-dive reference: [`docs/ansible-architecture.md`](../docs/ansible-architecture.md).

---

## Question 35: The module that only existed on one laptop

### Scenario
A developer adds a new task using `amazon.aws.rds_instance` to a role, tests it successfully locally, and opens a PR. CI fails immediately with "couldn't resolve module/action 'amazon.aws.rds_instance'." The developer insists "it works on my machine."

### Interview Question
Diagnose the actual cause and fix the pipeline so this class of failure can't recur.

### Strong Senior-Level Answer
**Initial assessment:** "works on my machine, fails in CI" for a module-resolution error almost always means the collection providing that module is installed locally (perhaps from earlier ad hoc exploration, or a global install) but isn't declared in `requirements.yml` — CI, running from a clean environment, has no such module available at all.

**Technical reasoning:** `ansible-galaxy collection install` only installs what's explicitly listed in `requirements.yml` (or manually specified) — a developer's local machine accumulating collections over time from various past work is a completely different, uncontrolled state from a clean CI checkout.

**Investigation process:** confirm via `ansible-galaxy collection list` on the developer's machine that `amazon.aws` (at whatever version provides `rds_instance`) is indeed present locally, then confirm it's genuinely absent from `requirements.yml`.

**Recommended solution:** add the collection (and a version constraint) to `requirements.yml`, and — critically — make CI's collection-install step run from `requirements.yml` on every single run (not a cached, potentially-stale install), so a missing entry is caught immediately:
```yaml
# requirements.yml
collections:
  - name: amazon.aws
    version: ">=7.0.0,<8.0.0"
```

**Risk controls:** for local development, encourage (or enforce via a pre-commit hook) developers to install collections *only* from `requirements.yml` in a fresh virtual environment/container, rather than accumulating a globally-installed, uncontrolled local collection set that masks this exact class of gap during local testing.

**Validation steps:** re-run CI and confirm the module now resolves correctly; separately, have the developer confirm the task still works after reinstalling collections strictly from the corrected `requirements.yml` in a clean environment, proving the fix is complete, not just "CI happens to pass now."

**Rollback or recovery strategy:** not applicable — a dependency-declaration fix with no infrastructure-state risk.

**Long-term prevention:** use a pinned Execution Environment image (see [Question 40](#question-40-the-laptop-that-drifted-from-ci)) for both local development and CI, eliminating the entire class of "my local environment has something CI doesn't" discrepancy at the source.

### Step-by-Step Implementation
```bash
# Diagnose: confirm the collection is present locally but missing from requirements.yml
ansible-galaxy collection list | grep amazon.aws
grep amazon.aws requirements.yml   # likely empty/missing

# Fix: add it, then verify from a clean state
rm -rf ~/.ansible/collections
ansible-galaxy collection install -r requirements.yml
ansible-playbook site.yml --syntax-check   # confirms module resolution without a real run
```

### Under-the-Hood Explanation
Ansible resolves a fully-qualified module name (`amazon.aws.rds_instance`) by searching installed collection paths (`~/.ansible/collections`, any `collections/` directory adjacent to the playbook, or paths configured via `ANSIBLE_COLLECTIONS_PATH`) for a collection matching the `amazon.aws` namespace containing that module — if no such collection is installed in any searched path, resolution fails immediately, before any connection to a target host is even attempted. A developer's local machine, having accumulated collections from unrelated past work, has a search path that happens to satisfy this specific resolution; a clean CI checkout, installing only from a possibly-incomplete `requirements.yml`, does not.

### Common Weak Answer
"Just install the collection manually in the CI pipeline as a one-off fix."

### Why the Weak Answer Fails
A manual, undeclared install step in the CI pipeline configuration itself just relocates the same underlying problem — an unpinned, undeclared dependency — from `requirements.yml` to the pipeline script, with the same risk of drifting out of sync with what's actually needed as the codebase evolves; the correct fix declares the dependency in the one place (`requirements.yml`) that both local development and CI should consistently install from.

### Follow-Up Questions
1. How would you audit an entire codebase for other modules being used without a corresponding `requirements.yml` entry?
2. What's the risk of an unconstrained collection version range (no upper bound) in `requirements.yml`, similar to the Terraform provider-version discussion?
3. How would an Execution Environment image eliminate this entire class of discrepancy, not just this one instance?

### Key Interview Signals
Diagnoses "works on my machine" precisely (uncontrolled local collection state vs. clean CI) rather than treating it as mysterious, and fixes the actual dependency declaration rather than patching around it in the pipeline.

### Hands-On Connection
[Lab 12 — CI/CD Pipeline](../labs/lab-12-cicd-pipeline/).

---

## Question 36: One inventory, three connection types

### Scenario
Your fleet includes real EC2 Linux hosts (SSH), a handful of legacy Windows servers (WinRM), and a set of Molecule-style test containers used for a specific validation step (Docker). A new engineer proposes writing three entirely separate playbooks, one per connection type, duplicating most of the actual configuration logic three times.

### Interview Question
Is a fully separate playbook per connection type actually necessary? Design a better approach.

### Strong Senior-Level Answer
**Initial assessment:** no — connection type is an inventory/host-level property (`ansible_connection`), not something that needs to be baked into separate playbooks; mixing connection types within a single inventory (and even a single play, if the underlying tasks are genuinely cross-platform) is normal and well-supported, and duplicating logic three times is exactly the kind of unnecessary redundancy this repository's broader "avoid overly generic/duplicated automation" principles argue against.

**Technical reasoning:** `ansible_connection` (along with `ansible_host`, `ansible_port`, etc.) is set per-host or per-group in inventory, and Ansible's connection-plugin dispatch happens per-host at task-execution time — a single play can, in principle, target hosts with different connection types simultaneously, though in practice you'll usually still want separate plays for genuinely different task content (Windows-specific modules vs. Linux-specific modules), while still sharing the same playbook/repository and, where task content genuinely is cross-platform, the same tasks.

**Investigation process:** identify which parts of the "configuration logic" are genuinely platform-specific (package management, service management — inherently different between Windows and Linux) versus genuinely shared (e.g., a cross-platform health-check `uri` task) — this determines how much can actually be shared versus needs platform-specific tasks regardless of connection-type handling.

**Recommended solution:** structure inventory groups by connection type/platform, and structure the playbook to target each group with the appropriate platform-specific tasks, while sharing common roles/tasks wherever genuinely platform-agnostic:
```yaml
# inventory/group_vars/windows_hosts.yml
ansible_connection: winrm
ansible_winrm_transport: kerberos

# inventory/group_vars/molecule_test_containers.yml
ansible_connection: docker
```
```yaml
# playbooks/site.yml
- hosts: linux_hosts
  roles: [common, webserver]   # SSH, default connection

- hosts: windows_hosts
  roles: [windows-baseline]     # WinRM, Windows-specific tasks

- hosts: molecule_test_containers
  roles: [webserver]            # Docker, reusing the SAME webserver role as linux_hosts
```

**Risk controls:** be cautious about assuming a role written for Linux "just works" against a differently-connected target without verifying — connection type affects *how* Ansible reaches the host, but the tasks themselves still need to be written for (or conditionally branch on) the actual target OS/platform.

**Validation steps:** confirm each play correctly targets only its intended connection-type group (`ansible-inventory --graph` showing the group memberships as expected), and that shared roles genuinely produce correct, working configuration across the different connection types they're applied to.

**Rollback or recovery strategy:** not applicable — a structural design decision with no infrastructure-state risk.

**Long-term prevention:** default to structuring by inventory group/connection-type property rather than duplicating entire playbooks, reserving genuine duplication only for content that's truly platform-specific and can't reasonably be shared.

### Step-by-Step Implementation
See the grouped inventory and multi-play structure above.

### Under-the-Hood Explanation
Ansible resolves the connection plugin to use for a given task's execution based on that specific target host's resolved `ansible_connection` variable (from inventory/group_vars/host_vars) at the moment the task is dispatched to that host — this resolution happens independently per host, meaning a single inventory (and even, where task content allows, a single play) can genuinely mix SSH-connected, WinRM-connected, and Docker-connected hosts without needing entirely separate playbook files purely to accommodate the different connection mechanisms.

### Common Weak Answer
"Yes, always use separate playbooks per connection type for clarity."

### Why the Weak Answer Fails
This conflates "connection type" with "needs entirely separate automation," when the actual driver for separation should be platform-specific task content (Windows vs. Linux package/service management), not connection mechanism alone — genuinely shareable logic (like the `webserver` role example) shouldn't be duplicated three times just because the underlying hosts are reached differently.

### Follow-Up Questions
1. How would you handle a role that's *almost* cross-platform but needs a few OS-specific task variations — what's the cleanest way to express that without full duplication?
2. What's the risk of assuming a role "just works" against a new connection type without explicit testing?
3. How does this same principle apply to a Kubernetes pod target (via the `kubernetes.core` collection's connection options) alongside traditional SSH-connected hosts?

### Key Interview Signals
Recognizes connection type as an inventory-level property, not a reason for wholesale playbook duplication, and correctly identifies platform-specific task content (not connection mechanism) as the actual driver for genuine separation.

### Hands-On Connection
[Lab 9 — Kubernetes and Helm](../labs/lab-09-kubernetes-and-helm/) (a different connection-type scenario, same underlying principle).

---

## Question 37: The output nobody could parse

### Scenario
Your CI pipeline runs Ansible playbooks and tries to parse the human-readable console output with regex to determine per-host success/failure for a custom dashboard, which breaks every time Ansible's default output formatting changes slightly across a version upgrade.

### Interview Question
Redesign this to be robust and version-independent.

### Strong Senior-Level Answer
**Initial assessment:** parsing human-readable, formatting-optimized-for-terminal-display output with regex is inherently fragile — exactly the same anti-pattern as parsing `terraform plan`'s human-readable text output instead of using `terraform show -json`; Ansible has a direct equivalent solution.

**Technical reasoning:** callback plugins can produce genuinely structured, machine-parseable output instead of the default human-readable format, decoupling any downstream consumer (a CI dashboard, a log aggregator) from Ansible's own internal, presentation-focused formatting choices, which are not a stable contract across versions.

**Investigation process:** confirm whether an official structured-output callback (like `community.general.json` or the ARA (Ansible Run Analysis) integration) meets the need, before considering writing a fully custom callback plugin.

**Recommended solution:**
```ini
# ansible.cfg
[defaults]
callbacks_enabled = community.general.json
```
```bash
ANSIBLE_STDOUT_CALLBACK=community.general.json ansible-playbook site.yml > run-result.json
```
The dashboard then parses genuinely structured JSON (per-host results, task-level detail, changed/failed/skipped counts) rather than regex-matching against console formatting that isn't designed or guaranteed to be stable for machine consumption.

**Risk controls:** if the built-in JSON callback doesn't capture exactly what the dashboard needs, writing a custom callback plugin (a well-defined Python API, hooking specific events like `v2_runner_on_ok`/`v2_runner_on_failed`) is a legitimate, supported extension point — still far more robust than regex-parsing presentation output.

**Validation steps:** confirm the dashboard's parser now correctly handles output across at least two different Ansible versions without needing any regex adjustment, proving the fix actually decoupled it from presentation-layer changes.

**Rollback or recovery strategy:** not applicable — a tooling-integration fix with no infrastructure-state risk.

**Long-term prevention:** establish "never parse Ansible's default human-readable console output programmatically" as a standing rule, exactly mirroring "always use `terraform show -json`, never parse `terraform plan`'s text output" from the companion repository.

### Step-by-Step Implementation
See the `community.general.json` callback configuration above.

### Under-the-Hood Explanation
Ansible's default console output (the `default` callback plugin) is explicitly designed and tuned for human terminal readability — color, indentation, and exact wording are all subject to change across releases as usability improvements are made, with no guarantee of stability for programmatic parsing. Callback plugins hook into Ansible's internal event stream (task start, task result, playbook stats) at a structured, well-defined API level — a JSON-producing callback serializes this same underlying event data into a stable, parseable format, entirely decoupled from whatever the human-facing `default` callback happens to look like in any given version.

### Common Weak Answer
"Just update the regex whenever Ansible's output format changes."

### Why the Weak Answer Fails
This is a permanent, recurring maintenance burden reacting to every future Ansible version's presentation-layer changes — the correct fix eliminates the entire class of fragility by consuming genuinely structured output instead of fighting an ever-shifting human-readable format that was never intended as a stable machine interface.

### Follow-Up Questions
1. What's the difference between a callback plugin and simply piping Ansible's `-v`/`-vvv` output into a log aggregator — which is more robust for structured consumption?
2. How would you design a custom callback plugin if the built-in JSON callback doesn't capture a specific piece of information your dashboard needs?
3. How does this same "don't parse human-readable output" principle apply to `ansible-inventory`'s output — what's the equivalent robust approach there?

### Key Interview Signals
Recognizes regex-parsing human-readable console output as inherently fragile and reaches for the structured, purpose-built alternative (a callback plugin producing JSON) rather than accepting ongoing regex maintenance as normal.

### Hands-On Connection
[Lab 12 — CI/CD Pipeline](../labs/lab-12-cicd-pipeline/).

---

## Question 38: The lookup that quietly made every play slower

### Scenario
A role uses `lookup('pipe', 'aws secretsmanager get-secret-value --secret-id app/db-password --query SecretString --output text')` inside a task that runs for every host in a 200-host play. The play has become noticeably slower since this was introduced, and the team can't figure out why, since the lookup itself, tested individually, returns almost instantly.

### Interview Question
Explain why this specific pattern causes a much bigger slowdown than the individual lookup's own latency would suggest, and redesign it.

### Strong Senior-Level Answer
**Initial assessment:** `lookup()` calls execute on the **control node**, not per managed host, and — critically — are typically **not cached** by default across loop iterations/multiple hosts referencing the same task; if this lookup is inside a task that runs once per host in a 200-host play, that's potentially 200 separate `aws secretsmanager` API calls from the control node, each with its own latency and rate-limit exposure, even though the secret value is identical for every host.

**Technical reasoning:** a lookup plugin is control-node-side I/O, fully independent of Ansible's per-host connection/execution model — it doesn't benefit from `forks`-based parallelism the way per-host module execution does (all 200 lookup calls originate from the same single control-node process, typically sequentially, one per host as that host's task is being prepared), and repeated identical lookups for the same static value are pure waste.

**Investigation process:** confirm via `ansible.posix.profile_tasks` timing whether this specific task is indeed the dominant contributor to the play's slowdown — this settles it definitively rather than assuming.

**Recommended solution:** resolve the secret **once**, at the play level (via `run_once: true` combined with a fact set on a delegate host, or simply resolved once in a separate, `hosts: localhost` play before the main play begins), then reference the already-resolved value for every host, rather than re-invoking the lookup per host:
```yaml
- hosts: localhost
  connection: local
  gather_facts: false
  tasks:
    - name: Resolve the secret ONCE, not per-host
      ansible.builtin.set_fact:
        resolved_db_password: "{{ lookup('amazon.aws.aws_secret', 'app/db-password') }}"

- hosts: app_servers
  tasks:
    - name: Use the already-resolved secret
      ansible.builtin.template:
        src: app-config.j2
        dest: /etc/app/config.conf
      vars:
        db_password: "{{ hostvars['localhost']['resolved_db_password'] }}"
```

**Risk controls:** for genuinely per-host-varying lookups (where the value really does differ by host), this single-resolution pattern doesn't apply — but confirm that's actually the case rather than assuming, since many "looks per-host" lookups (like this shared database password) are actually identical across every host and needlessly re-fetched.

**Validation steps:** re-run with profiling enabled and confirm the task's total time dropped from roughly 200× a single lookup's latency to roughly 1× (plus per-host template rendering, which is fast).

**Rollback or recovery strategy:** not applicable — a performance fix with no infrastructure-state risk.

**Long-term prevention:** treat any lookup plugin call inside a per-host-executed task as a candidate for "does this value actually vary per host, or is it being needlessly re-fetched identically 200 times" — resolve genuinely-shared values once, at the play level, as a standard practice.

### Step-by-Step Implementation
See the `run_once`/`hosts: localhost` pre-resolution pattern above.

### Under-the-Hood Explanation
Lookup plugins execute synchronously on the control node as part of variable/template resolution for whichever task references them — unlike module execution (which Ansible dispatches to managed hosts, in parallel up to `forks`), a lookup's control-node-side I/O happens once per task-per-host evaluation, sequentially, on the single control-node process, with no built-in caching across hosts unless you explicitly resolve and store the value once (via `set_fact` on a single delegate host) and reference that stored value everywhere else.

### Common Weak Answer
"Just increase forks to speed up the lookup calls."

### Why the Weak Answer Fails
`forks` controls concurrent *connections to managed hosts* — it has no effect on lookup plugin execution, which happens entirely on the control node, independent of per-host connection parallelism; this fix wouldn't address the actual bottleneck at all.

### Follow-Up Questions
1. How would you identify, in a large existing codebase, other instances of a lookup being redundantly re-executed per host for a value that's actually shared/static?
2. What's the trade-off of resolving a secret once at play-start versus per-host, if the secret genuinely could differ by host in some edge case?
3. How does this same "control-node-side I/O repeated unnecessarily per host" class of issue show up with other constructs beyond `lookup()`, like a `command`-based control-node-side check?

### Key Interview Signals
Understands lookup plugins as control-node-side, per-task-evaluation I/O with no automatic caching or forks-based parallelism, and redesigns to resolve genuinely-shared values once rather than redundantly per host.

### Hands-On Connection
[Lab 4 — Ansible Vault](../labs/lab-04-ansible-vault/) and [Lab 14 — Troubleshooting, Drift, and Recovery](../labs/lab-14-troubleshooting-and-recovery/).

---

## Question 39: The custom module that wasn't worth building

### Scenario
An engineer proposes writing a custom Python module to wrap a specific internal API call needed by exactly one role, used by exactly one application team, roughly once a quarter during a specific maintenance procedure.

### Interview Question
Would you approve building a custom module for this, or recommend an alternative? Walk through your reasoning.

### Strong Senior-Level Answer
**Initial assessment:** a custom module is a real, ongoing engineering investment (Python code with proper idempotency/check-mode support, its own test suite, its own maintenance burden as Ansible/Python versions evolve) — justified when a need is common enough across the organization to be worth that investment, not for a single team's quarterly, narrow use case.

**Technical reasoning:** for this specific scenario (rare, single-team, narrow use), a well-guarded `command`/`uri` task with explicit `changed_when`/`failed_when` logic is a pragmatic, proportionate choice — it won't have a custom module's clean idempotency semantics, but building and maintaining a full custom module for something this narrow is disproportionate engineering investment relative to its actual usage.

**Investigation process:** confirm the actual usage pattern (frequency, number of consumers) as stated — this is the deciding factor, not the specific API call's complexity.

**Recommended solution:** implement via a well-guarded task, not a custom module:
```yaml
- name: Call the internal API for the quarterly maintenance procedure
  ansible.builtin.uri:
    url: "https://internal-api.example.com/v1/maintenance-trigger"
    method: POST
    body_format: json
    body:
      procedure: "quarterly-cleanup"
    status_code: [200, 202]
  register: api_result
  changed_when: api_result.json.status == "triggered"
```
Using `ansible.builtin.uri` here (rather than `command`/`shell` with `curl`) is itself already a meaningfully better choice than the weakest possible implementation, giving reasonable status-code/response handling without the investment of a full custom module.

**Risk controls:** if this specific need grows — more consumers, more frequent use, more complex idempotency requirements the `uri` module can't cleanly express — revisit the custom-module decision at that point, since the calculus changes with actual usage growth.

**Validation steps:** a Molecule test asserting the correct API call shape and response handling for this narrow use case is proportionate; a full custom-module test suite would be disproportionate for this scale of usage.

**Rollback or recovery strategy:** not applicable — a build-vs-buy-equivalent decision with no infrastructure-state risk of its own.

**Long-term prevention:** establish a standing guideline: a custom module is justified by (a) no existing module/collection covering the need, (b) genuine, broad, recurring usage across the organization, and (c) a real idempotency/check-mode requirement a guarded `command`/`uri` task can't cleanly express — all three, not just one, should generally be true before investing in a custom module.

### Step-by-Step Implementation
See the `ansible.builtin.uri`-based task above.

### Under-the-Hood Explanation
`ansible.builtin.uri` (and similar general-purpose modules like `command`, `shell`, `script`) exist precisely to cover narrow, one-off, or infrequent needs without requiring a full custom module — they trade some idempotency/check-mode cleanliness (which a well-written custom module would have natively) for zero additional engineering/maintenance investment, which is the correct trade-off when actual usage is this narrow; a custom module's investment only pays off when amortized across genuinely broad, recurring usage.

### Common Weak Answer
"Building a custom module is always the more professional, better-engineered choice."

### Why the Weak Answer Fails
This ignores the actual cost side of the trade-off — a custom module the organization must now maintain indefinitely (across Python version changes, Ansible API changes, its own bug reports) for a use case touched once a quarter by one team is a poor return on that ongoing investment; "more professional" isn't the same as "proportionate to actual need."

### Follow-Up Questions
1. What would change your recommendation if this same internal API call were actually needed by a dozen teams, weekly?
2. How would you design the `uri`-based task's `changed_when`/`failed_when` logic if the API's response shape were more ambiguous about success/failure than this example?
3. How would you revisit and migrate to a custom module later if usage genuinely grows, without disrupting the existing (narrower) usage?

### Key Interview Signals
Weighs actual usage scale/frequency against the real ongoing cost of a custom module, and doesn't default to "always build the most sophisticated solution" regardless of proportionality.

### Hands-On Connection
[Lab 7 — AWS Configuration Management](../labs/lab-07-aws-configuration-management/).

---

## Question 40: The laptop that drifted from CI

### Scenario
A developer's local Ansible setup (installed via `pip install ansible` over a year ago, updated occasionally and inconsistently) produces a successful playbook run against a test host. The identical playbook, run in CI (which installs `ansible-core` and collections fresh on every run, currently resolving to newer versions than the developer's local setup), fails with a deprecation-turned-removal error on a module argument that changed behavior between the two versions.

### Interview Question
What's the actual, systemic gap here, and how do you close it so "works on my machine" and "works in CI" stop meaning two different things?

### Strong Senior-Level Answer
**Initial assessment:** the developer's local environment and CI's environment are, in effect, two different, uncoordinated Ansible installations — nothing ties them to the same `ansible-core`/collection version set, so of course they can diverge over time, exactly the same class of problem as inconsistent local vs. CI Terraform/provider versions in the companion repository.

**Technical reasoning:** the durable fix is a **pinned Execution Environment** (see [`docs/ansible-architecture.md` §6](../docs/ansible-architecture.md#6-execution-environments--the-air-gappedreproducibility-answer)) — a container image with `ansible-core`, collections, and Python dependencies all pinned to exact versions, used identically for local development (via `ansible-navigator`) and CI, eliminating the entire class of "my environment happens to differ from CI's" discrepancy at the root.

**Investigation process:** confirm the exact version discrepancy (`ansible --version` locally vs. what CI's fresh install resolves to) and cross-reference the specific module argument's changelog for when its behavior changed — this concretely explains the failure without needing further guessing.

**Recommended solution:** build and publish a pinned Execution Environment image via `ansible-builder`, and require every engineer (and CI) to run playbooks through it (`ansible-navigator run` locally, the same image in CI), rather than relying on individually-managed local `pip install ansible` setups that inevitably drift over time:
```yaml
# execution-environment.yml
version: 3
images:
  base_image:
    name: registry.example.com/ee-base:2.16-pinned
dependencies:
  galaxy: requirements.yml
  python: requirements.txt
```
```bash
ansible-builder build -t my-org/ee:2.16.3 -f execution-environment.yml
ansible-navigator run site.yml --execution-environment-image my-org/ee:2.16.3
```

**Risk controls:** version and tag the Execution Environment image deliberately (not `latest`), and treat any update to it as its own reviewed change with a clear changelog, exactly like a Terraform provider version bump.

**Validation steps:** confirm both a developer's local run (via `ansible-navigator` against the pinned EE) and CI's run (using the identical image) now produce identical results for the same playbook — proving the environments are genuinely unified, not just individually patched to work around this one specific version mismatch.

**Rollback or recovery strategy:** not applicable — an environment-standardization fix with no infrastructure-state risk of its own.

**Long-term prevention:** make the pinned Execution Environment the mandatory, only-supported way to run playbooks against anything beyond a personal sandbox, eliminating individually-managed local Ansible installations as a source of drift entirely.

### Step-by-Step Implementation
See the `ansible-builder`/`ansible-navigator` example above.

### Under-the-Hood Explanation
Without a shared, pinned execution environment, every individual `pip install ansible` (or system-package-manager-installed Ansible) and every CI runner's fresh install independently resolves `ansible-core` and collection versions according to whatever constraints (if any) are specified at that moment, from whatever package indices are configured — with no coordination between them, natural drift over time (different install dates, different constraint files, different available versions at each install time) is not just possible but likely; an Execution Environment image collapses this to one specific, versioned, reproducible artifact used identically everywhere.

### Common Weak Answer
"Just tell the developer to update their local Ansible installation."

### Why the Weak Answer Fails
This fixes today's specific instance for one developer but does nothing to prevent the next developer's local environment (or this same developer's environment six months from now) from drifting again — the systemic fix is eliminating individually-managed local installations as a source of truth entirely, via a shared, pinned Execution Environment.

### Follow-Up Questions
1. How would you roll out mandatory Execution Environment usage across an organization with many engineers currently using their own local installations?
2. What's the trade-off of pinning very tightly (exact versions) versus allowing some flexibility (a version range) within the Execution Environment's own dependency specification?
3. How does this same discrepancy risk manifest for AWX/Automation Platform specifically, and how does its own Execution Environment support address it?

### Key Interview Signals
Identifies the systemic root cause (uncoordinated, individually-managed environments) rather than treating this as a one-off version mismatch to patch, and reaches for the Execution Environment pattern as the durable, organization-wide fix.

### Hands-On Connection
[Lab 12 — CI/CD Pipeline](../labs/lab-12-cicd-pipeline/).

---

## Question 41: Ansible behind the wire

### Scenario
Your organization is deploying Ansible-managed configuration into an air-gapped regulated environment with no outbound internet access at all. Both `ansible-core`/collections and the target hosts' package installations need to resolve without ever reaching the public internet.

### Interview Question
Design the offline/air-gapped architecture for this.

### Strong Senior-Level Answer
**Initial assessment:** this needs both an internal substitute for the public Galaxy/Automation Hub (for `ansible-core`/collections) and a substitute for public OS package repositories (for whatever the roles themselves install on target hosts) — two separate, but architecturally similar, mirroring problems.

**Technical reasoning:** the Execution Environment concept (see Question 40) is directly the answer for the first half — build the EE image, with all needed collections/Python dependencies baked in, in a separate, internet-connected build environment, then transfer the resulting image across the air gap through your organization's approved one-way transfer process, exactly mirroring the companion repository's Terraform provider-mirror air-gapped pattern.

**Investigation process:** inventory which collections/roles are actually needed across the organization's air-gapped automation, and confirm whether an internal package mirror (e.g., an internal `yum`/`apt` repository mirror) already exists that roles can be pointed at for target-host package installation, or whether one needs to be stood up specifically for this.

**Recommended solution:** build the pinned Execution Environment image in a connected environment, transfer it across the air gap via the approved process, and load it into an internal container registry reachable from the air-gapped environment; separately, point every role's package-installation tasks at an internal package mirror (already commonly present in regulated environments) rather than public repositories, parameterized so the same role works in both connected and air-gapped environments via a variable, not hardcoded URLs:
```yaml
# group_vars/airgapped.yml
package_repo_base_url: "https://internal-mirror.corp.example/repos"
```

**Risk controls:** treat the cross-air-gap transfer process for the EE image (and any package mirror updates) with the same checksum-verification rigor as the companion repository's Terraform provider-mirror guidance — verify integrity, don't just copy files across trustingly.

**Validation steps:** confirm a full playbook run succeeds inside the air-gapped environment with zero outbound network calls (verifiable via network monitoring/firewall logs showing no attempted egress), using only the transferred EE image and internal package mirror.

**Rollback or recovery strategy:** if an EE image transfer introduces a bad/incompatible version, the fix is re-transferring the previous known-good image — no different in principle from any other environment-image rollback.

**Long-term prevention:** automate and document the EE-build-then-transfer process (rather than ad hoc manual transfers) so keeping the air-gapped environment's Ansible/collection set current doesn't become an entirely manual, error-prone, infrequent chore.

### Step-by-Step Implementation
```bash
# In the connected build environment
ansible-builder build -t my-org/ee-airgapped:2.16.3 -f execution-environment.yml
podman save my-org/ee-airgapped:2.16.3 -o ee-airgapped-2.16.3.tar
# Transfer ee-airgapped-2.16.3.tar across the air gap via the approved process

# In the air-gapped environment
podman load -i ee-airgapped-2.16.3.tar
podman push my-org/ee-airgapped:2.16.3 internal-registry.airgapped.example/my-org/ee-airgapped:2.16.3
ansible-navigator run site.yml --execution-environment-image internal-registry.airgapped.example/my-org/ee-airgapped:2.16.3
```

### Under-the-Hood Explanation
An Execution Environment image is a self-contained container image bundling `ansible-core`, every needed collection, and their Python dependencies — once built, it requires no further network access to *run* Ansible itself (collection resolution already happened at build time, inside the image) — the only remaining network dependency is whatever the *managed hosts'* own package-installation tasks need, which is why pointing those specifically at an internal mirror (rather than public repositories) closes the second half of the air-gap requirement.

### Common Weak Answer
"Just download everything needed manually and copy it over by hand."

### Why the Weak Answer Fails
This describes an ad hoc, per-instance, unrepeatable workaround rather than a systematic, auditable, version-controlled process — a proper Execution Environment build-then-transfer pipeline is the supported, repeatable, checksum-verifiable equivalent, and scales to keeping the air-gapped environment current over time rather than being a one-time manual exercise.

### Follow-Up Questions
1. How would you keep the air-gapped environment's EE image and package mirror current over time without constant manual intervention?
2. What's your process for vetting a brand-new collection or role before it's allowed into the EE build at all?
3. How does this architecture change if different teams within the air-gapped environment need genuinely different, possibly conflicting, sets of approved collections?

### Key Interview Signals
Recognizes the two separate air-gap problems (Ansible/collections itself, and target-host package installation) and designs a systematic, auditable, repeatable solution for both, directly parallel to the companion repository's Terraform air-gapped guidance.

### Hands-On Connection
[Lab 8 — Packer and Ansible AMI Baking](../labs/lab-08-packer-ami-baking/) (the EE/pinning discipline extends directly).

---

## Question 42: One playbook, five AWS accounts

### Scenario
Your organization operates five AWS accounts (dev, staging, production, and two regional production replicas). A single Ansible-driven configuration-management pipeline needs to reach EC2 hosts across all five, each requiring different, account-specific credentials.

### Interview Question
Design the credential and connection architecture for this.

### Strong Senior-Level Answer
**Initial assessment:** exactly the Ansible analog of the companion repository's Terraform provider-aliasing-per-account pattern — one central automation identity assumes narrowly-scoped, per-account roles for the specific account being targeted, never one broad credential (or five separately-stored static credentials) used across every account.

**Technical reasoning:** both the dynamic inventory plugin (resolving hosts per account) and any `amazon.aws`/`community.aws` module calls need account-specific credentials — the `assume_role` parameter (supported by the AWS collections and the dynamic inventory plugin alike) is the mechanism, exactly mirroring Terraform's `assume_role` provider block.

**Investigation process:** confirm the current credential-management approach — if it's five separately-stored static access keys (one per account), that's the actual risk worth addressing, independent of anything else about the pipeline's design.

**Recommended solution:** one central CI/automation identity (ideally OIDC-federated, no long-lived keys at all) assumes a narrowly-scoped, per-account IAM role for whichever account a given run targets:
```yaml
# inventory/production.aws_ec2.yml
plugin: amazon.aws.aws_ec2
regions: [us-east-1]
assume_role_arn: "arn:aws:iam::PRODUCTION_ACCOUNT_ID:role/ansible-automation"
filters:
  tag:Environment: production
```
```ini
# ansible.cfg or per-play vars, for modules needing to call AWS APIs directly
[inventory]
# credentials resolved via the same assume_role pattern per environment/account
```

**Risk controls:** each per-account role should be scoped to only the specific permissions that account's configuration-management tasks actually need — least privilege per account, not one broad cross-account role.

**Validation steps:** confirm each environment's dynamic inventory resolves only its own account's hosts (never accidentally reaching into a different account due to a credential/role misconfiguration), via `ansible-inventory --list` against each environment's specific inventory file.

**Rollback or recovery strategy:** not applicable — a credential-architecture design with no infrastructure-state risk of its own, though correcting an over-broad existing role to proper least privilege should follow the same careful, tested cutover discipline as any IAM policy tightening (see the companion repository's least-privilege-remediation guidance).

**Long-term prevention:** establish per-account, per-environment role assumption (never static per-account credentials) as the standard pattern for any new account added to the fleet going forward.

### Step-by-Step Implementation
See the `assume_role_arn` dynamic-inventory configuration above; the identical pattern applies to any `amazon.aws`/`community.aws` module call needing to act against a specific account.

### Under-the-Hood Explanation
The `amazon.aws` collection's `assume_role_arn` (and related) parameters work by having the underlying boto3/AWS SDK call `sts:AssumeRole` against the specified role ARN before making any subsequent API call (whether for dynamic inventory resolution or a module's own AWS API interaction) — the resulting short-lived, narrowly-scoped credentials are used only for that specific call/run, exactly mirroring how Terraform's own `assume_role` provider block operates, since both ultimately rely on the same underlying AWS STS mechanism.

### Common Weak Answer
"Store five separate AWS access keys, one per account, as CI secrets."

### Why the Weak Answer Fails
Five separate long-lived static credentials multiply the credential-management burden and the blast radius of any single credential leaking, compared to one central, OIDC-federated identity assuming narrowly-scoped, short-lived roles per account — this is exactly the anti-pattern the companion repository's Terraform multi-account guidance warns against, applied here to Ansible's credential architecture.

### Follow-Up Questions
1. How would you extend this pattern to a genuinely multi-cloud scenario (AWS plus Azure plus GCP), not just multiple AWS accounts?
2. What's the risk of a single automation identity's OIDC trust policy being scoped too broadly across all five accounts' assumed roles?
3. How would you audit that each per-account role's permissions are genuinely least-privilege, not just narrower than "one role for everything"?

### Key Interview Signals
Applies the exact same assume-role-per-account, no-long-lived-credentials discipline already established for Terraform in the companion repository, recognizing the underlying AWS STS mechanism is identical regardless of which tool is calling it.

### Hands-On Connection
[Lab 7 — AWS Configuration Management](../labs/lab-07-aws-configuration-management/).
