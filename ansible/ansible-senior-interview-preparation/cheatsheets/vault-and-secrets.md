# Cheat Sheet: Vault and Secrets Management

## Core commands
| Command | Purpose |
|---|---|
| `ansible-vault create FILE` | Create a new encrypted file |
| `ansible-vault edit FILE` | Edit in place (decrypts to a temp file, re-encrypts on save) |
| `ansible-vault view FILE` | Print decrypted content without writing to disk |
| `ansible-vault encrypt FILE` | Encrypt an existing plaintext file |
| `ansible-vault decrypt FILE` | Permanently decrypt (rarely appropriate outside a migration) |
| `ansible-vault encrypt_string 'val' --name 'x'` | Encrypt one value inline, for a partially-plaintext vars file |
| `ansible-vault rekey FILE` | Rotate the vault password without touching plaintext content |

## Non-negotiable rules
- **Never** commit a vault password in plaintext, in any file, in any repository — even a "private" one. Repo access ≠ secrets management, and Git history retains it even after removal. [Question 61](../interview-questions/07-security-vault.md#question-61-the-vault-password-that-was-itself-the-vulnerability)
- Source the vault password via a **script** (`vault_password_file` pointing at an executable) that fetches from a real secrets manager (AWS Secrets Manager, HashiCorp Vault) — never a static file.
- Split vaults **per environment** (or finer) via `--vault-id` — a monolithic, single-password vault is an all-or-nothing access grant. [Question 63](../interview-questions/07-security-vault.md#question-63-vault-per-environment-or-vault-per-secret)
- For a genuine secrets manager (HashiCorp Vault, distinct from Ansible Vault) integration, prefer **AppRole** or **cloud-native IAM auth** over a long-lived static token. [Question 65](../interview-questions/07-security-vault.md#question-65-the-hashicorp-vault-integration-that-authenticated-with-a-static-token)

## `no_log` — what it actually covers
- Suppresses Ansible's **normal task-result** output/logging (substituted with a "censored" placeholder).
- Does **not** guarantee a module's own internally-constructed **exception message** won't include a sensitive value — verify via a deliberate failure test, don't assume. [Question 62](../interview-questions/07-security-vault.md#question-62-the-no_log-that-logged-anyway)
- `--check --diff` on a task templating a vault-decrypted value **will show the plaintext value in the diff** unless that specific task is also `no_log`'d. [Question 64](../interview-questions/07-security-vault.md#question-64-the-vault-encrypted-variable-that-was-still-visible-in-plan-output)

## Secret scanning
- Run `gitleaks detect --source . --verbose` in CI as a mandatory, non-bypassable gate — never a manual, occasionally-run local command. [Question 66](../interview-questions/07-security-vault.md#question-66-the-compliance-scan-that-found-secrets-in-plain-sight)

## `become` privilege escalation
- Never a shared, fleet-wide `become` password — passwordless, **command-scoped** `sudoers` entries (`NOPASSWD:` with an explicit command list, never `ALL`) is the correct pattern. [Question 67](../interview-questions/07-security-vault.md#question-67-the-become-password-that-became-everyones-problem)
- Hardcode `become_user` explicitly on security-relevant tasks rather than relying on inherited variables, which are subject to the full precedence chain and can be silently overridden by an unrelated `group_vars` change. [Question 90](../interview-questions/10-troubleshooting.md#question-90-the-become_user-that-quietly-became-someone-else)
