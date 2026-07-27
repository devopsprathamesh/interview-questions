# Security and Secrets Management

Security in Ansible spans the code you write, the secrets it handles, the credentials that authorize it, and the pipeline that runs it. This document backs [`interview-questions/07-security-vault.md`](../interview-questions/07-security-vault.md) and is exercised in [Lab 4](../labs/lab-04-ansible-vault/) and [Lab 10](../labs/lab-10-security-hardening/).

## 1. Ansible Vault — encrypting data at rest

```bash
ansible-vault create group_vars/production/vault.yml
ansible-vault edit group_vars/production/vault.yml
ansible-vault encrypt_string 'super-secret-value' --name 'vault_db_password'
ansible-vault view group_vars/production/vault.yml
```
Vault encrypts the **file content**, not individual values, unless you specifically use `encrypt_string` to produce an inline encrypted scalar embedded in an otherwise-plaintext YAML file. The recommended pattern (see [`inventory-and-variables.md` §7](inventory-and-variables.md#7-secrets-in-variables--the-vault-boundary)) splits a plaintext `vars.yml` (referencing variable names) from a fully-encrypted `vault.yml` (defining the actual secret values) — this keeps `git diff`/`git blame` useful on the non-secret file while the secret file stays opaque at rest.

**Multiple vault IDs** let different secrets be encrypted with different passwords, scoped by sensitivity/team:
```bash
ansible-vault encrypt --vault-id production@prompt group_vars/production/vault.yml
ansible-vault encrypt --vault-id dev@prompt group_vars/dev/vault.yml
ansible-playbook site.yml --vault-id production@~/.vault-pass-prod --vault-id dev@~/.vault-pass-dev
```
This means a compromised dev-vault password does **not** grant access to production secrets — the same least-privilege-scoping principle as separate state-bucket access-per-environment in the companion Terraform repository, applied to Vault passwords instead.

## 2. The vault password itself — the actual key management problem

Vault only shifts the secret-management problem one level up: now the **vault password** is the thing that must be protected. Options, worst to best for production use:
- A password typed interactively (`--ask-vault-pass`) — fine for a human running playbooks locally, unusable for unattended CI.
- A password stored in a plaintext file referenced via `--vault-password-file` — better than nothing, but the file itself is now a plaintext secret needing its own access control, and easy to accidentally commit.
- **A vault password *script*** that fetches the real password from a proper secrets manager (AWS Secrets Manager, HashiCorp Vault, etc.) at run time — the actual production-grade answer, since it means no plaintext vault password sits on disk anywhere long-term:
```bash
#!/usr/bin/env bash
# vault-pass-from-secrets-manager.sh, referenced via --vault-password-file
aws secretsmanager get-secret-value --secret-id ansible/vault-password --query SecretString --output text
```

## 3. `no_log` — preventing secrets from leaking into run output

```yaml
- name: Set a database password (never show this in logs)
  ansible.builtin.mysql_user:
    name: app
    password: "{{ vault_db_password }}"
  no_log: true
```
Exactly like Terraform's `sensitive = true`, **`no_log` only affects what's *displayed*** (console output, `-vvv` verbose logs, and anything a callback plugin might otherwise print) — it does not change what a module internally does with the value, and does not retroactively protect a value that a *different*, non-`no_log`'d task already exposed. A common, real mistake: setting `no_log: true` on the task that *uses* a secret, while a preceding `debug:` task (added temporarily for troubleshooting and forgotten) still prints it in full. Audit for stray `debug:`/`ansible.builtin.debug` tasks referencing sensitive variables as part of any security review, not just the tasks explicitly handling secrets.

## 4. `become` and least privilege

```yaml
- name: Only escalate privilege for the specific tasks that need it
  ansible.builtin.service:
    name: nginx
    state: restarted
  become: true
  become_user: root
```
Prefer scoping `become: true` to the **specific tasks** that genuinely need root (or another elevated user), rather than setting it once at the play level for an entire play where most tasks don't actually need escalation — the same least-privilege principle as any other credential scoping. Also prefer `become_user` to a specific non-root account where the operation allows it (e.g., a task that only needs to write as the application's own service account, not root).

## 5. CI/CD credential handling

Never store long-lived cloud credentials or SSH private keys as plaintext CI secrets when a better option exists:
- **AWS**: OIDC federation from the CI platform to an assumed IAM role — identical pattern to the companion Terraform repository's CI/CD authentication model, reused here for any `amazon.aws`/`community.aws` module calls or dynamic inventory queries.
- **SSH access to managed hosts**: prefer short-lived, CI-generated SSH certificates (via an SSH CA) or a bastion/Session-Manager-based connection over a long-lived private key stored as a static CI secret.
- **Ansible Vault password**: fetched at run time from a secrets manager (§2), never embedded in the CI pipeline's own YAML configuration.

## 6. AWX/Automation Platform credential storage

Centralizing credentials in AWX/Automation Platform (rather than scattered across individual engineers' laptops and ad hoc CI secrets) means: credentials are injected into a job's execution environment only for the duration of that specific run, access to *use* a credential is separately controlled from access to *view* it (a user can be granted "launch this Job Template using this credential" without ever seeing the credential's actual value), and every credential use is logged in the Job Template's run history — a real, auditable trail matching the CloudTrail-based auditing discussed for Terraform's state/IAM access.

## 7. Static analysis: `ansible-lint`

```bash
ansible-lint playbooks/ roles/
```
`ansible-lint` catches a broad set of correctness *and* security-adjacent issues: use of `command`/`shell` where a proper module exists (a maintainability/idempotency issue, see [`ansible-internals.md` §3](ansible-internals.md#3-idempotency--a-contract-you-write-not-a-guarantee-ansible-provides)), missing `no_log` on tasks handling common secret-shaped variable names, use of the deprecated/removed built-in cloud modules instead of current collections, and general YAML/Jinja best-practice violations. It is **not** a substitute for a dedicated secret-scanner (gitleaks/truffleHog) or a real security scanner (Checkov-style rules don't exist natively for Ansible in the way they do for Terraform plans, since Ansible has no equivalent "plan JSON" artifact to statically scan against — see [`interview-questions/09-testing-validation.md`](../interview-questions/09-testing-validation.md) for the practical implications of this gap).

## 8. Secret scanning for committed vault files

Even though Vault-encrypted files are opaque, always run a secret scanner across the **plaintext** side (the `vars.yml` half of the vars/vault split, and any playbook/role file) as a backstop against a secret accidentally landing in the wrong (unencrypted) file — a vault-encrypted repository still benefits from the same gitleaks-style CI gate as any other codebase, since the risk isn't Vault failing, it's a human putting a real secret in the wrong file by mistake.

## 9. Supply-chain trust: collections and roles

A collection or role is executed with exactly the same privilege as any hand-written task in the same play — a compromised or malicious third-party collection (Galaxy, like any public package registry, has had real supply-chain incidents in the broader ecosystem sense) has the same blast radius as a compromised CI credential. Pin exact collection versions (`requirements.yml`, committed), prefer Red Hat-certified/well-known-vendor collections for anything touching production credentials or infrastructure, and maintain an internal vetting/allowlist process for community collections used in security-relevant automation — directly mirroring the Terraform provider/module supply-chain guidance in the companion repository.

## Common weak answer vs. senior answer

| Scenario | Weak answer | Senior answer |
|---|---|---|
| "How do you protect secrets in Ansible?" | "Use Ansible Vault" | Vault encrypts data at rest, but the vault *password* itself needs real key management (a secrets-manager-backed vault password script, not a plaintext file); `no_log` is a display control, not a storage control |
| A secret appeared in CI logs | "Add `no_log` to the task" | Audit for any preceding `debug`/verbose-logging task that may have already exposed it before the fix; rotate the credential regardless of how contained the exposure looks |
| Managing SSH access to hundreds of hosts | "Distribute a shared SSH private key to the automation user" | Prefer short-lived SSH certificates from an SSH CA, or connection via a bastion/Session-Manager-equivalent, avoiding a long-lived, widely-distributed static key entirely |
| CI needs to run Ansible against AWS | "Store an AWS access key as a CI secret" | OIDC federation to an assumed role, scoped and short-lived, matching the same pattern used for Terraform CI/CD |

## Related material
- Interview questions: [`interview-questions/07-security-vault.md`](../interview-questions/07-security-vault.md)
- Hands-on: [Lab 4 — Ansible Vault](../labs/lab-04-ansible-vault/), [Lab 10 — Security Hardening Pipeline](../labs/lab-10-security-hardening/)
- Diagrams: [`diagrams/07-vault-flow.md`](../diagrams/07-vault-flow.md)
