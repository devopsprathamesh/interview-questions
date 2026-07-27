# Diagram 7: Ansible Vault Encrypt/Decrypt Flow

Referenced from [`docs/security.md`](../docs/security.md) and [Lab 4](../labs/lab-04-ansible-vault/).

```mermaid
flowchart TD
    subgraph AtRest["Committed to git"]
        VarsFile["group_vars/production/vars.yml\n(plaintext, references vault_ names)"]
        VaultFile["group_vars/production/vault.yml\n(fully AES256-encrypted)"]
    end

    subgraph Runtime["ansible-playbook run"]
        PassSource["Vault password source:\n--vault-password-file script\nfetching from a secrets manager"]
        Decrypt["Decrypt vault.yml in memory\n(never written to disk decrypted)"]
    end

    VaultFile --> Decrypt
    PassSource --> Decrypt
    VarsFile -->|references e.g. vault_db_password| Merge[Merged variable space]
    Decrypt --> Merge
    Merge --> Task["Task uses {{ db_password }}\nno_log: true on the task itself"]
    Task -->|"no_log hides the VALUE\nfrom console/verbose output"| Output["Run output - value redacted"]
```

**Key points:**
- The vars/vault split keeps `git diff` useful on the plaintext file (you can see *that* a variable is referenced) while the actual secret value stays encrypted at rest.
- The vault **password** itself is the real key-management problem — a production setup fetches it from a secrets manager at run time via a password script, never a plaintext file sitting on disk long-term.
- `no_log` on the consuming task is a **display** control (console/log redaction), not a storage control — the decrypted value still exists in memory during the run, and any *other*, non-`no_log`'d task referencing the same variable would still expose it.
