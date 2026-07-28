# Cheat Sheet: Role Design

## Standard directory structure
```text
roles/rolename/
├── defaults/main.yml    # overridable interface - LOW precedence
├── vars/main.yml         # role-internal constants - HIGH precedence (beats defaults!)
├── tasks/main.yml
├── handlers/main.yml
├── templates/
├── files/
├── meta/main.yml         # dependencies, galaxy metadata
└── meta/argument_specs.yml  # typed, validated interface
```

## `defaults` vs `vars` — the real interface decision
- `defaults/main.yml`: values a caller is *meant* to override. Low precedence — anything else (group_vars, -e) beats it.
- `vars/main.yml`: role-internal constants not meant for casual override. **Higher precedence than defaults** — a common, easy-to-miss reversal of intuition. [Question 12](../interview-questions/02-inventory-variables.md#question-12-the-role-that-couldnt-be-overridden)

## `argument_specs.yml` — the typed interface
```yaml
argument_specs:
  main:
    options:
      webserver_port:
        type: int
        required: false
        default: 80
        description: TCP port nginx listens on
```
- Validated **before any task runs** — a bad input fails immediately at the interface boundary, not deep inside a template rendering. [Question 26](../interview-questions/03-roles-collections.md#question-26-the-readme-that-lied)
- This is Ansible's closest equivalent to Terraform's typed/validated module variables.

## Versioning and backward compatibility
- Never rename a variable outright for an existing, consumed role — use a deprecation-aliasing period (accept both names, warn on the old one). [Question 23](../interview-questions/03-roles-collections.md#question-23-the-role-update-that-broke-thirty-playbooks)
- Add new capability behind a new, optional variable with a safe, backward-compatible default. [Question 32](../interview-questions/03-roles-collections.md#question-32-adding-a-feature-without-breaking-anyone)
- For a widely-shared role (Galaxy/internal registry), test against a **contract matrix** of representative real consumer configurations, not just your own Molecule scenario. [Question 82](../interview-questions/09-testing-validation.md#question-82-the-role-that-had-no-idea-it-broke-someone-else)

## Design principles
- Prefer an **opinionated**, narrower role over one with fifty conditional variables trying to serve every case. [Question 25](../interview-questions/03-roles-collections.md#question-25-the-role-with-fifty-conditional-variables)
- A role should have clear **outputs** (via `set_fact`), not just inputs — a VPC-equivalent module that only gives you an ID is under-designed. [Question 27](../interview-questions/03-roles-collections.md#question-27-the-role-that-only-told-you-the-port)
- Avoid deep, implicit `meta/main.yml` dependency chains three levels down — flatten to an explicit `roles:` list in the calling playbook where feasible. [Question 31](../interview-questions/03-roles-collections.md#question-31-the-role-nobody-knew-was-three-levels-deep)
- `README.md` describes the contract in prose, but `argument_specs.yml` is the enforced, authoritative source of truth if they ever disagree.
