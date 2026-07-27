# Testing and Validation

"We just run it against staging and see what happens" is the Ansible equivalent of "we don't really test our Terraform" — and just as revealing. This document backs [`interview-questions/09-testing-validation.md`](../interview-questions/09-testing-validation.md) and is exercised in [Lab 11](../labs/lab-11-molecule-testing/).

## 1. The testing pyramid, applied to Ansible

| Layer | Tool | Cost | Catches |
|---|---|---|---|
| Syntax | `ansible-playbook --syntax-check` | Free, instant | YAML/Jinja syntax errors only |
| Lint | `ansible-lint`, `yamllint` | Free, seconds | Anti-patterns, deprecated modules, style, some correctness issues |
| Unit/Role | **Molecule** (Docker/Podman driver) | Free (local containers), seconds-minutes | Role correctness, idempotency, in-container assertions |
| Integration | Molecule against real cloud instances, or Terratest-style external verification | Real cost, minutes | Real cloud-specific behavior (security groups, IAM, actual boot behavior) a container can't simulate |
| Contract | A role/collection's new version run against representative real consumer playbooks | Real or container cost | Breaking-change detection before a wide release, mirroring the Terraform module contract-testing pattern |

## 2. `ansible-playbook --syntax-check` — necessary, far from sufficient

Confirms the YAML parses and the playbook structure is valid — catches nothing about whether the automation actually does the right thing, exactly analogous to `terraform validate`'s narrow scope.

## 3. `ansible-lint`

```bash
ansible-lint playbooks/ roles/
```
Catches structural/best-practice issues: `command`/`shell` where a real module exists, missing `no_log`, use of deprecated modules, missing `argument_specs`, FQCN (fully-qualified collection name) violations (`service:` instead of `ansible.builtin.service:` — required by modern collection-based module resolution to avoid ambiguity). Treat lint failures as a mandatory PR gate, same as `terraform fmt -check`/`terraform validate` in the companion repository's CI chain.

## 4. Molecule — the core testing framework

```text
roles/webserver/molecule/default/
├── molecule.yml       # driver (docker), platforms, provisioner config
├── converge.yml       # the actual playbook that applies the role under test
├── verify.yml         # assertions about the resulting state
└── prepare.yml        # optional: pre-converge setup (e.g., install prerequisites)
```
```yaml
# molecule.yml
driver:
  name: docker
platforms:
  - name: instance
    image: "geerlingguy/docker-rockylinux9-ansible:latest"
provisioner:
  name: ansible
verifier:
  name: ansible
```
```bash
molecule test    # full cycle: create -> converge -> idempotence -> verify -> destroy
molecule converge  # just apply, useful for iterative development
molecule verify    # just run assertions against an already-converged instance
```

### The idempotence step — Molecule's single most important built-in check
`molecule test`'s `idempotence` stage runs the **same converge playbook a second time** and fails the test if the second run reports **any** `changed` tasks. This is the automated, enforced version of the manual "does running my playbook twice produce the same result" discipline — exactly the practical proof of the idempotency contract discussed in [`ansible-internals.md` §3](ansible-internals.md#3-idempotency--a-contract-you-write-not-a-guarantee-ansible-provides). A role that passes `converge` but fails `idempotence` has a real bug — usually an unguarded `command`/`shell` task, or a template that non-deterministically re-renders differently each run (e.g., embedding a raw timestamp).

### `verify.yml` — asserting actual resulting state, not just "Ansible reported success"
```yaml
# verify.yml
- hosts: all
  tasks:
    - name: Confirm nginx is actually running
      ansible.builtin.command: systemctl is-active nginx
      register: result
      changed_when: false
      failed_when: result.stdout != "active"

    - name: Confirm the config file has the expected worker_processes value
      ansible.builtin.command: grep "worker_processes auto" /etc/nginx/nginx.conf
      changed_when: false
```
This mirrors the "assert against an independently-derived expected value, not a tautological self-comparison" discipline from the companion Terraform repository's testing material — verify the *real*, observable state (a running service, a specific config value), not just that the converge playbook exited 0.

## 5. Testing at the playbook level, not just the role level

Molecule scenarios are most naturally scoped per-role, but a full playbook (composing several roles) deserves its own integration-style Molecule scenario too, specifically to catch cross-role interaction bugs (a variable one role sets that another role silently depends on, an ordering issue between roles) that no single role's isolated test would ever surface.

## 6. Mocking cloud calls for fast, free unit-level testing

For playbooks/roles that call `amazon.aws`/`community.aws` modules, running them for real in every test cycle is slow and costs money. Two common approaches:
- **Check mode + a role designed to be check-mode-safe** — verifies the *logic* (which tasks would run, with what parameters) without ever hitting the real AWS API.
- **A dedicated, cheap sandbox AWS account** reserved for integration-tier tests only, with aggressive tagging and a scheduled cleanup sweep — identical cost-control discipline to the companion Terraform repository's integration-test guidance.

There is no Ansible-native "mock_provider" equivalent to Terraform's `terraform test` mocking — this is a genuine capability gap worth naming directly in an interview, not glossing over: Ansible's testing story for cloud-calling roles leans more heavily on either real (cost-incurring) sandbox testing or structural check-mode verification, since there's no first-party framework simulating cloud API responses the way Terraform's `mock_provider` does.

## 7. Contract testing for widely-shared roles

Before releasing a new major version of an organization-wide role (e.g., `security-baseline`), run its Molecule scenario **plus** a representative sample of real consuming playbooks' own Molecule scenarios against the new version, checking specifically for newly-introduced `changed`/`failed` results that weren't there before — the direct Ansible analog of the Terraform module contract-testing pattern that prevents the "one module release broke forty consumers" incident class.

## 8. CI cadence

- **Every PR**: `ansible-lint`, `yamllint`, `--syntax-check`, and every affected role's Molecule scenario (Docker driver — free, fast).
- **Scheduled / pre-release**: any integration-tier tests requiring real cloud resources.
- **Before a major role/collection version release**: the contract-test matrix (§7).

## Common weak answer vs. senior answer

| Scenario | Weak answer | Senior answer |
|---|---|---|
| "How do you test Ansible roles?" | "We run the playbook against staging and check it worked" | Molecule with a Docker driver for fast, free, per-PR testing, including the automated idempotence check, plus a real-cloud integration tier for anything a container can't simulate |
| Proving idempotency | "We assume the modules are idempotent" | Molecule's `idempotence` stage runs converge twice and fails on any second-run `changed` — this is the actual, enforced proof, not an assumption |
| Verifying a role worked | "If Ansible reports no errors, it worked" | `verify.yml` asserts the real, observable resulting state (service running, config content correct) — Ansible reporting success only means the tasks executed without error, not that the intended outcome is actually true |
| Releasing a new major role version broke many consumers | "We should test roles more" | Run a contract-test matrix — the new version against representative real consumer playbooks' own Molecule scenarios — specifically checking for newly-introduced changes/failures before a wide release |

## Related material
- Interview questions: [`interview-questions/09-testing-validation.md`](../interview-questions/09-testing-validation.md)
- Hands-on: [Lab 11 — Molecule Testing](../labs/lab-11-molecule-testing/)
- Diagrams: [`diagrams/12-molecule-architecture.md`](../diagrams/12-molecule-architecture.md)
