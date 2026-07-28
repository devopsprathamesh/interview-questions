# Role and Collection Engineering

Roles are Ansible's unit of reuse — and, at organizational scale, its unit of **contract** between the team that maintains a role and every playbook that consumes it. This document backs [`interview-questions/03-roles-collections.md`](../interview-questions/03-roles-collections.md) and is exercised in [Lab 2](../labs/lab-02-roles-and-structure/) and [Lab 11](../labs/lab-11-molecule-testing/).

## 1. Standard role structure

```text
roles/webserver/
├── defaults/main.yml     # PUBLIC interface - lowest precedence, meant to be overridden
├── vars/main.yml         # internal constants - high precedence, not meant to be overridden by callers
├── tasks/main.yml        # the actual task list
├── handlers/main.yml
├── templates/
├── files/
├── meta/main.yml         # role dependencies, Galaxy metadata, platform support
└── molecule/default/     # test scenario (see docs/testing.md)
```
The `defaults/` vs. `vars/` distinction is a real interface decision, not a formality (see [`inventory-and-variables.md` §4](inventory-and-variables.md#4-variable-precedence-order) for the precedence mechanics behind it) — treat `defaults/main.yml` as the role's actual public API surface, and `vars/main.yml` as implementation details the role owns and callers shouldn't expect to easily override.

## 2. Designing the role interface

```yaml
# roles/webserver/defaults/main.yml — the public interface
webserver_port: 8080
webserver_worker_processes: "auto"
webserver_enable_ssl: false
webserver_ssl_cert_path: null
webserver_extra_modules: []
```
- **Sensible, safe defaults for everything** — a caller invoking the role with zero variables set should get a reasonable, secure-by-default result.
- **Fail fast on invalid combinations**, using `assert`:
```yaml
- name: Validate SSL configuration is complete if enabled
  ansible.builtin.assert:
    that:
      - not webserver_enable_ssl or webserver_ssl_cert_path is not none
    fail_msg: "webserver_enable_ssl is true but webserver_ssl_cert_path was not set."
```
- **Document every variable** — a role's `README.md` (or, better, `argument_specs.yml` for `ansible-doc`-integrated validation, covered below) is the actual contract; a role with undocumented variables forces every consumer to read the task source to know what's configurable.

## 3. `argument_specs.yml` — validated role interfaces (ansible-core >= 2.11)

```yaml
# roles/webserver/meta/argument_specs.yml
argument_specs:
  main:
    short_description: Configures and starts a hardened web server.
    options:
      webserver_port:
        type: int
        default: 8080
        description: Port the web server listens on.
      webserver_enable_ssl:
        type: bool
        default: false
        description: Whether to configure TLS termination.
      webserver_ssl_cert_path:
        type: path
        required: false
        description: Required if webserver_enable_ssl is true.
```
This gives you **actual type checking and required-argument validation** for a role's inputs, enforced automatically at run time — the closest Ansible equivalent to a Terraform module's `variable` type constraints and `validation` blocks. A role without this validates nothing about its own inputs beyond what individual tasks happen to fail on internally, often with a confusing downstream error rather than a clear, immediate one.

## 4. Role dependencies (`meta/main.yml`)

```yaml
# roles/webserver/meta/main.yml
dependencies:
  - role: security-baseline
    vars:
      security_baseline_profile: "web-tier"
```
Dependencies listed here run **automatically, before** the depending role's own tasks, every time the role is used — a powerful but easy-to-overuse mechanism. **The senior-level caution:** implicit `meta/main.yml` dependencies can produce a surprising, hard-to-trace execution order for anyone reading a playbook that just says `roles: [webserver]` with no visible indication that `security-baseline` is also running. Many mature Ansible codebases deliberately avoid `meta/main.yml` dependencies in favor of explicit `roles:` lists in the playbook itself, trading a little repetition for much greater legibility — a real, debatable trade-off worth being able to argue either side of in an interview.

## 5. Avoiding overly generic roles

A role that accepts forty conditional variables to handle every possible web-server configuration across every team is exactly the Ansible analog of the Terraform "fifty optional variables" anti-pattern: it has no real opinion, so every consumer re-derives correct, secure usage from scratch, and mistakes proliferate. Prefer **opinionated roles** with narrow, deliberate escape hatches:
```yaml
webserver_tier: "public"   # enum: public | internal | admin — drives a small, curated set of internal decisions
# NOT: forty independent booleans each toggling one specific nginx directive
```
Reserve genuinely flexible, low-level roles for platform teams building primitives for *other role authors*, not for the role most application teams consume directly.

## 6. Versioning and Galaxy/Automation Hub

```yaml
# requirements.yml
roles:
  - name: my_org.webserver
    version: "2.3.1"
collections:
  - name: my_org.platform
    version: ">=1.4.0,<2.0.0"
```
Exactly the same semantic-versioning discipline as Terraform modules applies here: **patch** = bug fix, no interface change; **minor** = backward-compatible addition (a new optional variable with a default); **major** = anything that could break an existing consumer (a renamed variable, a removed default, a behavior change). Consumers should pin with a version range (`>=1.4.0,<2.0.0`), never an unconstrained "latest," for exactly the reasons covered in the companion Terraform repository's module-versioning material — an unpinned consumer floats onto a breaking change the moment anyone runs `ansible-galaxy install --force`.

**Private Automation Hub / a private Galaxy-compatible server** is the organizational equivalent of a private Terraform module registry — namespaced, versioned, internally-hosted collections/roles, instead of ad hoc Git-URL sourcing scattered across every consuming repository.

## 7. Collections vs. standalone roles

A **collection** bundles roles, modules, plugins, and documentation together under one namespaced, versioned package (`my_org.platform`) — the modern, recommended packaging unit for anything beyond a single simple role. Prefer a collection when you're distributing more than "just a role" (custom modules, filter plugins, multiple related roles that should version together) — a standalone role is fine for a single, focused, independently-versioned unit of configuration.

## 8. Testing roles (see `testing.md` for the full treatment)

Every role intended for reuse needs, at minimum, a **Molecule** scenario verifying: the role applies cleanly on a fresh target, running it **twice** produces no changes on the second run (the actual, automated idempotency proof — see [`ansible-internals.md` §3](ansible-internals.md#3-idempotency--a-contract-you-write-not-a-guarantee-ansible-provides)), and (ideally) an assertion-based verifier confirming the *intended state* is actually correct (the service is running, the config file has the expected content), not just that Ansible reported success.

## 9. Documentation

`README.md` per role covering purpose, `argument_specs`-derived variable reference (kept in sync automatically if you generate docs from the spec rather than hand-maintaining a separate table — the same "generated docs, not hand-written," discipline as `terraform-docs` in the companion repository), a minimal usage example, and any assumptions the role doesn't itself enforce (e.g., "assumes the target already has Python 3 available").

## 10. Deprecation and upgrade strategy

Exactly mirroring the Terraform module deprecation discipline: mark a deprecated role/collection version visibly (Automation Hub/Galaxy listing, not just team-internal knowledge), set a real sunset date, provide a migration guide, and support both old and new interfaces in parallel for a defined window via optional variables with safe defaults rather than a forced simultaneous cutover.

## Common weak answer vs. senior answer

| Scenario | Weak answer | Senior answer |
|---|---|---|
| A role change broke several consuming playbooks | "We should test roles before releasing" | Identify whether the break was a semver-classification miss (a breaking default/variable change shipped as non-major) plus unpinned consumer version ranges — fix both, not just "test more" |
| Should this role expose every possible option? | "Yes, more flexibility is always better" | Opinionated roles with a narrow, deliberate escape hatch are correct for application-facing roles; full flexibility belongs in low-level platform primitives only |
| Role dependencies via `meta/main.yml` | "Just add it as a dependency, it'll run automatically" | Weigh the legibility cost — an implicit, invisible-from-the-playbook execution order — against the convenience, and consider an explicit `roles:` list instead for anything a reader needs to reason about quickly |
| Validating role inputs | "Tasks will just fail if the input is wrong" | Use `argument_specs.yml` for real type/required-field validation at the interface level, plus `assert` for cross-field invariants — fail fast with a clear message, not a confusing downstream task error |

## Related material
- Interview questions: [`interview-questions/03-roles-collections.md`](../interview-questions/03-roles-collections.md)
- Hands-on: [Lab 2 — Roles and Structure](../labs/lab-02-roles-and-structure/), [Lab 11 — Molecule Testing](../labs/lab-11-molecule-testing/)
- Diagrams: [`diagrams/08-role-dependency.md`](../diagrams/08-role-dependency.md)
