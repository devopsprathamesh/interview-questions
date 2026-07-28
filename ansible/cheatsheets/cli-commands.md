# Cheat Sheet: Ansible CLI Commands

| Command | Purpose | Notes |
|---|---|---|
| `ansible all -m ping` | Connectivity check across inventory | First command to run against any new inventory |
| `ansible-playbook site.yml` | Run a playbook | |
| `ansible-playbook site.yml --check --diff` | Preview changes without applying | Not a saved artifact — re-evaluates live; see [Question 72](../interview-questions/08-cicd-automation.md#question-72-the-plan-ansible-never-had) |
| `ansible-playbook site.yml --syntax-check` | Structural YAML/syntax validity only | Does not catch logic errors — [Question 85](../interview-questions/09-testing-validation.md#question-85-the-syntax-check-that-checked-nothing-meaningful) |
| `ansible-playbook site.yml --limit "group1,!group2"` | Narrow the target host set | Combine groups/exclusions |
| `ansible-playbook site.yml --tags "config"` | Run only tagged tasks | Tags are unenforced metadata, not a security boundary — [Question 10](../interview-questions/01-ansible-core.md#question-10-the-tag-that-skipped-the-thing-everyone-needed) |
| `ansible-playbook site.yml -e "key=value"` | Extra vars — highest precedence, always wins | [Question 16](../interview-questions/02-inventory-variables.md#question-16-the--e-that-nobody-remembered-setting) |
| `ansible-playbook site.yml --vault-id dev@script.sh` | Decrypt with a specific, scoped vault password | Multiple `--vault-id` flags for multiple simultaneous vaults |
| `ansible-playbook site.yml -vvv` | Verbose output for real diagnostics | `-vvvv` adds connection-plugin-level detail |
| `ansible-playbook site.yml --start-at-task "Task name"` | Resume from a specific task | Useful mid-incident, not a substitute for idempotency |
| `ansible-playbook site.yml --list-hosts` | Show resolved target hosts without running anything | Confirms inventory pattern resolution before a real run |
| `ansible-playbook site.yml --list-tasks` | Show the task list without running | Confirms role/task ordering, e.g. after adding a role dependency |
| `ansible-inventory -i inventory/ --graph` | Show resolved inventory as a tree | The definitive check for dynamic inventory group resolution |
| `ansible-inventory -i inventory/ --list` | Full resolved inventory + hostvars as JSON | Pipe to `jq` for scripted checks |
| `ansible-vault create/edit/view/encrypt/decrypt/rekey FILE` | Vault file lifecycle operations | `rekey` for password rotation without re-encrypting content manually |
| `ansible-vault encrypt_string 'value' --name 'var_name'` | Encrypt a single value inline | For embedding one secret in an otherwise-plaintext vars file |
| `ansible-galaxy collection install NAME` | Install a collection | Pin exact versions in `requirements.yml` for reproducibility |
| `ansible-galaxy role install NAME` | Install a role from Galaxy | |
| `ansible-doc MODULE_NAME` | Show a module's documentation and options | Faster than searching docs for parameter names |
| `ansible-config dump --only-changed` | Show effective config differing from defaults | Diagnoses "why is my ansible.cfg setting not applying" |
| `ANSIBLE_STDOUT_CALLBACK=json ansible-playbook site.yml` | Structured JSON output | Never regex-parse human-readable output — [Question 37](../interview-questions/04-modules-plugins.md#question-37-the-output-nobody-could-parse) |

## Exit codes
- `0`: success, no failures/unreachable hosts
- `1`: general error (parse error, unhandled exception)
- `2`: one or more hosts failed or were unreachable
- `3`: hosts unreachable (in some older versions; check `4` for unreachable-specific in newer combined codes)
- `4`: parser error
- `5`: bad or incomplete options
