# Category 3: Roles, Collections, and Reuse

Questions 23–34 of 120. Category weight: 12 questions. Deep-dive reference: [`docs/role-design.md`](../docs/role-design.md).

---

## Question 23: The role update that broke thirty playbooks

### Scenario
Your platform team publishes a shared `security-baseline` role used by roughly thirty application playbooks, each pinned with `version: ">=2.0.0"`. A minor-looking change — renaming the `baseline_ssh_port` variable to `security_baseline_ssh_port` for consistency with the naming convention from [Question 22](02-inventory-variables.md#question-22-the-variable-that-meant-two-different-things) — ships as `2.6.0`. Within hours, dozens of consuming playbooks start silently applying the *default* SSH port instead of their previously-configured custom ports, since the old variable name is simply no longer referenced by the role at all.

### Interview Question
Diagnose the root cause and redesign the role's release process so this can't happen again.

### Strong Senior-Level Answer
**Initial assessment:** two compounding failures: an unconstrained consumer version range (`>=2.0.0` floats onto any future release, including breaking ones) and a variable rename shipped as a minor version bump when it's unambiguously a breaking interface change — worse, this specific kind of breakage (an old variable name silently ignored rather than erroring) is especially dangerous because it fails **silently**, applying a wrong default instead of an obvious error.

**Technical reasoning:** Ansible has no equivalent of a compile-time "unknown variable" error for a role simply no longer referencing a variable a consumer still sets — a consumer still setting `baseline_ssh_port: 2222` after the rename simply has that variable silently ignored (it's not referenced by any task anymore), and the role quietly falls back to its own new default for `security_baseline_ssh_port`, with zero indication anything is wrong.

**Investigation process:** confirm the actual `security-baseline` role diff between `2.5.x` and `2.6.0`, and confirm this is indeed a bare rename with no backward-compatible alias — this is the finding that explains the silent-wrong-port behavior precisely.

**Recommended solution:** immediately patch a backward-compatible release restoring support for the old name (accepting either, preferring the new one if both are set, warning if only the old one is used) to stop the silent breakage:
```yaml
# roles/security-baseline/tasks/main.yml
- name: Warn if using the deprecated variable name
  ansible.builtin.debug:
    msg: "baseline_ssh_port is deprecated, use security_baseline_ssh_port instead. Support for the old name will be removed in 3.0.0."
  when: baseline_ssh_port is defined and security_baseline_ssh_port is not defined

- name: Resolve the effective SSH port, preferring the new name
  ansible.builtin.set_fact:
    _effective_ssh_port: "{{ security_baseline_ssh_port | default(baseline_ssh_port) | default(22) }}"
```
Ship the actual rename as a proper major version (`3.0.0`) with a migration guide, after a deprecation window where both names work and the old one warns.

**Risk controls:** mandate that any role variable rename/removal requires a major version bump *and* a deprecation-aliasing period — never a same-release swap — and require every consumer to pin with a constrained range (`>=2.6.0,<3.0.0`), never an unconstrained `>=`.

**Validation steps:** a contract-test matrix (§ below, Question 30's full treatment) running the new role version's Molecule scenario **plus** a representative sample of real consuming playbooks' own scenarios, specifically checking that previously-set custom values (like a non-default SSH port) still take effect after the "update," would have caught this before release.

**Rollback or recovery strategy:** consumers roll back via their own version constraint to the last good version; audit every affected host for whether it's actually running on the wrong (default) SSH port right now and correct immediately, since this is a live security-relevant misconfiguration, not just a cosmetic issue.

**Long-term prevention:** semver discipline enforced via a required CHANGELOG classification on every role PR, contract testing before any major release, and consumer-side constrained version pinning enforced via a lint/policy check on consuming repositories.

### Step-by-Step Implementation
See the deprecation-aliasing example above; pair with `requirements.yml` pinning discipline (`version: ">=2.6.0,<3.0.0"`) on the consumer side.

### Under-the-Hood Explanation
A role's tasks reference whatever variable names they're written to reference — renaming a variable in the role's task files means any consumer still setting the *old* name simply has that value sitting unused in the variable namespace, silently ignored by every task, while the role's own (possibly very different) default or newly-named variable takes over. There is no mechanism, in Ansible itself, that would warn "you set a variable this role doesn't reference" — this is exactly why the silent-failure risk here is higher than a typical "renamed and now errors" breaking change; it doesn't error at all, it just quietly does something different than intended.

### Common Weak Answer
"We should test roles before releasing them."

### Why the Weak Answer Fails
Too generic — doesn't identify the two specific, fixable root causes (unconstrained consumer pinning, and a silent-rename misclassified as non-breaking) or propose the concrete mechanisms (semver discipline, deprecation aliasing, contract testing) that actually prevent recurrence, and doesn't address why this specific class of change (a rename with no error on the old name) is more dangerous than an obviously-breaking change.

### Follow-Up Questions
1. How would you retrofit constrained version pinning across all thirty existing consumers?
2. Why is a silently-ignored old variable name more dangerous than a role that would instead throw an explicit "unknown variable" error — and is there any way to get closer to the latter in Ansible?
3. How would you design a contract-test matrix specifically to catch "a previously-set custom value silently stopped taking effect" as opposed to just "the role errors or fails"?

### Key Interview Signals
Identifies both root causes, recognizes the silent (not error-producing) nature of this specific breaking-change class as uniquely dangerous, and proposes concrete process fixes rather than "test more."

### Hands-On Connection
[Lab 2 — Roles and Structure](../labs/lab-02-roles-and-structure/) and [Lab 11 — Molecule Testing](../labs/lab-11-molecule-testing/).

---

## Question 24: The role that depended on itself

### Scenario
A `webserver` role's `meta/main.yml` lists a dependency on `network-config`, and `network-config`'s own `meta/main.yml` lists a dependency back on `webserver` (added later, by a different engineer, to ensure "the webserver's expected ports are documented in the network role's comments" — a weak justification that nonetheless created a real cycle). Running any playbook using either role now fails immediately with a dependency-resolution error.

### Interview Question
Explain what's actually gone wrong here and redesign it.

### Strong Senior-Level Answer
**Initial assessment:** a genuine circular role dependency — Ansible resolves `meta/main.yml` dependencies before running a role's own tasks, and a cycle here (A depends on B, B depends on A) has no valid resolution order, exactly mirroring the Terraform circular-module-dependency problem covered in the companion repository.

**Technical reasoning:** the specific justification given ("so the webserver's ports are documented in the network role") isn't a genuine functional dependency at all — it's a documentation/comment-only justification that never should have been expressed as an executable `meta/main.yml` dependency in the first place.

**Investigation process:** confirm via each role's `meta/main.yml` exactly what the claimed dependency reasoning is — this quickly reveals whether it's a genuine functional need (network-config's tasks actually require something webserver's tasks produce) or, as here, a weak, non-functional justification that shouldn't have created an executable dependency at all.

**Recommended solution:** remove the `network-config → webserver` dependency entirely (since its justification was documentation, not function) — if the actual desire is "network-config's comments/docs reference webserver's expected ports," that's better served by a plain code comment or a shared variable both roles reference (e.g., both consuming a `webserver_port` variable defined once in `group_vars`, with no directional role dependency needed at all).

**Risk controls:** apply a standing review question to any new `meta/main.yml` dependency: "does this role's *tasks* genuinely require something the other role's tasks produce, or is this a weaker, non-functional justification (documentation, convention, 'it made sense at the time')?" — only the former justifies an executable dependency.

**Validation steps:** after removing the cycle, confirm both roles can be used independently (a Molecule scenario for each, not requiring the other) and confirm a playbook using both together still produces the correct combined result via the two `roles:` list entries alone, with no implicit dependency needed.

**Rollback or recovery strategy:** not applicable — a design-time fix, no infrastructure impact, since the cycle was caught as an immediate dependency-resolution error before anything could run.

**Long-term prevention:** during role design review, explicitly diagram cross-role dependencies (the same discipline recommended for Terraform module design in the companion repository) before implementation, treating a circular arrow on that diagram as the same red flag whether or not it's yet expressed in `meta/main.yml`.

### Step-by-Step Implementation
```yaml
# Before: genuine cycle
# roles/webserver/meta/main.yml
dependencies:
  - role: network-config

# roles/network-config/meta/main.yml
dependencies:
  - role: webserver   # weak justification, creates the cycle

# After: no dependency at all - both consume a shared, independently-defined variable
# group_vars/all.yml
webserver_port: 8080
# Both roles' tasks/templates reference {{ webserver_port }} directly,
# with no role-to-role dependency required
```

### Under-the-Hood Explanation
Ansible resolves `meta/main.yml` dependencies recursively, before running a role's own task list, building an implicit ordering graph much like Terraform's resource dependency graph — a genuine cycle here (A's dependency resolution requires B, whose dependency resolution requires A) has no valid topological order, and Ansible detects and errors on this rather than guessing an arbitrary order, exactly mirroring the companion repository's explanation of Terraform's own cycle-detection behavior.

### Common Weak Answer
"Just remove one of the two dependency declarations, whichever seems less important."

### Why the Weak Answer Fails
This might mechanically break the cycle, but without first understanding *why* each dependency was added (which one, if either, reflects a genuine functional need versus a weak justification), you risk removing a dependency that some consuming playbook was silently and correctly relying on — the investigation into *why* each dependency exists has to come before deciding which (if either) is legitimate to keep.

### Follow-Up Questions
1. How would you catch this kind of weak, non-functional dependency justification during code review, before it's ever merged?
2. What's the difference between this cycle and a legitimate two-phase relationship within a single playbook (e.g., a role that must run before another, expressed via explicit `roles:` list ordering rather than `meta/main.yml`)?
3. If both roles genuinely need to share configuration values, is a `meta/main.yml` dependency ever the right way to achieve that, or is a shared variable always preferable?

### Key Interview Signals
Confirms the candidate recognizes a cycle as a modeling/justification problem (not just a mechanical resolution error to route around) and investigates *why* each dependency exists before deciding how to break the cycle.

### Hands-On Connection
[Lab 2 — Roles and Structure](../labs/lab-02-roles-and-structure/).

---

## Question 25: The role with fifty conditional variables

### Scenario
An internal `app-server` role has grown to accept over fifty optional variables covering every conceivable configuration across every team that's ever used it — toggling individual config directives, feature flags, log formats, and more. New engineers regularly misconfigure it, and the role's own Molecule test suite covers only a handful of the possible variable combinations.

### Interview Question
How would you redesign this role's philosophy?

### Strong Senior-Level Answer
**Initial assessment:** exactly the Ansible analog of the Terraform "fifty optional variables" module anti-pattern — this role optimized for flexibility at the cost of having no real opinion, which pushes the burden of getting every configuration decision right onto each individual consumer, and mistakes proliferate exactly as described.

**Technical reasoning:** an opinionated role encodes the organization's actual standards as defaults and exposes only the small set of genuinely-varying inputs; a role with fifty independent, orthogonal booleans is unmaintainable and untestable (the combinatorial space of fifty independent variables is not something any realistic test suite can cover).

**Investigation process:** audit actual usage across consumers — of the fifty variables, how many are actually set to non-default values in practice, and by how many distinct consumers? This usually reveals the real variance is a handful of genuinely-differing inputs, with the rest either always left at default or always set to the same value everywhere.

**Recommended solution:** redesign around a small, opinionated core (an enum-style `app_server_tier` variable driving a small, curated set of internal decisions, rather than fifty independent booleans), with a single, narrow, explicitly-reviewed escape hatch for genuine, rare exceptions:
```yaml
# Before: fifty independent, unopinionated variables
# After:
app_server_tier: "standard"   # enum: minimal | standard | high-throughput
app_server_overrides: {}       # narrow, reviewed escape hatch only - not a blanket pass-through
```

**Risk controls:** ship this as a major version with a migration guide, since narrowing the interface is itself a breaking change for any consumer using a variable being removed from the public surface.

**Validation steps:** with a small input space (an enum plus a narrow override), genuinely exhaustive Molecule coverage becomes achievable — test every enum value plus a representative override case, closing the coverage gap the fifty-variable version could never realistically close.

**Rollback or recovery strategy:** offer the new opinionated role as a new major version while the old flexible one remains available and deprecated for a defined window, letting consumers migrate at their own pace rather than a forced simultaneous cutover.

**Long-term prevention:** establish a design-review gate for any new role variable, asking whether it represents a genuine, recurring, multi-consumer need or a one-off convenience for a single team — the same discipline as the companion repository's Terraform module design guidance.

### Step-by-Step Implementation
See the `app_server_tier` enum example above; pair with `argument_specs.yml` validating the enum's allowed values.

### Under-the-Hood Explanation
This is purely a role-interface design decision — Ansible itself has no preference between a flexible or opinionated role. The practical, measurable benefit of a narrow input space is combinatorial: Molecule test coverage of N largely-independent variables requires testing a combinatorial space that grows with N, so shrinking fifty independent variables to a handful of interdependent, validated ones (an enum plus a narrow override) makes genuinely exhaustive coverage achievable rather than aspirational.

### Common Weak Answer
"Add more documentation so people know how to use all fifty options correctly."

### Why the Weak Answer Fails
Documentation doesn't reduce the actual combinatorial misuse surface — it asks every consumer to correctly navigate fifty options by reading carefully, the same failure mode already observed; the structural fix reduces the surface area itself.

### Follow-Up Questions
1. How do you handle the genuine outlier consumer who needs something the opinionated defaults don't support, without immediately re-expanding back to fifty variables?
2. How would you migrate existing consumers from the old flexible role to the new opinionated one with minimal disruption?
3. Is there a case where a fully flexible role is still the right design?

### Key Interview Signals
Distinguishes "flexibility is always good" thinking from a deliberate, opinionated-by-default design appropriate for application-facing roles.

### Hands-On Connection
[Lab 2 — Roles and Structure](../labs/lab-02-roles-and-structure/).

---

## Question 26: The README that lied

### Scenario
A role's hand-maintained `README.md` documents twelve input variables. The actual role, after over a year of incremental changes, has twenty-one — the other nine were added without updating the README. A new engineer, following the README, misses a security-relevant variable entirely and ships a host with a materially weaker default than intended.

### Interview Question
How do you prevent role documentation from silently going stale like this, and what should have caught the specific missed security-relevant variable?

### Strong Senior-Level Answer
**Initial assessment:** hand-maintained documentation for a role's variable reference is fundamentally unreliable at scale — the moment updating the README becomes a manual, easily-forgotten second step alongside a code change, it will drift, exactly as happened here over a year of incremental changes.

**Technical reasoning:** the fix is generating the reference documentation directly from the role's actual, executable source of truth rather than maintaining separate prose describing it.

**Investigation process:** confirm the actual, current, correct interface directly from the role's `defaults/main.yml`/`argument_specs.yml` (never trust the stale README during this audit), and specifically flag the missed security-relevant variable — was its default actually appropriate, or does this incident reveal it should have been required (forcing an explicit choice) rather than silently defaulted?

**Recommended solution:** adopt `argument_specs.yml` as the single source of truth for the role's interface (see [`docs/role-design.md` §3](../docs/role-design.md#3-argument_specsyml--validated-role-interfaces-ansible-core--211)) — this gives you both `ansible-doc`-integrated, always-current documentation generation *and* actual runtime validation, closing the gap a purely-documentation-only fix (like `terraform-docs` for the companion repository) wouldn't fully close on its own, since Ansible has no compile-time type checking otherwise. Wire a CI check confirming the README's variable table (if you still keep one for human-readability) is regenerated from `argument_specs.yml`, failing the PR if they've diverged.

**Risk controls:** for the specific missed security-relevant variable, consider promoting it to `required: true` in `argument_specs.yml` rather than leaving it optional-with-a-default — forcing every consumer to make an explicit, conscious choice rather than silently inheriting a default they never saw documented.

**Validation steps:** deliberately add a new variable in a test PR without updating `argument_specs.yml`/regenerated docs and confirm the CI check actually fails, proving the gate works before relying on it.

**Rollback or recovery strategy:** not applicable to the tooling fix; separately, audit any hosts already configured with the missed security-relevant variable at its (possibly-too-weak) default, and correct them.

**Long-term prevention:** apply `argument_specs.yml` plus generated-docs-CI-gate discipline to every reusable role in the organization, not just this one — stale documentation is a systemic risk across the whole role library, not unique to this role.

### Step-by-Step Implementation
```yaml
# roles/app-server/meta/argument_specs.yml — single source of truth
argument_specs:
  main:
    options:
      app_server_enable_tls:
        type: bool
        required: true   # promoted from optional-with-default, given the incident
        description: Whether to enforce TLS - no default, must be an explicit, conscious choice.
```
```bash
ansible-doc -t role app-server   # documentation generated directly from argument_specs.yml, always current
```

### Under-the-Hood Explanation
`argument_specs.yml` is read by `ansible-doc` and, at runtime, by Ansible's own role-invocation validation logic — a required option genuinely missing from a caller's invocation produces an immediate, clear validation error before the role's tasks even begin, and `ansible-doc`'s generated output is always derived directly from this same file, meaning it's structurally impossible for the generated documentation to drift from the role's actual, enforced interface the way a separately hand-maintained README can.

### Common Weak Answer
"Remind the team to update the README whenever they add a variable."

### Why the Weak Answer Fails
This is the exact process that already failed for over a year across nine added variables — the fix needs to make out-of-date documentation mechanically impossible or immediately caught, not dependent on every future contributor remembering.

### Follow-Up Questions
1. How would you handle documentation for role *behavior* that isn't just an input/output list (e.g., "this role assumes Python 3 is already available on the target")?
2. Should the missed security-relevant variable have been required from the start — how do you decide required vs. optional-with-a-safe-default in general?
3. How would you audit whether other roles in your library have the same documentation-drift problem right now?

### Key Interview Signals
Reaches for an automated, validated solution (`argument_specs.yml` plus a CI gate) over a process reminder, and separately considers whether the missed variable's design (optional-with-default vs. required) contributed to the incident.

### Hands-On Connection
[Lab 2 — Roles and Structure](../labs/lab-02-roles-and-structure/).

---

## Question 27: The role that only told you the port

### Scenario
Your organization's shared `database` role outputs (via `set_fact`, meant for consuming playbooks to reference) only `database_port`. Every one of a half-dozen consuming playbooks independently derives the database's connection string, credentials-secret path, and backup-schedule details by re-implementing the same logic against the role's *internal* variable names (which happen to be readable, but were never intended as a public interface) — and two playbooks' re-derivations have subtly diverging bugs.

### Interview Question
What's wrong with this role's output design, and how do you fix it without breaking the six existing consumers?

### Strong Senior-Level Answer
**Initial assessment:** the role's output surface is under-designed — exposing only the bare minimum (`database_port`) forces every consumer to reach into and re-derive from the role's *internal* variables (never intended as a public contract) rather than receiving the values they actually, legitimately need directly and reliably from the role itself.

**Technical reasoning:** a role's outputs (whatever it deliberately exposes via `set_fact`/registered facts meant for consumption, or documented in its interface) should describe what the role *guarantees to provide*, not the smallest technically-sufficient set — exactly the same lesson as the companion repository's "VPC module that only gave you an ID" scenario.

**Investigation process:** survey the six consumers' independent re-derivation logic to catalog exactly what they're all trying to obtain — this is almost always near-identical, redundant logic, the clearest signal the role should provide it directly rather than leaving every consumer to reinvent it, with the diverging bugs in two consumers being direct proof of the risk this pattern creates.

**Recommended solution:** add new, deliberately-named, documented outputs (`database_connection_string`, `database_secret_path`, `database_backup_schedule`) via `set_fact` as a purely additive change — no existing consumer is affected, and new/updating consumers can migrate off their fragile re-derivation logic onto the role's own guaranteed outputs at their own pace:
```yaml
# roles/database/tasks/main.yml, near the end
- name: Expose the role's public output contract
  ansible.builtin.set_fact:
    database_connection_string: "postgresql://{{ database_host }}:{{ database_port }}/{{ database_name }}"
    database_secret_path: "{{ vault_secret_mount }}/database/{{ inventory_hostname }}"
```

**Risk controls:** don't remove consumers' ability to still derive their own values if they have a genuine reason — the fix is *adding* a better, guaranteed path, not restricting existing flexibility, avoiding any breaking change for this specific fix.

**Validation steps:** for each migrating consumer, confirm their playbook's behavior is unchanged (same connection string, same secret path) after switching from their own re-derivation to the role's direct output — a Molecule scenario asserting the role's output facts match the previously-independently-derived values is the durable proof.

**Rollback or recovery strategy:** since this is purely additive, no rollback risk to the role itself; a migrating consumer can revert to their own prior logic independently if something looks wrong, with no coordination needed with other consumers.

**Long-term prevention:** during role output design review, ask "what will every reasonable consumer need to derive about this role's managed resource" and provide those directly, rather than waiting for consumers to independently discover the gap via fragile, divergent re-derivation.

### Step-by-Step Implementation
See the `set_fact`-based output example above.

### Under-the-Hood Explanation
`set_fact` registers a value into the host's fact namespace, available to any subsequent task/role in the same play (including ones running after this role, referencing these facts directly) — there's no mechanical constraint forcing a minimal output surface; the under-design here is purely an authoring choice. Adding new `set_fact` outputs is unconditionally backward-compatible from Ansible's perspective (existing consumers who don't reference the new facts are entirely unaffected), exactly mirroring why adding new Terraform module outputs is a safe, additive, minor-version change.

### Common Weak Answer
"Tell the two teams with buggy re-derivation logic to fix their bugs."

### Why the Weak Answer Fails
This fixes two symptoms while leaving the systemic cause (every consumer independently reimplementing the same derivation) in place for the other four teams, who will eventually hit the same class of bug with their own slightly-different-but-still-fragile logic.

### Follow-Up Questions
1. How would you decide how granular the role's output surface should be, without over-designing the interface?
2. What's the risk of exposing *too much* — every internal variable as a fact — and how does that differ from this under-design problem?
3. How would you encourage the existing four correctly-working (if fragile) consumers to migrate, without forcing a disruptive simultaneous cutover?

### Key Interview Signals
Treats role output design as a deliberate interface decision (what should consumers be guaranteed) rather than an afterthought, and recognizes the two buggy consumers as symptoms of a systemic under-design, not isolated mistakes.

### Hands-On Connection
[Lab 2 — Roles and Structure](../labs/lab-02-roles-and-structure/).

---

## Question 28: The "patch" that changed real behavior

### Scenario
A role author ships what they label a patch release (`3.1.4` → `3.1.5`) fixing a typo in a default log-rotation schedule comment. Every consumer's next run shows the log-rotation configuration file being rewritten — expected and harmless — except one consumer's role invocation shows a full **service restart** being triggered, because their environment happens to have a handler wired to notify on *any* change to files under the log-rotation config directory, including this one.

### Interview Question
Was this actually a safe patch release? How do you prevent this class of surprise?

### Strong Senior-Level Answer
**Initial assessment:** the role change was genuinely trivial in intent (a comment-only fix), but its real-world impact depends on the *consumer's own handler wiring*, which the role author can't fully predict or control — a subtler failure mode than a clear-cut breaking interface change, directly analogous to the Terraform "patch that forced replacement" scenario in the companion repository.

**Technical reasoning:** semantic versioning classifies changes by *interface* impact, but a content change to a managed file can have *side-effect* impact (triggering a consumer's own handler) depending entirely on how that consumer has wired their own notifications — something not visible from the role's own task/template diff alone.

**Investigation process:** confirm the specific handler wiring in the affected consumer's playbook — is it genuinely notified on *any* change to the config directory (a broad, perhaps overly-broad handler trigger), or something narrower that shouldn't have fired for a comment-only change?

**Recommended solution:** for the specific incident, the affected consumer's handler trigger is arguably too broad (notifying a full service restart on *any* file change in a directory, rather than specifically the substantive config values) — but the role author should also, going forward, test any change (even a "trivial" one) via the contract-test matrix (§ Question 30) checking for unexpected side effects across representative real consumer configurations, not just "does the role's own logic still work."

**Risk controls:** for template/config content changes specifically, consider whether the change could plausibly alter the *rendered* file's content in a way that would trigger any reasonable consumer's change-detection/handlers, even for comment-only intent — if in doubt, treat it with the same caution as a substantive change.

**Validation steps:** the contract-test matrix's plan/diff output, run against representative consumer configurations, should specifically flag any *unexpected* handler notification (a "changed" result triggering a notify that wasn't expected for this class of release), not just whether the role's own tasks succeed.

**Rollback or recovery strategy:** if the unwanted restart already occurred and caused disruption, that's a real (if likely minor, for a comment-only change) incident — assess actual impact and communicate to the affected consumer team; going forward, revert the role change if this exact scenario recurs and isn't easily preventable.

**Long-term prevention:** treat "does this change risk triggering any consumer's handler unexpectedly" as a standard pre-release check for any role-authored file/template content change, however trivial the stated intent.

### Step-by-Step Implementation
```yaml
# Consumer's own handler wiring — arguably too broad, triggers on ANY change
# in the directory, not just substantive config values
- name: Update log rotation config
  ansible.builtin.template:
    src: logrotate.conf.j2
    dest: /etc/logrotate.d/app
  notify: restart app service   # fires even for a comment-only content change

# A narrower, more deliberate consumer-side handler wiring would avoid this class
# of surprise, but the role author should still test for it proactively
```

### Under-the-Hood Explanation
Whether a template's rendered content differs (and thus reports `changed: true`, potentially triggering any consumer-side `notify`) is a pure content comparison — a comment-only change to the template source still produces genuinely different rendered output, which `changed_when`-equivalent logic for `template` correctly and accurately detects as a change; this is provider-schema-equivalent behavior entirely outside the role author's control once a consumer has wired their own handler to that file's change status, which is exactly why a role author can ship a change that looks harmless in the role's own diff but has real side-effect impact for specific consumer wiring.

### Common Weak Answer
"Patch releases are safe by definition since they're just bug fixes — the consumer's handler must be misconfigured."

### Why the Weak Answer Fails
It's not necessarily a consumer misconfiguration — a handler notifying on any change to a config directory is a common, reasonable pattern; the role release process failed to check the real-world side-effect impact of a seemingly-minor content change before calling it safe, and both the role author's process and the consumer's handler granularity are worth examining, not just one or the other.

### Follow-Up Questions
1. How would you build automated tooling to check "does this content change risk triggering unexpected consumer handlers" without manually inspecting every consumer's wiring each time?
2. How does this risk change across a role *major* version upgrade with genuinely substantive content changes, versus this comment-only patch?
3. Should a role ever hard-code awareness of how consumers might wire their own handlers, or is that too tightly coupling the role to consumer-side concerns it shouldn't need to know about?

### Key Interview Signals
Recognizes that a role's semver classification and its real side-effect impact on consumers (via their own handler wiring) can diverge, requiring an explicit check beyond "is this an interface change," and considers both the role-author and consumer-side contributing factors.

### Hands-On Connection
[Lab 11 — Molecule Testing](../labs/lab-11-molecule-testing/).

---

## Question 29: Retiring the ad hoc Git-tag roles

### Scenario
Your organization's thirty-plus internal roles are currently referenced via raw Git URLs with `?ref=` tags (`git+https://github.com/my-org/roles.git,v3.2.0`) scattered inconsistently across `requirements.yml` files, with no central visibility into which consumers use which role versions.

### Interview Question
Would you migrate to a private Automation Hub / Galaxy-compatible registry, and how would you execute that migration with minimal disruption?

### Strong Senior-Level Answer
**Initial assessment:** yes — a private registry provides namespaced, discoverable source addresses, listed version history, and (in Automation Hub specifically) consumer/usage visibility that raw Git-tag sourcing has none of, exactly mirroring the companion repository's Terraform private-registry migration reasoning.

**Technical reasoning:** the migration is purely a `requirements.yml` source/version change per consumer — the role content itself doesn't need to change, since a registry can be backed by the same Git repository's tags.

**Investigation process:** inventory current usage — for each of the thirty roles, which consumers reference which ref, and are those refs already valid semver tags, or inconsistent ad hoc naming needing cleanup before migration.

**Recommended solution:** stand up the private registry pointing at the existing Git repository, publish existing tags as registry versions, then migrate consumers incrementally — each consumer's `requirements.yml` entry changes from a raw Git URL to a namespaced registry reference, verified via a Molecule/idempotence-equivalent check (a no-op run confirming the role's actual behavior against real inventory is unchanged, since only the sourcing mechanism changed, not the role content).

**Risk controls:** migrate a small number of low-risk consumers first to validate the registry setup end-to-end before rolling out broadly.

**Validation steps:** for each migrated consumer, confirm `ansible-galaxy install -r requirements.yml` resolves the identical role content/version as before, and a subsequent playbook run behaves identically.

**Rollback or recovery strategy:** each consumer's migration is independent and reversible (revert their own `requirements.yml` entry) if the registry has an issue.

**Long-term prevention:** once migrated, enforce (via convention/code review, or a lint check on consumer repos) that all new role consumption uses the registry address, not raw Git URLs.

### Step-by-Step Implementation
```yaml
# Before
# requirements.yml
roles:
  - src: git+https://github.com/my-org/roles.git
    name: security-baseline
    version: v3.2.0

# After
roles:
  - name: my_org.security_baseline
    version: ">=3.2.0,<4.0.0"
```

### Under-the-Hood Explanation
A private Automation Hub / Galaxy-compatible server is, at its core, an index mapping namespaced role/collection addresses and version strings to underlying source archives, typically generated directly from the same Git tags already in use — `ansible-galaxy install` resolves the registry address via the registry's own API instead of directly cloning a Git ref, but the actual content downloaded is generally identical to what the equivalent tagged checkout would produce, exactly mirroring the companion repository's Terraform private-module-registry explanation.

### Common Weak Answer
"Just tell everyone to switch to the registry going forward for new usage."

### Why the Weak Answer Fails
This leaves the exact operational blindness described (no central visibility into version usage) unresolved for all existing consumption, which is the majority of the actual problem — a registry only delivers its visibility/discoverability benefit once consumers are actually using it.

### Follow-Up Questions
1. How would you handle role versions that were never given proper semver tags in the original Git-based scheme?
2. What additional value does Automation Hub provide beyond addressing — how does it change your release process from Question 23?
3. How would you handle this migration for an organization without Ansible Automation Platform access, using a different Galaxy-compatible private registry?

### Key Interview Signals
Executes a low-risk, incremental migration rather than a disruptive cutover, and understands what a registry actually adds operationally beyond nicer source strings.

### Hands-On Connection
[Lab 2 — Roles and Structure](../labs/lab-02-roles-and-structure/).

---

## Question 30: Proving a new role version won't break anyone before you ship it

### Scenario
Your platform team wants to publish a major version of the `database` role changing several defaults (enabling encrypted-at-rest storage configuration by default, changing the default backup retention). Given the role has around twenty known consumers, leadership wants confidence this won't repeat the Question 23 incident before it ships.

### Interview Question
Design the pre-release validation process.

### Strong Senior-Level Answer
**Initial assessment:** this calls for contract testing — validating the new role version against a representative sample of real consumer playbooks, not just the role's own isolated Molecule scenario, since the risk here is specifically about *consumer* impact.

**Technical reasoning:** the role's own Molecule suite (unit/converge-mode tests against synthetic inputs) verifies the role's internal logic is correct, but says nothing about whether *actual* consumers, with their actual existing variable overrides and target-host state, would see unacceptable behavior (an unexpected `changed`/`failed` result, or a silent behavior change) from adopting the new version.

**Investigation process:** pull a representative sample of the twenty consumers' actual role-invocation configurations (their variable overrides) — ideally all twenty if feasible, or a sample weighted toward those managing the most critical hosts.

**Recommended solution:** build a CI job that, for each sampled consumer configuration, pins the *new* role version, runs the consuming playbook in `--check --diff` mode (or a full Molecule converge against a representative container, where feasible) against a copy of their actual target state, and asserts: no unexpected `failed` results, and any `changed` results are limited to the expected set (e.g., encryption configuration flipping on, backup retention changing — both expected, in-place changes, not anything indicating a broken invocation). Any consumer configuration producing an unexpected result blocks the release until investigated.

**Risk controls:** for the specific new defaults chosen here (encryption on, longer backups) — these are safety-increasing changes, so the main risk isn't data loss from the role change itself, but unexpected task failures if a given consumer's target database engine/version doesn't actually support the newly-defaulted-on feature the same way.

**Validation steps:** the contract-test matrix passing cleanly across all twenty (or the representative sample) is the release gate — not merely "the role's own Molecule tests pass."

**Rollback or recovery strategy:** ship behind a documented migration guide regardless of clean contract-test results, since real consumer state can still surface an edge case the sampled configurations didn't cover; be prepared to patch quickly if a consumer outside the sample hits an issue.

**Long-term prevention:** make this contract-test matrix a standing CI job (not a one-off exercise for this release) that runs automatically against every future major version candidate for this role.

### Step-by-Step Implementation
```bash
# Conceptual contract-test harness
for consumer in $(cat consumer-configs.list); do
  cp -r "fixtures/${consumer}" "workdir/${consumer}"
  # pin the new role version in this consumer's requirements.yml
  sed -i 's/version: ">=3\..*"/version: ">=4.0.0,<5.0.0"/' "workdir/${consumer}/requirements.yml"
  ansible-galaxy install -r "workdir/${consumer}/requirements.yml" -p "workdir/${consumer}/roles"
  ansible-playbook -i "workdir/${consumer}/inventory" "workdir/${consumer}/site.yml" --check --diff > "workdir/${consumer}/result.log"
  grep -q "failed=0" "workdir/${consumer}/result.log" || { echo "FAIL: ${consumer}"; exit 1; }
done
```

### Under-the-Hood Explanation
This is entirely orchestration around standard `ansible-playbook --check --diff` (or full Molecule converge) invocations against real, representative consumer fixtures — the contract-testing insight isn't a new Ansible feature, it's applying the existing check-mode/converge tooling programmatically across many real consumer configurations instead of just the role's own synthetic test scenario, specifically watching for unexpected `failed`/`changed` results that reveal a real-world break the role's own isolated tests wouldn't surface.

### Common Weak Answer
"Run the role's Molecule test suite and if it passes, ship it."

### Why the Weak Answer Fails
The role's own Molecule suite validates the role in isolation against synthetic fixtures — it cannot catch an issue that only manifests against a specific real consumer's actual accumulated variable overrides and target state, exactly the class of problem that caused the Question 23 incident.

### Follow-Up Questions
1. How do you keep the representative-consumer fixture set up to date as consumers' own configurations evolve over time?
2. What would you do if one consumer, out of twenty, shows an unexpected result — does that block the whole release?
3. How does this contract-testing approach scale if the role has hundreds of consumers rather than twenty?

### Key Interview Signals
Distinguishes "tested" as "the role's own Molecule suite passes" from genuine contract testing against real consumer configurations — the actual mitigation for the Question 23 class of incident.

### Hands-On Connection
[Lab 11 — Molecule Testing](../labs/lab-11-molecule-testing/).

---

## Question 31: The role nobody knew was three levels deep

### Scenario
A playbook calls `roles: [app-platform]`. `app-platform`'s `meta/main.yml` depends on `app-runtime`, which itself depends on `app-base`. A debugging session to trace why a single environment variable wasn't propagating correctly into the running application took most of a day, following the variable through all three layers of implicit, `meta/main.yml`-driven role dependencies.

### Interview Question
Would you flatten this, and how?

### Strong Senior-Level Answer
**Initial assessment:** yes — three levels of `meta/main.yml`-chained dependencies, invisible from the calling playbook (`roles: [app-platform]` gives no hint that two more roles are implicitly running), is exactly the deeply-nested-composition anti-pattern discussed in [`docs/role-design.md` §4](../docs/role-design.md#4-role-dependencies-metamainyml) — it adds indirection cost (debugging time, as demonstrated) without a corresponding, clearly-justified benefit visible to anyone reading the playbook.

**Technical reasoning:** implicit role dependencies are justified when a role genuinely, always needs another role's setup to function correctly and that relationship is stable and rarely needs to be seen/reasoned about by playbook authors — not when it obscures a debugging path that ends up mattering regularly.

**Investigation process:** audit each of the three layers: does `app-platform` genuinely need `app-runtime`'s tasks to have run first for its own tasks to function, or could this be expressed as an explicit `roles:` list instead, making the full execution order visible directly in the playbook?

**Recommended solution:** flatten to an explicit `roles:` list in the playbook itself, removing the `meta/main.yml` dependencies entirely:
```yaml
# playbooks/site.yml — the full execution order visible in one place
- hosts: app_servers
  roles:
    - app-base
    - app-runtime
    - app-platform
```
This achieves the identical execution order, but now any reader (or anyone debugging a variable-propagation issue) can see the complete picture without needing to know to check three separate `meta/main.yml` files.

**Risk controls:** flattening changes nothing about actual task execution — no `moved`-block-equivalent concern here, since Ansible has no state to reconcile; this is a pure, safe refactor.

**Validation steps:** run a Molecule scenario (or a real playbook run) before and after the flattening and confirm identical behavior/output — this is the concrete proof the refactor is behavior-neutral.

**Rollback or recovery strategy:** not applicable — a pure refactor with no infrastructure-state risk.

**Long-term prevention:** apply a "does this meta/main.yml dependency add real, hidden-but-necessary value, or would an explicit `roles:` list serve just as well with better legibility" test before introducing any new implicit role dependency going forward.

### Step-by-Step Implementation
See the explicit `roles:` list example above.

### Under-the-Hood Explanation
Each `meta/main.yml` dependency is resolved recursively during playbook parsing, before any task executes — Ansible flattens the full dependency chain into an ordered task list, identically whether that ordering came from explicit `roles:` entries or implicit `meta/main.yml` dependencies. The *execution* is identical either way; the difference is entirely about legibility — an explicit `roles:` list is visible to anyone reading the playbook, while implicit dependencies require checking each role's own `meta/main.yml` to discover the full chain, which is exactly what turned a one-line variable-propagation bug into a full day of debugging in this scenario.

### Common Weak Answer
"Nested role dependencies are fine, it's more modular."

### Why the Weak Answer Fails
It treats symptomatic debugging pain as an acceptable cost of "modularity" rather than recognizing the actual root cause: unnecessary indirection with no corresponding legibility or functional benefit, when an explicit `roles:` list achieves the identical execution order with the dependency chain fully visible.

### Follow-Up Questions
1. How do you decide, in general, whether a `meta/main.yml` dependency is genuinely justified versus better expressed as an explicit `roles:` list entry?
2. Is there a case where implicit `meta/main.yml` dependencies are clearly the right choice — what characterizes it?
3. How would you retrofit this flattening across a larger role library with many similar implicit dependency chains?

### Key Interview Signals
Treats dependency-chain depth/visibility as a cost to be justified, not a default organizational virtue, and proposes a concrete, safe, behavior-neutral flattening.

### Hands-On Connection
[Lab 2 — Roles and Structure](../labs/lab-02-roles-and-structure/).

---

## Question 32: Adding a feature without breaking anyone

### Scenario
Your `webserver` role's interface currently has a fixed set of variables. You need to add optional support for HTTP/2 without forcing all existing consumers to update their invocations immediately.

### Interview Question
How do you add this without a breaking change, and how does Ansible's lack of Terraform-style `optional()` object-type constraints affect your approach?

### Strong Senior-Level Answer
**Initial assessment:** unlike Terraform's `optional()` type-constraint mechanism for object-typed variables, Ansible has no equivalent structural feature for "this specific field within a larger object variable is optional with a default" — Ansible variables are dynamically typed, and the equivalent safety comes from a new, independently-optional top-level variable with a sensible default, plus (if you want validation) an `argument_specs.yml` entry.

**Technical reasoning:** adding a brand-new variable with a default that preserves current behavior when unset is unconditionally backward-compatible in Ansible, exactly as it is in Terraform — the mechanism differs (a new independent variable vs. an `optional()` field within an existing object type) but the backward-compatibility property is the same.

**Investigation process:** confirm the new capability (HTTP/2 support) is genuinely independent/orthogonal to existing variables, not something that should logically be a sub-field of an existing configuration object — if the latter, and you're using a dict-typed variable for related settings, consider whether restructuring that dict is itself a breaking change worth deferring to a major version.

**Recommended solution:** add a new, independently-defaulted variable:
```yaml
# roles/webserver/defaults/main.yml
webserver_enable_http2: false   # new, backward-compatible - existing consumers unaffected
```
```yaml
# roles/webserver/tasks/main.yml
- name: Configure HTTP/2 support
  ansible.builtin.lineinfile:
    path: /etc/nginx/nginx.conf
    line: "    http2 on;"
  when: webserver_enable_http2
```
Ship this as a minor version — a pure, backward-compatible addition.

**Risk controls:** confirm via the contract-test matrix (Question 30) that existing consumers show zero behavior change after upgrading to the new minor version, proving the addition is genuinely transparent to them.

**Validation steps:** a Molecule test case explicitly asserting that omitting `webserver_enable_http2` produces the previous (HTTP/1.1-only) behavior, and that setting it to `true` produces the new behavior.

**Rollback or recovery strategy:** not applicable — purely additive change, no existing behavior altered.

**Long-term prevention:** default to new, independently-optional, safely-defaulted variables for any new capability, reserving a genuine restructuring of an existing configuration object (which likely *is* a breaking change) for a deliberate major version.

### Step-by-Step Implementation
See the `webserver_enable_http2` example above.

### Under-the-Hood Explanation
A new variable with a default is resolved exactly like any other variable in Ansible's precedence system — a consumer who's never heard of `webserver_enable_http2` simply never sets it, and the role's `defaults/main.yml` value (`false`) applies, producing byte-identical behavior to the pre-change role version. There's no type-system-level distinction between "this is a newly-added optional field" and "this variable has always existed" from Ansible's runtime perspective — the backward-compatibility guarantee comes entirely from the *value* being a safe, behavior-preserving default, which is squarely the role author's responsibility to choose correctly, not something Ansible's type system enforces for you the way Terraform's `optional()` does for object-typed variables.

### Common Weak Answer
"Ansible doesn't have Terraform's optional() feature, so there's no safe way to add new variables without risk."

### Why the Weak Answer Fails
This overstates the actual gap — while Ansible indeed lacks a structural, type-system-level `optional()` mechanism for object sub-fields, adding a new, independently-defaulted top-level variable is just as safely backward-compatible in practice; the discipline required is simply choosing a genuinely behavior-preserving default, which is a role-authoring responsibility either way.

### Follow-Up Questions
1. How would you handle this same requirement if the new setting genuinely needed to be a sub-field of an existing dict-typed variable, rather than a new independent variable?
2. How does `argument_specs.yml` help communicate that this new variable is optional and what its default is, to consumers who might not read the task source?
3. What's the actual practical difference in safety between Terraform's `optional()` and Ansible's "just add a new variable with a safe default" approach — is one genuinely more robust?

### Key Interview Signals
Correctly identifies the real (if more informal) mechanism Ansible offers for this exact backward-compatibility need, and doesn't either overstate the gap with Terraform or claim a feature parity that doesn't exist.

### Hands-On Connection
[Lab 2 — Roles and Structure](../labs/lab-02-roles-and-structure/).

---

## Question 33: The role that let you forget encryption

### Scenario
A database-provisioning-adjacent role has an `enable_encryption_at_rest` variable defaulting to `true`, but nothing stops a consumer from explicitly setting it to `false` — which one team did, unintentionally, by copy-pasting an example from an internal wiki page that had it disabled for a local-testing scenario.

### Interview Question
How would you make it structurally difficult to disable encryption through this role, while still allowing a genuine, reviewed exception?

### Strong Senior-Level Answer
**Initial assessment:** a default, even a safe one, is not a guardrail — it only protects consumers who don't override it, and this scenario shows exactly how easily an override happens accidentally (copy-pasted example code) rather than through a deliberate, reviewed decision — directly mirroring the companion repository's Terraform module encryption-toggle scenario.

**Technical reasoning:** the fix is an `assert` that actively rejects the unsafe combination unless a second, explicit, harder-to-copy-paste-accidentally signal is also present, raising the bar from "one flag flipped" to "a deliberate, named exception."

**Investigation process:** confirm whether any legitimate production use case genuinely needs unencrypted-at-rest storage through this role (likely none) versus a rare, real exception (e.g., a specific, approved compliance scenario).

**Recommended solution:** require an explicit, harder-to-accidentally-set companion variable for the unsafe path:
```yaml
- name: Reject disabling encryption without an explicit, reviewed exception
  ansible.builtin.assert:
    that:
      - enable_encryption_at_rest or (unencrypted_exception_ticket is defined and unencrypted_exception_ticket | length > 0)
    fail_msg: "Disabling encryption requires unencrypted_exception_ticket referencing an approved exception ticket - see SEC-XXXX process."
```

**Risk controls:** pair this role-level guard with an organization-wide policy check (an `ansible-lint` custom rule, or a Conftest-style check against rendered configuration in CI) as defense-in-depth, so the guard holds even for any path bypassing this specific role.

**Validation steps:** a Molecule test case confirming `enable_encryption_at_rest: false` without the exception ticket is rejected, and that providing both together is accepted.

**Rollback or recovery strategy:** for the team that already disabled encryption, this requires a real remediation — re-enabling it and confirming whatever was stored while unencrypted needs its own review depending on sensitivity.

**Long-term prevention:** apply the same "should this ever be legitimately disabled, and if so, what makes disabling it deliberate rather than accidental" question to every other security-relevant boolean default across the role library.

### Step-by-Step Implementation
See the `assert`-based guard above.

### Under-the-Hood Explanation
`ansible.builtin.assert` evaluates its condition during task execution, before any subsequent task runs — a failing assertion halts the play immediately with the custom error message, giving specific, immediate feedback rather than allowing an insecure configuration to reach a real host. This is a play-time-only, Ansible-level check — it doesn't touch the actual target infrastructure at all, which is why the policy-as-code backstop matters for defense-in-depth against any path that bypasses this specific role.

### Common Weak Answer
"The default is already true, so this is basically already safe."

### Why the Weak Answer Fails
The scenario explicitly demonstrates a default being overridden accidentally via copy-pasted example code — "the default is safe" provides zero protection against an override; the fix must make the unsafe override itself harder to do by accident.

### Follow-Up Questions
1. How would you extend this "require an explicit exception marker" pattern to other security-relevant toggles across your role library consistently?
2. What's the trade-off between removing the toggle entirely (hardcoding safety) versus keeping it with an assert-based friction requirement?
3. How would a policy-as-code check catch this same misconfiguration for a raw task declared entirely outside this role?

### Key Interview Signals
Reaches for structural friction (an assert requiring deliberate justification) rather than trusting a default alone, and considers defense-in-depth via policy-as-code for paths the role itself can't cover.

### Hands-On Connection
[Lab 10 — Security Hardening Pipeline](../labs/lab-10-security-hardening/) and [Lab 13 — Policy as Code](../labs/lab-13-policy-as-code/).

---

## Question 34: Sunsetting the role nobody was supposed to still be using

### Scenario
Two years ago, your team published a `legacy-webserver` role, later replaced by a much-improved `webserver` role. The legacy role was never formally deprecated — it still works, and a recent audit discovered four consumers still using it, including one added last month by a new hire who had no idea a newer role existed.

### Interview Question
Design the deprecation and migration process, including how you'd have prevented the new hire from picking the legacy role in the first place.

### Strong Senior-Level Answer
**Initial assessment:** the core failure is that "replaced" was never actually communicated or enforced anywhere discoverable — the legacy role looked, to a new hire searching the registry, exactly as valid and current as the replacement, since nothing marked it otherwise, exactly mirroring the companion repository's Terraform module deprecation scenario.

**Technical reasoning:** deprecation needs to be visible at the point of discovery (the Automation Hub/registry listing itself), not just known informally within the team that made the change.

**Investigation process:** confirm exactly what differs functionally between `legacy-webserver` and `webserver` for each of the four current consumers — is this a drop-in swap, or does it require per-consumer migration work (renamed variables, different defaults)?

**Recommended solution:** immediately update the legacy role's README/Automation Hub description with an explicit, prominent deprecation notice naming the replacement and a sunset date; if the registry platform supports it, mark the role version itself as deprecated so `ansible-galaxy search`/installs surface a warning. Set a real, communicated sunset date (e.g., 90 days) giving the four consumers a concrete migration window, with the platform team providing a migration guide. After the sunset date and confirmed migration of all four, remove the legacy role from the registry entirely (or leave a final version that errors immediately with a clear message pointing to the replacement).

**Risk controls:** track migration completion per consumer explicitly rather than assuming everyone migrated just because the deadline passed — confirm before removing the legacy role.

**Validation steps:** each of the four consumers should show identical (or expected, reviewed) behavior after migrating to the new role, verified via Molecule or a real playbook run comparison.

**Rollback or recovery strategy:** keep the legacy role's last version available (even if deprecated/removed from active registry search) for a defined grace period after the official sunset, purely as a safety net.

**Long-term prevention:** establish a standing convention that any role replacement is immediately paired with a registry-level deprecation notice on the old one, and periodically audit the registry for roles with no recent updates as a signal to check whether they're actually still meant to be current.

### Step-by-Step Implementation
```markdown
<!-- roles/legacy-webserver/README.md, top of file -->
> **DEPRECATED**: This role is replaced by [`webserver`](https://automation-hub.example.com/my-org/webserver).
> Sunset date: 2026-10-24. New usage is not supported. See [migration guide](MIGRATION.md).
```
```bash
# Re-audit before removal - track migration completion explicitly, don't assume
grep -rl 'name: legacy-webserver' --include='requirements.yml' ~/repos/*/
```

### Under-the-Hood Explanation
There's no Ansible-core mechanism that automatically flags a role as deprecated to consumers — this is entirely a registry-platform and documentation-convention concern (private Automation Hub instances support marking versions/roles deprecated in their own metadata, surfaced in search/UI; a purely Git-tag-based role source has no equivalent built-in mechanism at all, reinforcing the value of a real registry from Question 29).

### Common Weak Answer
"Just tell people not to use the legacy role anymore."

### Why the Weak Answer Fails
This is exactly the informal, team-internal-knowledge approach that already failed — a new hire with no access to that tribal knowledge had no way to discover the role was deprecated, because nothing about the role itself, in the place they'd actually go looking, indicated it.

### Follow-Up Questions
1. How would you handle a consumer who, after the sunset date, still can't migrate in time due to unrelated project constraints?
2. What would you do differently if the legacy and replacement roles had significantly different underlying task structures, making migration inherently riskier?
3. How do you build an organizational habit of always pairing a role replacement with a deprecation notice?

### Key Interview Signals
Treats deprecation as requiring visible, discoverable, registry-level signaling — not an assumption that "everyone will just know" — and designs a concrete sunset timeline with real migration support.

### Hands-On Connection
[Lab 2 — Roles and Structure](../labs/lab-02-roles-and-structure/).
