# Category 14: Migration, Adoption, and Upgrades

Questions 115–117 of 120. Category weight: 3 questions.

---

## Question 115: The Ansible core upgrade that broke everything at once

### Scenario
An organization, running Ansible 2.9 for years, decides to upgrade directly to the latest `ansible-core` version across their entire automation estate in a single, coordinated weekend cutover — motivated by wanting to "get it over with." Multiple playbooks break simultaneously (deprecated syntax removed, collection compatibility issues, changed default behaviors).

### Interview Question
Evaluate this upgrade approach and design a better one.

### Strong Senior-Level Answer
**Initial assessment:** a single, big-bang upgrade across an entire automation estate — especially spanning as many intermediate versions as 2.9 to latest — is exactly the kind of undifferentiated, high-blast-radius change this repository series consistently warns against, mirroring the companion EKS repository's Question 5 (the cluster upgrade that skipped a step) and Question 118's staged-migration guidance.

**Technical reasoning:** `ansible-core` has had multiple significant changes across major versions (the collection-based module distribution model introduced in 2.10, changed default behaviors, removed deprecated syntax) — attempting to absorb all of these simultaneously, across an entire estate of unknown-quality playbooks, makes it extremely difficult to isolate which specific version's change caused which specific breakage, exactly the compounding-changes problem the companion EKS repository's version-skipping guidance identifies.

**Investigation process:** review the actual scope of what changed across the intermediate versions between 2.9 and the target latest version (deprecated syntax removed, collection-splitting changes, default-behavior changes) — this scoping exercise itself reveals how much simultaneous change this single cutover attempted to absorb.

**Recommended solution:** upgrade incrementally, one significant version boundary at a time (mirroring Kubernetes' own one-minor-version-at-a-time discipline), validating the full playbook estate (via `ansible-lint`, Molecule tests, and a staged rollout against non-production first) at each step before proceeding to the next — isolating each version's specific changes and their effects rather than absorbing them all simultaneously.

**Risk controls:** for the current, already-broken state, roll back to the previous, known-working Ansible version while the proper, incremental upgrade path is planned and executed — resist the urge to firefight forward through the compounded breakage without first understanding which specific version boundary caused which specific issue.

**Validation steps:** at each incremental version step, run the full playbook estate's test suite (Molecule, lint) and a staged, non-production validation before considering that step complete and proceeding to the next.

**Rollback or recovery strategy:** maintain the ability to revert to the previous Ansible version at any point during the incremental upgrade if a specific step reveals an issue too complex to resolve quickly — never advancing to the next version boundary with unresolved issues from the current one.

**Long-term prevention:** treat Ansible core version upgrades with the same staged, one-boundary-at-a-time discipline established for Kubernetes cluster upgrades in the companion EKS repository, never accepting "get it over with in one weekend" as sufficient justification for skipping proper, incremental validation.

### Step-by-Step Implementation
```text
Incremental upgrade path (not a single big-bang cutover):
2.9 -> 2.10 (validate: collection-splitting compatibility, run full test suite)
2.10 -> 2.12 (validate: any deprecated syntax removed in this range)
2.12 -> 2.14 (validate: default-behavior changes)
2.14 -> latest (validate: final compatibility check)
Each step: ansible-lint + Molecule test suite + staged non-production validation
  BEFORE proceeding to the next version boundary.
```

### Under-the-Hood Explanation
Each `ansible-core` version boundary can introduce its own specific set of deprecated-syntax removals, default-behavior changes, and collection-compatibility requirements — absorbing several of these boundaries simultaneously means any given observed failure could stem from any of several different version-specific changes, making root-cause isolation significantly harder than if each boundary's changes were validated independently and sequentially.

### Common Weak Answer
"Just fix whatever breaks after the upgrade, one issue at a time."

### Why the Weak Answer Fails
This is a reactive, firefighting approach to a problem that a staged, incremental upgrade would have prevented largely from occurring in the first place — fixing issues after a compounded, multi-version jump is significantly harder to diagnose than validating each version boundary's changes independently and sequentially.

### Follow-Up Questions
1. How would you determine the appropriate incremental version-upgrade path for a specific starting and target version?
2. What's the role of `ansible-lint`'s deprecation-detection capabilities in identifying syntax that will break at a specific future version boundary?
9. How does this directly parallel the companion EKS repository's Question 5 (the cluster upgrade that skipped a step)?

### Key Interview Signals
Recognizes a big-bang Ansible core version upgrade as compounding multiple version boundaries' changes simultaneously, making root-cause isolation difficult, and designs a staged, incremental, validated upgrade path instead.

### Hands-On Connection
[Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).

---

## Question 116: The collection deprecation nobody saw coming

### Scenario
A widely-used community collection the organization depends on for dozens of playbooks announces it's being deprecated and will receive no further updates, with functionality being split across several new, differently-named collections. The organization discovers this only when a routine `ansible-galaxy collection install --upgrade` starts failing.

### Interview Question
Diagnose this dependency-management gap and design a more resilient collection-dependency strategy.

### Strong Senior-Level Answer
**Initial assessment:** discovering a critical dependency's deprecation only when an automated upgrade fails is a reactive-discovery gap — the organization had no proactive visibility into the health/roadmap status of a collection dozens of playbooks depend on, exactly the kind of unmonitored, critical-dependency risk this repository series consistently flags for any single point of failure.

**Technical reasoning:** community-maintained Ansible collections, like any open-source dependency, can be deprecated, restructured, or abandoned with limited advance notice to downstream consumers who aren't actively monitoring the collection's own release notes/community channels — without proactive dependency-health monitoring, an organization only discovers this kind of change reactively, at the worst possible moment (an automated upgrade suddenly failing).

**Investigation process:** confirm the actual scope of the organization's dependency on this specific collection (exactly how many playbooks/roles reference it, and how deeply) and review the deprecating collection's own migration guidance for how functionality is being redistributed across the new collections.

**Recommended solution:** pin the collection to its last-known-working version immediately (via `requirements.yml`'s version constraint) to stop the bleeding, buying time to plan a deliberate migration to the new, redistributed collections — following the same reviewed, tested migration discipline as any other significant dependency change, rather than reactively patching each individual failure as it surfaces.

**Risk controls:** for any critical, widely-depended-upon collection, establish proactive monitoring of its release notes/community activity (a genuinely low-effort, high-value practice) rather than relying on an automated upgrade failure as the sole discovery mechanism.

**Validation steps:** after migrating to the new, redistributed collections, run the full test suite (Molecule, lint) across every affected playbook/role, confirming functional equivalence before considering the migration complete.

**Rollback or recovery strategy:** the immediate version-pin provides a safe, stable rollback point while the fuller migration to new collections is planned and executed deliberately, rather than under reactive time pressure.

**Long-term prevention:** treat every critical, widely-used external dependency (collections, roles, community modules) the same way the companion Terraform/EKS repositories treat provider/chart version pinning — always pinned to a specific, deliberately-chosen version (never floating/unpinned), with periodic, deliberate review of upgrade opportunities and proactive monitoring of upstream deprecation/roadmap signals, rather than discovering critical changes reactively via a failed automated upgrade.

### Step-by-Step Implementation
```yaml
# requirements.yml - pin to last-known-working version immediately
collections:
  - name: community.deprecated_collection
    version: "3.2.1"   # pinned, buying time for a deliberate migration plan
```
```text
Migration plan (deliberate, not reactive):
1. Review the deprecating collection's own migration guidance
2. Map each currently-used module/plugin to its new collection location
3. Update requirements.yml + playbook FQCN references incrementally
4. Run full test suite (Molecule, lint) after each incremental change
5. Complete migration on a planned timeline, not under reactive pressure
```

### Under-the-Hood Explanation
Ansible collections are independently versioned and maintained artifacts, typically by community or vendor teams outside the consuming organization's direct control — without an explicit version pin, `ansible-galaxy collection install --upgrade` will pull whatever the latest available version is, which can include a breaking restructuring or deprecation with no warning beyond whatever the collection's own release notes happen to state, unless someone is actively monitoring for it.

### Common Weak Answer
"Just switch to whatever new collection the community recommends immediately."

### Why the Weak Answer Fails
An immediate, unplanned switch under reactive pressure (the automated upgrade already failing) risks introducing new, unvalidated issues on top of the original disruption — the correct response first stabilizes (pin to the last-working version) before executing a deliberate, tested migration on a reasonable timeline.

### Follow-Up Questions
1. How would you establish proactive monitoring for critical collection dependencies' health/roadmap status going forward?
2. How would you prioritize which of the dozens of affected playbooks to migrate first?
3. How does this connect to the companion Terraform/EKS repositories' provider/chart-version-pinning discipline for critical dependencies?

### Key Interview Signals
Recognizes reactive discovery of a critical dependency's deprecation as a proactive-monitoring gap, and stabilizes first (version pin) before executing a deliberate, tested migration rather than reacting under pressure.

### Hands-On Connection
[Lab 2 — Roles and Structure](../labs/lab-02-roles-and-structure/) and [Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).

---

## Question 117: The migration from Puppet that started with the wrong question

### Scenario
An organization migrating from Puppet to Ansible starts the project by asking engineers to "translate every Puppet manifest to an equivalent Ansible playbook, one-to-one." Several months in, the resulting Ansible codebase is functionally correct but deeply un-idiomatic — heavy use of `command`/`shell` tasks mimicking Puppet's exec resources, no role structure, everything crammed into a handful of massive playbooks.

### Interview Question
Diagnose why "translate one-to-one" was the wrong starting question, and describe the better approach.

### Strong Senior-Level Answer
**Initial assessment:** a literal, one-to-one translation preserves Puppet's own resource-model idioms and structure inside Ansible's syntax, rather than actually re-architecting the configuration management to use Ansible's own idiomatic patterns (proper modules instead of `command`/`shell`, role-based structure, Ansible's own idempotency and variable-precedence models) — the result is functionally working but fails to capture any of the actual, meaningful benefits (maintainability, testability, reusability) a genuine migration should provide.

**Technical reasoning:** Puppet's resource-declaration model and Ansible's task-execution model, while both achieving configuration management, have meaningfully different idioms and strengths — a literal translation optimizes for "get something running in Ansible quickly" at the cost of "actually adopt Ansible's own best practices," exactly the same "same problem, different syntax" mistake the companion EKS repository's Question 1 identifies for Ansible-to-Kubernetes migrations.

**Investigation process:** review a sample of the translated codebase's actual patterns (as described — heavy `command`/`shell` usage, no roles) against genuine Ansible idioms (proper modules, role-based organization, Category 1's idempotency-as-a-contract discipline) — confirming the gap between "functionally works" and "actually idiomatic."

**Recommended solution:** reframe the migration's actual goal from "translate literally" to "re-architect using Ansible's own idioms, informed by what the Puppet manifests were actually trying to accomplish" — starting with genuine role decomposition (per Category 3's guidance), using proper Ansible modules instead of `command`/`shell` wrappers, and applying Ansible's own idempotency/variable-precedence patterns rather than replicating Puppet's resource-model structure inside different syntax.

**Risk controls:** budget genuinely more time for this re-architecture-informed approach than a literal translation would take — the correct approach is more expensive upfront but produces a maintainable, idiomatic result; communicate this trade-off explicitly to stakeholders who may have expected the literal-translation timeline.

**Validation steps:** for the already-translated, non-idiomatic codebase, prioritize which parts most urgently warrant re-architecture (based on how frequently they're modified/maintained) rather than attempting to re-architect everything simultaneously — an incremental, prioritized re-architecture effort.

**Rollback or recovery strategy:** not applicable — this is a migration-approach correction, not an infrastructure change with its own rollback consideration.

**Long-term prevention:** frame any cross-tool migration (Puppet to Ansible, Chef to Ansible, or, per the companion EKS repository, VM-based configuration management to Kubernetes-native) as an opportunity to genuinely adopt the target tool's own idioms and strengths, not merely a syntax-translation exercise — exactly the same lesson established in the companion EKS repository's Question 1 and Question 118.

### Step-by-Step Implementation
```text
Wrong approach: Puppet exec { 'install-package': command => 'yum install -y foo' }
             -> Ansible: command: yum install -y foo  (literal translation)

Right approach: understand the Puppet manifest's actual INTENT (install a package)
             -> Ansible: ansible.builtin.package: { name: foo, state: present }
                (idiomatic module, proper idempotency, no command/shell wrapper)
```

### Under-the-Hood Explanation
A literal translation preserves the *shape* of the original tool's logic (one Puppet resource becomes one Ansible task, often via a generic `command`/`shell` wrapper mimicking Puppet's `exec` resource) without re-deriving the actual, underlying *intent* each resource was accomplishing — genuine re-architecture starts from that intent and expresses it using the target tool's own best, most idiomatic mechanism, which is a fundamentally different (and more valuable) exercise than syntax-level translation.

### Common Weak Answer
"A literal translation is faster and gets us off Puppet sooner, that's the priority."

### Why the Weak Answer Fails
This optimizes for migration speed at the cost of producing a codebase that fails to capture any of Ansible's actual advantages (proper idempotency, testability via Molecule, role-based reuse) — the resulting technical debt (heavy `command`/`shell` usage, no role structure) will cost significantly more to fix later than the time saved by skipping proper re-architecture now.

### Follow-Up Questions
1. How would you prioritize which parts of an already-literally-translated codebase most urgently need re-architecture?
2. How would you communicate the trade-off (slower but genuinely idiomatic migration) to stakeholders expecting a faster timeline?
3. How does this connect directly to the companion EKS repository's Question 1 (the playbook that tried to configure Kubernetes) and Question 118 (the legacy migration strategy)?

### Key Interview Signals
Recognizes that a literal, tool-to-tool translation fails to capture the target tool's actual idiomatic strengths, and reframes the migration around re-deriving original intent and expressing it using Ansible's own best practices, explicitly connecting this to the identical lesson established in the companion EKS repository.

### Hands-On Connection
[Lab 2 — Roles and Structure](../labs/lab-02-roles-and-structure/) and [Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).
