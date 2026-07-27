# Production Troubleshooting Catalog

A consolidated runbook-style catalog of the failure modes senior Ansible interviews probe most often. Every entry follows: **Symptom → Likely causes → Investigation → Fix → Prevention.** Use the [Interview Response Framework](../README.md#interview-response-framework) verbatim when answering any of these live. Backs [`interview-questions/10-troubleshooting.md`](../interview-questions/10-troubleshooting.md).

## Connectivity and access

### Host unreachable
**Symptom:** `UNREACHABLE!` status for one or more hosts.
**Likely causes:** network/security-group block, SSH key not authorized, wrong `ansible_host`/inventory value, host genuinely down.
**Investigation:** `ansible <host> -m ping -vvv` for verbose connection diagnostics; confirm the exact `ansible_host`/`ansible_port`/`ansible_user` resolved for that host (inventory precedence can silently resolve to the wrong value).
**Fix:** correct the specific broken piece (security group, key, inventory value) — never broaden a security group to "just get it working" without understanding why it was scoped that way.
**Prevention:** a `ping`-only smoke-test play run before any real change play, so connectivity issues surface before any real task attempts.

### `become` / privilege escalation failure
**Symptom:** tasks fail with a permission or `sudo` password error, even though the SSH connection itself succeeded.
**Likely causes:** `become_password` not supplied where required, `requiretty` set in `sudoers` (blocks non-interactive sudo, and specifically blocks `pipelining`), the become user not actually in sudoers on that specific host.
**Investigation:** `ansible <host> -m shell -a "whoami" --become -vvv`; check `/etc/sudoers`/`sudoers.d` on the target directly if you have another access path.
**Fix:** correct the sudoers configuration (via a separate, already-working access path) or supply the missing become credential correctly; disable `requiretty` if you intend to use `pipelining`.
**Prevention:** bake correct sudoers configuration into the baseline/security-hardening role applied to every host at provisioning time, not discovered ad hoc per incident.

## Idempotency and logic bugs

### A playbook that "works" once but misbehaves on a second run
**Symptom:** re-running an already-successful playbook reports unexpected `changed` tasks, or outright fails the second time.
**Deep dive:** [`ansible-internals.md` §3](ansible-internals.md#3-idempotency--a-contract-you-write-not-a-guarantee-ansible-provides).
**Fast fix:** identify the specific `command`/`shell` task lacking a `creates`/`removes`/`changed_when` guard, or a template rendering non-deterministic content (an embedded raw timestamp) causing a spurious diff every run.

### Handler never fires despite its notifying task reporting `changed`
**Symptom:** a config file was updated but the service was never restarted to pick it up.
**Deep dive:** [`ansible-internals.md` §5](ansible-internals.md#5-handlers--deferred-execution-not-immediate).
**Fast fix:** check whether a *later* task in the same play failed before the play reached its end (or an explicit `meta: flush_handlers`) — queued handlers never ran because the play never got there. Re-run to completion, or add an explicit `flush_handlers` point right after the notifying tasks if the restart genuinely can't wait until the play's natural end.

### Variable not taking the expected value
**Deep dive:** [`inventory-and-variables.md` §4](inventory-and-variables.md#4-variable-precedence-order).
**Fast fix:** walk the actual precedence order rather than guessing — an `-e` from a previous manual run, a role `vars/main.yml` (higher precedence than `defaults`), or a more-specific `host_vars` entry is almost always the culprit.

## Modules, collections, and templating

### "Module not found" / "couldn't resolve module/action"
**Symptom:** a task referencing e.g. `amazon.aws.ec2_instance` fails immediately with a module-resolution error.
**Likely causes:** the collection isn't installed in the current execution environment, or `requirements.yml` wasn't updated/re-installed after a developer added a new collection dependency locally.
**Investigation:** `ansible-galaxy collection list` on the machine/EE actually running the play; diff against `requirements.yml`.
**Fix:** `ansible-galaxy collection install -r requirements.yml`; ensure CI's execution environment build step actually re-runs this on every change to `requirements.yml`, not just on a cache miss.

### Jinja2 templating error ("undefined variable", syntax error)
**Symptom:** a task fails during templating, before the module itself even runs.
**Investigation:** `ansible-playbook ... -vvv` shows the exact template/expression that failed; check whether the variable is conditionally defined elsewhere (a role dependency that wasn't triggered, a fact that wasn't gathered because `gather_facts: false`).
**Fix:** use `| default(...)` for genuinely-optional variables, or `is defined` guards; if a fact is missing, confirm `gather_facts` is actually enabled for that play/host.

## Inventory and scale

### Dynamic inventory returns zero hosts, or the wrong hosts
**Symptom:** a play reports "no hosts matched," or matches an unexpectedly small/large set.
**Likely causes:** filter/tag mismatch (a tag value typo, an environment tag that doesn't match what's actually on the instances), region misconfiguration, IAM permissions insufficient for the dynamic inventory plugin's underlying API calls.
**Investigation:** `ansible-inventory -i inventory/aws_ec2.yml --list` to see exactly what the plugin resolved, independent of any playbook; compare against the AWS console/CLI directly for the same filter.
**Fix:** correct the filter/tag criteria or IAM permissions; this is the Ansible analog of the "wrong workspace/account/region" Terraform incident — always verify inventory resolution independently before trusting a play's host-count silently.

### Duplicate or conflicting host entries from overlapping inventory sources
**Symptom:** a host appears twice with two different sets of resolved variables, or a group's membership looks wrong.
**Likely causes:** combining a static inventory file and a dynamic inventory plugin (via an inventory directory with multiple sources) where both happen to reference the same host under slightly different names/IPs.
**Fix:** `ansible-inventory --list` to see the merged result explicitly; standardize on one canonical hostname/IP source of truth per host.

## Execution and performance

### A partially-completed run (some hosts succeeded, some failed/were skipped)
**Symptom:** a playbook run against 200 hosts fails partway, with an uneven mix of `ok`/`changed`/`failed`/`unreachable`.
**Investigation:** Ansible automatically writes a `.retry` file listing only the hosts that failed.
**Fix:** `ansible-playbook site.yml --limit @site.retry` to re-run **only** against the hosts that didn't succeed — never blindly re-run against the full inventory, which would re-apply (harmlessly, if truly idempotent — but verify that assumption) against hosts that already succeeded.
**Prevention:** for genuinely large fleets, use `serial` with `max_fail_percentage` so a systemic issue (a bad role change) halts the rollout after a small percentage of failures, rather than grinding through the entire fleet before anyone notices a pattern.

### API throttling / connection storms against a large fleet
**Symptom:** a play against hundreds of hosts sees a wave of connection failures or cloud-API throttling partway through.
**Fix:** reduce `forks`, or switch to `serial` batching with a pause between batches; for cloud API calls specifically (not just SSH connections), the same "reduce concurrency for a rate-limited service" lesson from the companion Terraform repository's `-parallelism` guidance applies directly.

### A play against 500 hosts is unexpectedly slow
**Deep dive:** [`ansible-internals.md` §2](ansible-internals.md#2-execution-strategy-and-parallelism) and [`interview-questions/12-performance-scale.md`](../interview-questions/12-performance-scale.md).
**Fast fix:** profile first (`ansible.posix.profile_tasks` callback) — often a small number of slow tasks (unnecessary fact-gathering, a slow lookup plugin making a control-node-side API call per host) dominate, not raw host count; only then consider raising `forks` or switching strategy.

## Secrets and CI

### Vault decryption failure in CI
**Symptom:** `ERROR! Decryption failed` or the pipeline can't find a vault password at all.
**Investigation:** confirm which vault ID the affected file was encrypted with, and confirm the CI job is actually fetching/passing the matching password (a common cause: a vault password rotated without updating the secrets-manager entry CI's vault-password script reads from).
**Fix:** correct the password source; never work around this by decrypting the file once locally and committing the plaintext "just to unblock the pipeline" — that's a genuine secret exposure, not a shortcut.

### Concurrent pipelines targeting the same fleet
**Deep dive:** [`cicd.md` §4](cicd.md#4-concurrency-controls--a-fleet-level-not-just-a-state-level-concern).
**Fast fix:** CI-level concurrency group scoped to the target inventory/environment, or AWX Job Template concurrency limiting.

## Common weak answer vs. senior answer (cross-cutting)

| Pattern | Weak answer | Senior answer |
|---|---|---|
| Any partial/failed fleet run | "Re-run the whole playbook against everything" | Use the auto-generated `.retry` file / `--limit` to target only what actually failed, after understanding *why* it failed |
| Any "it worked once but not the second time" | "Ansible must be buggy" | Idempotency is a contract *you* write via proper modules and `command`/`shell` guards — find the specific unguarded task |
| Any unexpected variable value | "Ansible variables are confusing/random" | Walk the actual, fixed precedence order to find what's silently winning |

## Related material
- Interview questions: [`interview-questions/10-troubleshooting.md`](../interview-questions/10-troubleshooting.md)
- Diagrams: [`diagrams/14-drift-detection.md`](../diagrams/14-drift-detection.md)
