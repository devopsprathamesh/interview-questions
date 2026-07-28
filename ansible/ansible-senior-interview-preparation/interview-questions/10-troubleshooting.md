# Category 10: Troubleshooting and Production Incidents

Questions 87–98 of 120. Category weight: 12 questions. Deep-dive reference: [`docs/troubleshooting.md`](../docs/troubleshooting.md).

---

## Question 87: The retry file that told half the story

### Scenario
A large playbook run against 500 hosts fails partway through, leaving a `.retry` file. An engineer runs `ansible-playbook site.yml --limit @site.retry` to resume, and it completes successfully — but a later audit finds 15 hosts were never actually touched by either the original or the retry run, having failed in a way that didn't generate a retry-file entry for them.

### Interview Question
Diagnose why some failed hosts didn't appear in the retry file.

### Strong Senior-Level Answer
**Initial assessment:** the `.retry` file only lists hosts that reached a definitively-failed task state during the run — hosts that became genuinely unreachable *before* any task could even attempt to run against them (a connection timeout during the initial fact-gathering/connection phase, rather than a task failure) may be recorded differently or not consistently included, depending on exactly when and how the failure occurred.

**Technical reasoning:** Ansible's retry-file mechanism is generated based on the `PLAY RECAP`'s failed/unreachable host categorization at the end of a run — a host that was "unreachable" throughout (never successfully connected at all) is tracked separately from a host that connected fine but had a task fail partway through, and depending on the specific Ansible version/configuration, the retry file's exact inclusion behavior for "unreachable throughout" hosts can differ from "failed mid-task" hosts in ways that are easy to overlook.

**Investigation process:** compare the original run's full `PLAY RECAP` output (showing every host's final status: ok/changed/unreachable/failed/skipped) against the retry file's actual contents — this reveals exactly which category of failure the 15 missed hosts fell into and whether the retry file's known behavior explains the gap.

**Recommended solution:** never rely solely on the `.retry` file for resuming a partial run against a large fleet — instead, explicitly derive the list of hosts needing re-run by comparing the full `PLAY RECAP` (or a structured, machine-readable output via a callback plugin per Category 4's guidance) against the intended full host list, capturing every category of non-success (unreachable, failed, and skipped-due-to-earlier-failure) rather than trusting the retry file's specific, narrower inclusion logic.

**Risk controls:** for any large-fleet run, treat the actual, complete host-coverage verification (per the companion Ansible Question 76's silent-partial-coverage pattern) as the authoritative check, not the retry file's convenience shortcut.

**Validation steps:** after deriving the complete list of un-succeeded hosts via full `PLAY RECAP` comparison, re-run against exactly that list and confirm, this time, that every originally-intended host is now accounted for as either successful or explicitly, deliberately still-excluded for a known reason.

**Rollback or recovery strategy:** for the 15 missed hosts, run the playbook against them specifically once identified, bringing them to the same state as the rest of the fleet.

**Long-term prevention:** build a structured, machine-readable run-completion report (via a JSON callback plugin, per the companion category's guidance) as the standard mechanism for verifying complete fleet coverage after any large run, rather than relying on the `.retry` file's specific, narrower semantics for anything beyond a quick, informal resume.

### Step-by-Step Implementation
```bash
# Derive the complete "not yet succeeded" host list from full recap, not just .retry
ansible-playbook site.yml -i inventory --list-hosts > intended-hosts.txt
ansible-playbook site.yml -i inventory | tee run-output.log
grep -E "unreachable=[1-9]|failed=[1-9]" run-output.log | awk '{print $1}' > actually-failed-hosts.txt
# Re-run against the ACTUAL, complete failure list, not just @site.retry
ansible-playbook site.yml -i inventory --limit @actually-failed-hosts.txt
```

### Under-the-Hood Explanation
The `.retry` file is generated from Ansible's internal tracking of hosts that failed during play execution — its exact behavior for hosts that were unreachable from the very start (versus failing mid-task) has historically had edge cases and version-specific quirks, meaning it's a convenient but not always fully authoritative record of every host needing attention after a partial run.

### Common Weak Answer
"The retry file failed to include some hosts, that's an Ansible bug."

### Why the Weak Answer Fails
This assumes a defect rather than checking the documented, known behavior distinguishing unreachable-throughout hosts from mid-task failures — the correct response is verifying actual coverage via the full recap rather than trusting the retry file's narrower, convenience-oriented semantics as complete.

### Follow-Up Questions
1. How would you build a callback plugin producing a structured, complete run-report as a more reliable alternative to the `.retry` file?
2. What's the difference in Ansible's internal handling of "unreachable" versus "failed" host states?
3. How does this connect to the companion Ansible Question 76's silent-partial-CI-coverage pattern?

### Key Interview Signals
Understands the `.retry` file's specific, narrower scope and doesn't trust it as a complete record of every host needing attention, instead deriving complete coverage from the full `PLAY RECAP`.

### Hands-On Connection
[Lab 14 — Troubleshooting and Recovery](../labs/lab-14-troubleshooting-and-recovery/).

---

## Question 88: The handler that fired for the wrong reason

### Scenario
A playbook has two tasks notifying the same handler (`restart nginx`) — one templating the main config file, another templating an unrelated, rarely-changed SSL certificate file. A change to the SSL certificate task (which should rarely trigger) causes the handler to fire and restart nginx, coincidentally during a high-traffic period, causing a brief but noticeable service blip nobody expected at that moment.

### Interview Question
Diagnose why an infrequent, seemingly-unrelated task change caused an unexpected service restart at a bad time.

### Strong Senior-Level Answer
**Initial assessment:** two independent tasks notifying the *same* handler means either one triggering `changed` fires the shared restart — this is often intentional (either change genuinely does require a restart), but if the actual operational risk/timing-sensitivity of the two triggering conditions differs significantly (a routine config change versus a rare certificate rotation), lumping them into the same handler removes any ability to treat them with different care.

**Technical reasoning:** handlers are deferred and flushed once at the end of the play (or at `meta: flush_handlers`) regardless of which specific notifying task triggered them — there's no built-in mechanism to distinguish "this handler fired because of a routine, frequently-expected change" from "this handler fired because of a rare, infrequent change that maybe warrants extra caution about timing."

**Investigation process:** confirm both tasks do indeed notify the identical handler, and assess whether the certificate-file change genuinely requires an nginx restart to take effect (it likely does, if nginx needs to reload the cert), versus whether it could instead trigger a more graceful mechanism (a reload rather than a hard restart, if the application supports config reload without a full process restart).

**Recommended solution:** where the underlying application supports it, prefer a graceful **reload** handler over a hard **restart** for configuration changes that don't require a full process restart (many services, including nginx, support `systemctl reload` reading updated config/certs without dropping existing connections) — significantly reducing the actual disruption even when the handler does fire unexpectedly.

**Risk controls:** for any handler whose triggering could have genuinely disruptive timing implications, consider whether the underlying task should be scheduled/deployed during a defined maintenance window rather than an ad hoc run at any time, independent of the reload-vs-restart distinction.

**Validation steps:** after switching to reload (where supported), confirm a certificate update no longer causes a connection-dropping restart, verified via a test showing existing connections survive the reload.

**Rollback or recovery strategy:** if reload doesn't correctly pick up the certificate change for some reason (some services genuinely require a full restart for certain configuration types), revert to restart but pair it with the maintenance-window risk control instead.

**Long-term prevention:** review every shared handler notified by multiple, operationally-different-risk-profile tasks, and prefer the least-disruptive mechanism (reload over restart) that correctly achieves the intended effect — treating "does this handler's actual disruption level match what each notifying task's own risk profile warrants" as a standard handler-design review question.

### Step-by-Step Implementation
```yaml
handlers:
  - name: reload nginx   # graceful reload instead of hard restart
    ansible.builtin.service:
      name: nginx
      state: reloaded
```

### Under-the-Hood Explanation
`state: reloaded` sends a reload signal (typically `SIGHUP`) to the service, which most well-behaved services (including nginx) handle by re-reading their configuration/certificates without dropping existing, in-flight connections — a materially less disruptive mechanism than `state: restarted`, which stops and starts the process entirely, closing every existing connection regardless of whether the underlying config change genuinely required that level of disruption.

### Common Weak Answer
"Just use separate handlers for each task so they never interact."

### Why the Weak Answer Fails
This avoids the shared-handler coincidence but doesn't address the actual disruption risk if a restart genuinely is needed for either change — the better fix (reload over restart, where supported) reduces the real-world impact regardless of how many tasks share the handler.

### Follow-Up Questions
1. How would you determine whether a given service genuinely requires a full restart versus supporting a graceful reload for a specific configuration change type?
2. What's the trade-off of maintenance-window-gating a task versus relying on graceful reload alone?
3. How does this connect to the companion Ansible Question 2's handler-flush-trap discussion from Category 1?

### Key Interview Signals
Identifies the actual disruption mechanism (hard restart vs. graceful reload) as the real lever to address, rather than just isolating handlers to avoid the coincidental shared-trigger, and reasons about timing-sensitivity for genuinely disruptive changes.

### Hands-On Connection
[Lab 14 — Troubleshooting and Recovery](../labs/lab-14-troubleshooting-and-recovery/).

---

## Question 89: The fact that lied about the world

### Scenario
A playbook uses `ansible_facts['default_ipv4']['address']` to determine a host's IP for a configuration template. On a host with multiple network interfaces (recently added a second NIC for a new VPC peering connection), this fact now returns a different IP than the one the application actually needs to bind to, causing a configuration file with an incorrect bind address.

### Interview Question
Diagnose why the "default" fact stopped reflecting the intended IP, and design a more robust approach.

### Strong Senior-Level Answer
**Initial assessment:** `ansible_facts['default_ipv4']` reflects whatever the *operating system* considers its default route/primary interface, which is a property of the host's own routing table — it was never actually a semantic guarantee of "the IP this specific application should bind to," and adding a second NIC changed the OS's own notion of "default" in a way this playbook's implicit assumption didn't anticipate.

**Technical reasoning:** relying on `default_ipv4` conflates "the OS's default route interface" with "the interface this application needs" — these happened to coincide before the second NIC was added, but nothing in the playbook's logic ever actually verified that coincidence was guaranteed to hold, exactly the kind of implicit, unverified assumption that silently breaks when the underlying environment changes.

**Investigation process:** confirm exactly which interface/IP the application actually needs to bind to (informed by its own genuine requirement, e.g., the interface on the VPC subnet serving its intended traffic) versus what `default_ipv4` now resolves to post-second-NIC — this confirms the mismatch's exact nature.

**Recommended solution:** replace the implicit `default_ipv4` reliance with an explicit, intentional interface/IP selection — either an explicitly-named interface (`ansible_facts['eth0']['ipv4']['address']`, if the interface name is reliably consistent) or, more robustly, a variable explicitly set per-host/per-group declaring the intended bind IP, rather than deriving it implicitly from OS routing behavior that was never actually guaranteed to reflect application intent.

**Risk controls:** audit other playbooks/roles for similar implicit reliance on `default_ipv4`/`default_ipv6` where the actual intent is a specific, named interface — this exact class of "coincidental correctness that breaks on environment change" is easy to have accumulated elsewhere too.

**Validation steps:** after switching to explicit interface/IP selection, confirm the configuration file correctly reflects the intended bind address regardless of how many additional NICs are added to the host in the future.

**Rollback or recovery strategy:** fix the currently-misconfigured hosts by re-running the playbook with the corrected, explicit interface selection.

**Long-term prevention:** treat any fact-derived value used for a semantically-specific purpose (like "the IP an application binds to") as requiring an explicit, intentional selection rather than an implicit OS-behavior-derived default — `default_ipv4`/`default_ipv6` are appropriate when genuinely "whatever the OS considers default" is the actual intent, not as a stand-in for "the specific interface this application cares about."

### Step-by-Step Implementation
```yaml
# Before - implicit, coincidental
bind_address: "{{ ansible_facts['default_ipv4']['address'] }}"

# After - explicit, intentional (per-host/group variable, not OS-routing-derived)
bind_address: "{{ app_bind_ip }}"   # explicitly set in host_vars/group_vars per actual requirement
```

### Under-the-Hood Explanation
`ansible_facts['default_ipv4']` is derived from the host's own kernel routing table (specifically, the interface associated with the default route) — this is a genuinely useful fact for "what does this OS consider its primary network path," but has no inherent connection to "what IP should this specific application bind to," a distinction that only becomes visible once a host's routing configuration changes in a way that decouples the two, exactly as adding a second NIC did here.

### Common Weak Answer
"Just pin the playbook to always use the first NIC (eth0) regardless of routing."

### Why the Weak Answer Fails
This substitutes one implicit assumption (default route) for another equally implicit one (interface naming convention) without addressing the actual root issue — the fix should make the application's specific IP requirement an explicit, intentional variable, not another guess based on a different unverified assumption about interface ordering/naming.

### Follow-Up Questions
1. How would you audit the broader playbook library for other instances of implicit `default_ipv4`/`default_ipv6` reliance where explicit intent was actually meant?
2. What's the risk of interface-name-based selection (`eth0`) versus an explicitly-set variable, especially across different OS/cloud-provider naming conventions?
3. How does this relate to the earlier "variable that meant two different things" pattern from Category 2?

### Key Interview Signals
Correctly identifies that `default_ipv4` reflects OS routing behavior, not application intent, and replaces an implicit, coincidentally-correct assumption with an explicit, intentional configuration value.

### Hands-On Connection
[Lab 14 — Troubleshooting and Recovery](../labs/lab-14-troubleshooting-and-recovery/).

---

## Question 90: The become_user that quietly became someone else

### Scenario
A playbook task uses `become_user: appuser` to run a specific command as a non-root application user. After an unrelated change to the inventory's `group_vars`, the task starts silently running as `root` instead — the actual file ownership/permissions of files it creates change accordingly, causing a subtle permissions-related application failure days later.

### Interview Question
Diagnose why `become_user` silently changed effective behavior without any direct change to the task itself.

### Strong Senior-Level Answer
**Initial assessment:** `become_user` is a variable-driven setting subject to Ansible's full precedence chain (per Category 2's 19-level precedence order) — a seemingly-unrelated `group_vars` change could have introduced a higher-precedence `ansible_become_user` (or `become_user`) value overriding what the task itself intends, without the task's own YAML changing at all.

**Technical reasoning:** if the task doesn't hardcode `become_user` explicitly but instead relies on an inherited variable value, any change higher in the precedence chain (a new or modified `group_vars` entry) silently changes the *effective* value the task actually uses — exactly the kind of precedence-driven surprise Category 2's variable-precedence guidance warns about, here manifesting as a security/permissions-relevant behavior change rather than a purely functional one.

**Investigation process:** trace the actual, currently-effective `become_user` value for this specific task/host combination (`ansible-inventory`/`--extra-vars` debugging, or `ansible.builtin.debug` on the relevant variable) and identify exactly which `group_vars` change introduced the conflicting, higher-precedence value.

**Recommended solution:** for any task where the specific become-user identity is a deliberate, security-relevant choice (not something that should be silently inheritable/overridable), hardcode `become_user` explicitly on the task itself rather than relying on an inherited variable — removing the precedence-chain surprise risk entirely for this specific, consequential setting.

**Risk controls:** audit other tasks relying on inherited `become_user`/`become` settings for similarly security-relevant privilege-identity decisions, treating implicit inheritance of privilege-escalation-target as a red flag warranting explicit hardcoding wherever the specific identity genuinely matters.

**Validation steps:** after hardcoding, confirm the task now correctly and consistently runs as `appuser` regardless of any future `group_vars` changes, and confirm the previously-affected files' ownership/permissions are corrected to the intended state.

**Rollback or recovery strategy:** fix the affected files' ownership/permissions directly (re-running the corrected playbook against the affected hosts) to restore the intended state.

**Long-term prevention:** treat `become_user` (and any other privilege-escalation-target setting) as a security-relevant configuration deserving explicit, task-level hardcoding rather than implicit variable inheritance, specifically because the precedence chain (per Category 2) makes inherited values silently overridable by seemingly-unrelated changes elsewhere in the variable hierarchy.

### Step-by-Step Implementation
```yaml
- name: Run task as appuser (explicitly hardcoded, not inherited)
  ansible.builtin.command: /opt/app/bin/migrate
  become: true
  become_user: appuser   # explicit on the task - immune to group_vars precedence surprises
```

### Under-the-Hood Explanation
Without an explicit, task-level `become_user`, Ansible resolves the effective value through its full variable-precedence chain (per Category 2) — any `group_vars`/`host_vars` entry setting `ansible_become_user` (or an equivalent) at a level with sufficient precedence silently becomes the actual, effective value for every task not explicitly overriding it, with no warning that a change to an ostensibly-unrelated variables file has altered a specific task's real, executed privilege identity.

### Common Weak Answer
"This must be an Ansible bug — the task's own become_user setting shouldn't be affected by unrelated group_vars changes."

### Why the Weak Answer Fails
This is Ansible's precedence system working exactly as documented — the task never actually had its own hardcoded `become_user` in this scenario, meaning it was always inheriting from the variable chain, and any change to that chain's higher-precedence sources correctly (if surprisingly) changes the effective value.

### Follow-Up Questions
1. How would you audit every task in a playbook library for implicit, inheritable privilege-escalation settings that should instead be hardcoded?
2. What's the broader lesson here about which settings should always be explicit versus which are appropriately left to variable inheritance?
3. How does this connect to the earlier "role that couldn't be overridden" and "the -e that nobody remembered setting" precedence-surprise patterns from Category 2?

### Key Interview Signals
Correctly traces a silent behavior change to Ansible's variable-precedence chain rather than assuming a platform defect, and hardcodes security-relevant settings explicitly rather than leaving them implicitly inheritable.

### Hands-On Connection
[Lab 14 — Troubleshooting and Recovery](../labs/lab-14-troubleshooting-and-recovery/) and [Lab 10 — Security Hardening](../labs/lab-10-security-hardening/).

---

## Question 91: The task that succeeded everywhere except where it mattered most

### Scenario
A fleet-wide playbook run reports 499 of 500 hosts as `ok`/`changed` successfully, and 1 host as `unreachable`. The team, satisfied with a "99.8% success rate," moves on — but the one unreachable host happens to be the fleet's primary database server, the single most critical host in the entire run.

### Interview Question
Evaluate the team's "99.8% success" framing and explain what's actually wrong with it.

### Strong Senior-Level Answer
**Initial assessment:** treating fleet-wide success purely as an aggregate percentage, without weighting by each host's actual criticality, is a real and common mistake — a 99.8% success rate sounds excellent in the abstract, but if the single failed host is the most consequential one in the entire fleet, the aggregate percentage is actively misleading about the actual, real-world risk this run's incomplete coverage represents.

**Technical reasoning:** `ansible-playbook`'s own `PLAY RECAP` reports purely per-host counts with no built-in concept of host criticality/weighting — a database server and a low-priority batch-processing node are counted identically as "one host" in the aggregate statistics, meaning any purely count-based success framing inherently treats all hosts as equally important, which is essentially never actually true across a real, heterogeneous fleet.

**Investigation process:** confirm why the database host specifically was unreachable (a genuinely important root-cause question in its own right, distinct from the reporting-framing issue) and assess what state this leaves the database host in relative to the intended change — is it now inconsistent with the rest of the fleet in some functionally important way.

**Recommended solution:** never accept an aggregate success percentage without explicitly checking which *specific* hosts failed and their relative criticality — for any fleet-wide run, treat a failure on a genuinely critical host as requiring immediate, prioritized attention regardless of how small it makes the aggregate failure percentage look, and fix the actual reason the database host was unreachable before considering this run complete in any meaningful sense.

**Risk controls:** for genuinely critical hosts (databases, load balancers, anything single-point-of-failure-adjacent), consider running them in a separate, dedicated play/step with its own explicit success verification, rather than lumping them into the same aggregate-percentage reporting as the rest of a large, heterogeneous fleet.

**Validation steps:** once the database host's reachability issue is resolved, re-run the playbook against it specifically and confirm it reaches the same, intended state as the rest of the fleet — genuine completion, not just an improved aggregate percentage.

**Rollback or recovery strategy:** not applicable beyond completing the intended change on the affected host.

**Long-term prevention:** design fleet-wide run reporting/alerting to weight by host criticality (e.g., any failure on a host tagged `critical: true` triggers an immediate, high-priority alert regardless of the overall aggregate success rate), rather than relying purely on an undifferentiated percentage that treats every host as equally important — exactly the same "aggregate metrics can mask a severe issue for a critical minority" lesson from the companion EKS repository's P50-versus-P99 discussion, applied here to fleet-run success reporting.

### Step-by-Step Implementation
```yaml
# Separate the fleet by criticality for weighted, appropriately-prioritized reporting
- name: Apply to critical hosts (dedicated play, verified independently)
  hosts: critical_infrastructure
  # ... explicit success verification, immediate alert on any failure

- name: Apply to general fleet (aggregate reporting acceptable here)
  hosts: general_fleet
```

### Under-the-Hood Explanation
`ansible-playbook`'s `PLAY RECAP` is a purely mechanical tally of per-host outcomes — it has no concept of "importance" or "criticality" built in at all, meaning any weighting by actual business/operational impact must be applied by the operators interpreting the output, not something the tool itself provides; treating an aggregate percentage as sufficient without this human-applied criticality lens is exactly the gap this scenario demonstrates.

### Common Weak Answer
"99.8% success is a great result, just retry the one host later when convenient."

### Why the Weak Answer Fails
This treats every host as equally weighted in the success calculation, missing that the specific failed host's criticality (the primary database) makes this run's actual, meaningful completion status far worse than the aggregate percentage suggests — "later when convenient" is an inappropriate urgency level for the fleet's most critical host being left in an unknown, potentially inconsistent state.

### Follow-Up Questions
1. How would you design host-criticality tagging and weighted alerting across a large, heterogeneous fleet?
2. What's the appropriate response urgency difference between a failed low-priority batch node versus a failed critical database host?
3. How does this connect to the companion EKS repository's aggregate-metric-masking-a-severe-minority-issue lesson (P50 vs. P99)?

### Key Interview Signals
Recognizes that an aggregate success percentage can mask a critical, high-impact failure, and designs criticality-weighted reporting/alerting rather than accepting an undifferentiated percentage as sufficient evidence of a run's actual completion.

### Hands-On Connection
[Lab 14 — Troubleshooting and Recovery](../labs/lab-14-troubleshooting-and-recovery/).

---

## Question 92: The playbook that succeeded by doing nothing

### Scenario
A playbook task with a `when` condition referencing a typo'd variable name (`when: evironment == "production"` instead of `environment`) has been silently evaluating to `false` (since the mistyped variable is undefined, and the condition's comparison against an undefined value resolves to a skip) for months, meaning an intended security-hardening task has never actually applied to any host.

### Interview Question
Diagnose why this typo didn't produce an error, and design a detection mechanism.

### Strong Senior-Level Answer
**Initial assessment:** this is a variant of the Category 1 "conditional that always evaluated true" pattern, here evaluating to consistently *false* instead — Ansible's default handling of a `when` condition referencing an undefined variable results in the task being silently *skipped*, not an error, meaning a typo in a conditional can cause a task to simply never run, indefinitely, with no failure signal anywhere.

**Technical reasoning:** Jinja2's undefined-variable handling within a `when` condition (depending on Ansible's configured `error_on_undefined_vars` behavior, which defaults to permissive in many contexts for `when` specifically) treats the comparison as `false` rather than raising an error — meaning `evironment == "production"` silently evaluates to "condition not met, skip this task" for every single host, forever, since the typo'd variable name never actually resolves to anything.

**Investigation process:** review the play's `--check --diff` output (or, more directly, `ansible-playbook -vvv` verbose output showing exact `when` evaluation) for this specific task across a sample of hosts — confirming it's been consistently skipped, and identifying the exact typo causing it.

**Recommended solution:** fix the typo (`environment` not `evironment`), and add an explicit `assert` early in the play verifying that any variable used in a security-critical conditional is actually defined and has an expected value — turning a silent, skip-producing typo into a loud, immediate failure if the same mistake recurs.

**Risk controls:** for the period this task was silently skipped, assess and remediate the actual security-hardening gap this left across the fleet (the intended hardening was never applied) — this is a genuine, if unintentional, compliance gap requiring its own remediation, not just a code fix.

**Validation steps:** after fixing the typo, confirm the task now correctly executes (via `--check --diff` showing it would apply, or an actual run showing `changed: true` on hosts genuinely needing it), and confirm the assert catches a deliberately-reintroduced version of the same typo.

**Rollback or recovery strategy:** not applicable — this is a fix-forward correction, not a change requiring rollback.

**Long-term prevention:** treat any security-critical `when` condition as warranting an explicit `assert` verifying its referenced variables are defined and behave as expected, exactly mirroring the Category 1 lesson (Question 5) about undefined-variable typos in conditionals — silent, skip-producing failures for security-relevant tasks are a genuinely dangerous category of bug precisely because nothing about their failure mode is loud or visible.

### Step-by-Step Implementation
```yaml
- name: Verify environment variable is correctly defined before conditional hardening tasks
  ansible.builtin.assert:
    that:
      - environment is defined
      - environment in ['dev', 'staging', 'production']
    fail_msg: "environment variable must be defined and valid - check for typos in referencing tasks"

- name: Apply security hardening (correctly spelled conditional)
  ansible.builtin.include_tasks: hardening.yml
  when: environment == "production"   # fixed typo
```

### Under-the-Hood Explanation
A `when` condition referencing an undefined Jinja2 variable, in many Ansible configurations, evaluates the overall boolean expression as falsy rather than raising a hard error — this is a deliberate design choice allowing conditionals to gracefully handle optional/sometimes-undefined variables, but it means a genuine typo in a variable name produces the exact same "condition not met, skip" behavior as an intentionally-false condition, with no distinguishing signal between the two.

### Common Weak Answer
"If the task was skipped for months without any error, it must not actually be needed."

### Why the Weak Answer Fails
This inverts cause and effect — the task was skipped due to a typo, not because it was determined unnecessary; treating months of silent skipping as evidence of the task's own unimportance misses the actual bug entirely and risks leaving the real, intended security-hardening gap unaddressed indefinitely.

### Follow-Up Questions
1. How would you audit an entire playbook library for other `when` conditions referencing potentially-undefined/typo'd variable names?
2. What's the trade-off of Ansible's permissive undefined-variable-in-when behavior versus a stricter, error-on-undefined default?
3. How does this connect directly to Category 1's Question 5 (the conditional that always evaluated true) as the same underlying pattern in the opposite direction?

### Key Interview Signals
Recognizes that a `when` condition referencing an undefined variable due to a typo produces a silent skip rather than an error, and designs an explicit assert to convert this exact class of mistake into a loud, immediate failure rather than months of undetected non-execution.

### Hands-On Connection
[Lab 14 — Troubleshooting and Recovery](../labs/lab-14-troubleshooting-and-recovery/) and [Lab 10 — Security Hardening](../labs/lab-10-security-hardening/).

---

## Question 93: The rescue block that rescued the wrong thing

### Scenario
A `block`/`rescue` structure is designed to catch a specific, expected failure (a package already being at the desired version, causing a benign non-zero exit) and continue gracefully. During an actual incident, an entirely different, genuinely serious failure (a disk-full condition preventing any file write) triggers the same `rescue` block, which was written broadly enough to catch and silently continue past this unrelated, serious error too.

### Interview Question
Diagnose this overly-broad rescue block and redesign it.

### Strong Senior-Level Answer
**Initial assessment:** per Category 1's Question 6 (the block that recovered silently), a `rescue` block that isn't scoped to the *specific* failure it's meant to handle will also silently catch and mask entirely unrelated, more serious failures — exactly what happened here, where a genuinely serious disk-full condition was swallowed by a rescue block only ever intended for a specific, benign package-version edge case.

**Technical reasoning:** Ansible's `rescue` block triggers on *any* failure within its corresponding `block`, with no built-in mechanism to distinguish "the specific failure type I designed this rescue for" from "some entirely different failure that happens to also raise a non-zero return code" — this distinction must be explicitly built into the rescue block's own logic if it's meant to be failure-specific rather than a catch-all.

**Investigation process:** review the rescue block's actual task content and confirm it has no check on *why* the preceding block failed before deciding to continue gracefully — this confirms the over-broad-catch diagnosis.

**Recommended solution:** add explicit logic within the `rescue` block inspecting the actual failure reason (e.g., checking `ansible_failed_result.msg` or stderr content for the specific, expected "already at desired version" pattern) before deciding to continue gracefully — and for any failure reason that doesn't match the specific, expected pattern, explicitly re-raise/fail loudly via `ansible.builtin.fail` rather than silently continuing.

**Risk controls:** treat every `rescue` block as needing this same specific-failure-matching discipline, per Category 1's guidance — a rescue block with no failure-type discrimination is functionally a blanket "ignore any error and continue" mechanism, which is almost never actually the intended behavior.

**Validation steps:** after adding the specific-failure-matching logic, deliberately trigger both the originally-intended benign failure (confirming it's still gracefully handled) and a different, unrelated failure (confirming it's now correctly surfaced as a loud failure, not silently swallowed).

**Rollback or recovery strategy:** for the specific incident, the disk-full condition needs its own, separate remediation (freeing space, investigating why it filled) — entirely independent of the rescue-block fix, which only prevents this exact masking pattern from recurring in the future.

**Long-term prevention:** apply Category 1's "rescue completing = play reports success even if the underlying failure was serious" lesson rigorously to every existing rescue block in the codebase, auditing each for whether it correctly discriminates the specific failure it's designed for versus silently catching anything.

### Step-by-Step Implementation
```yaml
- block:
    - name: Install package
      ansible.builtin.package: { name: myapp, state: latest }
  rescue:
    - name: Check if failure was the expected "already at desired version" case
      ansible.builtin.fail:
        msg: "Unexpected failure during package install: {{ ansible_failed_result.msg }}"
      when: "'already installed' not in ansible_failed_result.msg | default('')"
      # Only continues gracefully for the SPECIFIC expected failure reason;
      # anything else re-raises as a loud, visible failure
```

### Under-the-Hood Explanation
A `rescue` block, by default, catches any failure from its corresponding `block` regardless of the failure's actual underlying cause — `ansible_failed_result` (or `ansible_failed_task`) provides access to the specific failure details, and only by explicitly checking this content within the rescue logic can a playbook distinguish "this is the specific, expected failure I'm designed to handle gracefully" from "this is some entirely different, potentially serious failure that happens to also trigger the rescue path."

### Common Weak Answer
"The rescue block is working as designed — it caught the error and let the play continue, which is exactly what rescue blocks do."

### Why the Weak Answer Fails
This describes rescue's mechanical behavior accurately but misses that the block was only ever *intended* to handle one specific, benign failure case — silently continuing past a genuinely serious, unrelated failure (disk-full) is not "working as designed" in any meaningful sense; it's masking a real problem the rescue block was never meant to hide.

### Follow-Up Questions
1. How would you audit every existing rescue block in a large playbook library for this same over-broad-catch risk?
2. What's the right balance between rescue-block specificity and the added complexity of explicit failure-reason checking?
3. How does this directly extend Category 1's Question 6 lesson to a more nuanced, "which specific failure am I actually rescuing" scenario?

### Key Interview Signals
Recognizes that an unscoped rescue block masks any failure, not just the specific one it was designed for, and adds explicit failure-reason discrimination so only the genuinely intended, benign case is gracefully handled while anything else fails loudly.

### Hands-On Connection
[Lab 6 — Error Handling and Safe Refactoring](../labs/lab-06-error-handling-and-refactoring/) and [Lab 14 — Troubleshooting and Recovery](../labs/lab-14-troubleshooting-and-recovery/).

---

## Question 94: The playbook that worked in staging and lied about production

### Scenario
A playbook change is thoroughly tested and validated in staging, then applied to production, where it fails immediately — staging and production inventories reference the same group names and variable structure, but staging's hosts happen to already have a prerequisite package installed (from an earlier, since-forgotten manual installation) that production hosts genuinely lack, and the playbook never explicitly manages that prerequisite.

### Interview Question
Diagnose this staging-production parity gap and design a prevention process.

### Strong Senior-Level Answer
**Initial assessment:** this is the same "test environment doesn't genuinely represent target reality" gap as the companion Category 9 Molecule-fidelity questions, here manifesting between staging and production environments specifically rather than a test container versus a real host — staging's hosts had accumulated a prerequisite via an untracked manual installation, and the playbook's success in staging was coincidentally dependent on that prerequisite's presence, never actually managed or verified by the playbook itself.

**Technical reasoning:** if the playbook assumes a prerequisite is present (without an explicit task installing/verifying it) purely because every test/staging host happens to already have it, that assumption is invisible and untested — it only surfaces when the assumption's coincidental truth breaks, exactly as happened when production (never having received the same untracked manual installation) lacked it.

**Investigation process:** identify the exact missing prerequisite production lacks, and confirm exactly how/when staging came to have it (very likely, an old, undocumented manual installation, similar in spirit to Category 8's untested-shared-template blast-radius theme, here at the environment-parity level).

**Recommended solution:** add an explicit task to the playbook installing/verifying the prerequisite (rather than assuming its presence), ensuring the playbook is now self-sufficient and doesn't depend on any environment's accumulated, untracked history; separately, audit staging for other similarly-accumulated, undocumented manual changes that might be creating other invisible parity gaps with production.

**Risk controls:** treat any staging-validated change as only as trustworthy as staging's actual fidelity to production — periodically audit staging/production parity (package lists, configuration drift) to catch and close this class of gap proactively, rather than discovering it via a failed production deployment.

**Validation steps:** after adding the explicit prerequisite-management task, confirm the playbook now succeeds against a genuinely fresh, prerequisite-lacking test host (not just staging's already-privileged environment), proving the fix addresses the root assumption rather than staging's specific, coincidental state.

**Rollback or recovery strategy:** for the immediate production failure, install the missing prerequisite manually (or via the now-corrected playbook) to unblock the deployment, then proceed with the corrected playbook going forward.

**Long-term prevention:** periodically audit staging-production environment parity explicitly (not just assume it holds), and design playbooks to be self-sufficient (managing every prerequisite they depend on explicitly) rather than assuming any environment's current, possibly-accumulated-and-undocumented state as a given — exactly the same test-environment-fidelity discipline established in Category 9's Molecule-scenario-representativeness questions, applied here at the staging-vs-production level.

### Step-by-Step Implementation
```yaml
- name: Ensure prerequisite package is present (explicit, not assumed)
  ansible.builtin.package:
    name: prerequisite-lib
    state: present
  # No longer silently depends on staging's coincidental, undocumented state
```

### Under-the-Hood Explanation
A playbook's actual, real dependencies are exactly what its own tasks explicitly manage — anything it implicitly assumes (without a corresponding task) is entirely dependent on whatever state the target host happens to already have, which can differ arbitrarily between environments unless every environment's provisioning process is genuinely identical and free of untracked manual drift, exactly the gap staging's old, forgotten manual installation created here.

### Common Weak Answer
"Staging passed cleanly, so the playbook itself must be correct — production must have a separate, unrelated issue."

### Why the Weak Answer Fails
This trusts staging's validation as complete proof of correctness without considering that staging's own environment might have accumulated undocumented state the playbook was implicitly, coincidentally depending on — exactly the gap that caused this specific production failure.

### Follow-Up Questions
1. How would you periodically audit staging-production parity to catch this class of gap before it causes a production failure?
2. How would you design a "fresh, minimal" test target (rather than staging's potentially-privileged, accumulated state) to validate a playbook's actual, complete self-sufficiency?
3. How does this connect to the companion Category 9 Molecule-fidelity discussion (Questions 80/84) about test environments not fully representing real target diversity?

### Key Interview Signals
Recognizes that staging's coincidental, undocumented state can mask an implicit playbook dependency, and fixes the playbook to be genuinely self-sufficient rather than trusting staging validation as complete proof of correctness.

### Hands-On Connection
[Lab 5 — Multi-Environment Architecture](../labs/lab-05-multi-environment/) and [Lab 14 — Troubleshooting and Recovery](../labs/lab-14-troubleshooting-and-recovery/).

---

## Question 95: The variable that was right in every file except the one that mattered

### Scenario
A playbook run against production applies an incorrect database connection string to several hosts. Investigation reveals the correct value exists in `group_vars/production.yml`, but a more specific `host_vars/db-prod-03.yml` file (created months ago for a since-resolved, one-off exception) still contains an old, stale value that takes precedence for that specific host.

### Interview Question
Diagnose this precedence-driven staleness and design a prevention process.

### Strong Senior-Level Answer
**Initial assessment:** per Category 2's variable-precedence guidance, `host_vars` correctly takes precedence over `group_vars` by design — the actual problem isn't a precedence malfunction, but that a host-specific override created for a legitimate, one-off, since-resolved exception was never removed once its original purpose ended, becoming stale, forgotten, and silently overriding the correct, more-current group-level value indefinitely.

**Technical reasoning:** `host_vars` overrides are exactly as "sticky" as any other configuration — Ansible has no mechanism prompting anyone to reconsider whether a specific override is still needed once its original justification has passed, meaning a temporary exception left in place becomes a permanent, silent landmine exactly as it did here.

**Investigation process:** review the specific `host_vars/db-prod-03.yml` file's git history/commit message for context on why it was originally created — confirming it was indeed meant as a temporary exception, and identifying whether any other hosts have similarly stale, forgotten host-level overrides.

**Recommended solution:** remove the stale host-level override (restoring this host to inheriting the correct, current group-level value), and audit the broader `host_vars` directory for other overrides that might similarly have outlived their original, legitimate purpose.

**Risk controls:** for the affected hosts, verify the corrected connection string is actually applied and functioning before considering the incident resolved.

**Validation steps:** after removing the stale override, confirm `db-prod-03` (and any other hosts audited) now correctly inherits the current group-level value, and confirm no functional regression from removing what was genuinely a stale, no-longer-needed exception.

**Rollback or recovery strategy:** if the host-level override turns out to still be needed for some undocumented, legitimate reason not initially apparent, restore it with an explicit, dated comment explaining why it remains necessary, rather than leaving its purpose ambiguous.

**Long-term prevention:** treat any host-level (or otherwise unusually-specific) variable override as requiring an explicit, dated justification comment and, ideally, a tracked follow-up/expiration reminder if it's genuinely meant to be temporary — exactly the same "temporary access grant needs an explicit tracked expiration" discipline established for IRSA/RBAC access-lifecycle management in the companion EKS repository, applied here to configuration overrides specifically.

### Step-by-Step Implementation
```bash
# Audit host_vars for potentially-stale, undocumented overrides
git log --follow -p host_vars/db-prod-03.yml   # review original context/justification

# If confirmed stale, remove it - host now correctly inherits group_vars
rm host_vars/db-prod-03.yml
```
```yaml
# If a host-level override IS still legitimately needed, document it explicitly
# host_vars/db-prod-04.yml
# NOTE: overrides group default due to legacy hardware constraint - see JIRA-5678
# Review by: 2026-12-31 - remove once hardware is decommissioned
db_connection_pool_size: 10
```

### Under-the-Hood Explanation
Ansible's variable precedence (per Category 2) correctly and consistently applies `host_vars` above `group_vars` — this is working exactly as designed; the actual failure is organizational/process (a temporary override left in place indefinitely, with no mechanism prompting reconsideration), not anything wrong with Ansible's precedence resolution itself.

### Common Weak Answer
"Ansible's variable precedence must have a bug applying the wrong value."

### Why the Weak Answer Fails
Precedence resolved exactly correctly according to its documented rules — `host_vars` legitimately overrides `group_vars`; the actual issue is that a stale, forgotten override existed at all, a process/hygiene gap, not a precedence-resolution defect.

### Follow-Up Questions
1. How would you audit an entire inventory for stale, potentially-forgotten host-level overrides at scale?
2. What tracking/expiration mechanism would you build for genuinely temporary configuration overrides?
3. How does this connect directly to Category 2's Question 12 (the role that couldn't be overridden) and the broader precedence-surprise theme?

### Key Interview Signals
Correctly identifies precedence as functioning exactly as designed, locating the actual problem in an undocumented, stale override left in place past its legitimate purpose, and designs a documentation/expiration-tracking process to prevent recurrence.

### Hands-On Connection
[Lab 14 — Troubleshooting and Recovery](../labs/lab-14-troubleshooting-and-recovery/).

---

## Question 96: The incident where everyone assumed someone else had checked

### Scenario
A multi-team incident response for a fleet-wide configuration issue involves three engineers, each independently assuming another has already verified whether the issue affects the disaster-recovery region's fleet as well. Two hours into the incident, it's discovered nobody actually checked — and the DR region has the identical issue, unaddressed the entire time.

### Interview Question
Diagnose this coordination failure and design a prevention process for future multi-team incidents.

### Strong Senior-Level Answer
**Initial assessment:** this is a incident-command/coordination gap, not a technical one — three engineers each assuming "someone else is handling the DR region" produced a diffusion-of-responsibility failure where a genuinely important verification step (does this affect DR too) fell through entirely, exactly the kind of gap a clear incident-command structure with explicit task ownership exists to prevent.

**Technical reasoning:** without an explicit incident commander assigning specific, named ownership for specific verification/remediation tasks, multiple engineers working the same incident can each reasonably (but incorrectly) assume another is covering a given area — there's no technical mechanism preventing this; it's purely a process/communication gap.

**Investigation process:** review the incident's actual communication trail (chat logs, if available) to understand exactly how this assumption formed and went unquestioned for two hours — informing what structural communication gap allowed it.

**Recommended solution:** for any multi-team incident, establish (or reinforce) a clear incident-command structure where one person is explicitly responsible for maintaining and communicating a task-ownership list — "who is checking what" — with explicit, named assignment for each verification/remediation area (including, in this case, "has anyone confirmed DR region status"), rather than relying on implicit, assumed coverage.

**Risk controls:** for any incident involving fleet-wide or multi-region infrastructure, make "check every region/environment explicitly" a standard, checklist-driven first step, removing the possibility of an assumed-but-unverified region being silently skipped.

**Validation steps:** after remediating the DR region's identical issue, conduct a postmortem specifically examining the coordination gap (not just the technical root cause), and confirm the incident-command/task-ownership process improvement is documented and would have caught this specific gap.

**Rollback or recovery strategy:** remediate the DR region's issue using the same fix already applied to the primary region, now that it's been identified.

**Long-term prevention:** institutionalize an explicit incident-command role with visible, tracked task-ownership for any incident spanning multiple regions/teams/systems — treating "everyone assumed someone else checked" as a preventable process gap, not a one-off communication mishap, and building a standard multi-region/multi-team incident checklist that explicitly enumerates every environment/region requiring verification.

### Step-by-Step Implementation
```text
Multi-team incident coordination checklist:
1. Designate an explicit incident commander for any incident spanning
   multiple teams/regions.
2. Maintain a visible, shared task-ownership list: "[Name] is verifying
   [specific system/region] - status: [in progress/complete]"
3. Explicitly enumerate every region/environment potentially affected
   (primary, DR, every environment) as separate, individually-owned
   checklist items - never assumed as "probably someone's covering it"
```

### Under-the-Hood Explanation
This is a human-coordination and incident-management-process issue, not a technical/tooling one — the underlying fix (explicit, visible task ownership under a clear incident-command structure) applies to any type of incident regardless of its specific technical cause, and is the standard remedy for diffusion-of-responsibility failures in any complex, multi-person response effort.

### Common Weak Answer
"This was just bad luck, nothing systematic to fix."

### Why the Weak Answer Fails
Diffusion of responsibility in multi-person incident response is a well-known, predictable, and preventable failure mode, not random bad luck — dismissing it as unlucky misses the genuine, actionable process improvement (explicit incident command and task ownership) that directly prevents recurrence.

### Follow-Up Questions
1. How would you structure the incident-commander role for a smaller team without a dedicated, formally-trained incident-response function?
2. What tooling (a shared incident-tracking channel/dashboard) would you use to maintain visible task ownership in real time during an active incident?
3. How does this connect to the companion EKS repository's Question 100 (the incident that was actually three incidents) — both cases of investigation/coordination process mattering as much as technical diagnosis?

### Key Interview Signals
Diagnoses a diffusion-of-responsibility coordination failure precisely and designs an explicit incident-command/task-ownership process fix, rather than dismissing the gap as unlucky or purely technical.

### Hands-On Connection
[Lab 14 — Troubleshooting and Recovery](../labs/lab-14-troubleshooting-and-recovery/) and [Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).

---

## Question 97: The postmortem that stopped at "fixed the typo"

### Scenario
Following Question 92's silently-skipped security-hardening task incident, the postmortem's root-cause section simply states "a typo in a variable name caused the task to be skipped; fixed the typo." No further analysis is included.

### Interview Question
Is this a sufficient postmortem? What's missing?

### Strong Senior-Level Answer
**Initial assessment:** stopping at "fixed the typo" addresses only the immediate, proximate cause — it misses the deeper, more valuable question of *why* a months-long, security-relevant silent failure was possible at all with no detection mechanism, and what systemic changes would prevent this entire *class* of issue (not just this one specific typo) from recurring.

**Technical reasoning:** a genuinely useful postmortem distinguishes the proximate cause (this specific typo) from the contributing systemic factors (no assert verifying the conditional's variable was defined and correct; no monitoring for "has this security-hardening task actually applied across the fleet recently"; no periodic compliance audit that would have caught the gap sooner than "discovered incidentally months later") — fixing only the proximate cause leaves every contributing factor unaddressed, meaning the next similar typo (in a different conditional) would produce the identical undetected-for-months failure pattern.

**Investigation process:** revisit the incident with the full 10-step Interview Response Framework's "preventive controls" step explicitly in mind — asking not just "what was the bug" but "what would need to be true for this entire class of bug to be caught quickly, not discovered incidentally months later."

**Recommended solution:** expand the postmortem to include: the specific assert-based fix (per Question 92) as a template pattern for other similarly-critical conditionals; a broader audit of the playbook library for other conditionals with the same undefined-variable-silent-skip risk; and a monitoring/compliance-check mechanism specifically verifying that security-hardening tasks have actually applied recently across the fleet, catching a future silent-skip incident within days rather than months.

**Risk controls:** ensure the expanded postmortem's action items are actually tracked and completed, not just documented — a thorough postmortem that identifies systemic fixes but never implements them provides no more real protection than the shallow version.

**Validation steps:** confirm the broader audit (for other silently-skipped conditionals) is actually completed, and confirm the new compliance-monitoring mechanism is operational and would have caught this exact incident within a reasonably short window.

**Rollback or recovery strategy:** not applicable — this is a postmortem-quality improvement.

**Long-term prevention:** establish a postmortem-quality standard requiring every incident write-up to explicitly distinguish proximate cause from contributing systemic factors, and requiring action items addressing the systemic factors (not just the proximate fix) — exactly the same "postmortem accuracy and depth deserves the same rigor as the original investigation" discipline established in the companion EKS repository's Question 103 (the postmortem that blamed the wrong layer).

### Step-by-Step Implementation
```text
Postmortem structure requiring both levels of analysis:
1. Proximate cause: typo in `when` condition variable name
2. Contributing systemic factors:
   - No assert verifying the conditional's variable correctness
   - No monitoring confirming security-hardening tasks actually apply fleet-wide
   - No periodic compliance audit catching this class of silent gap sooner
3. Action items addressing EACH systemic factor, not just the proximate fix
```

### Under-the-Hood Explanation
A postmortem's actual protective value comes from the systemic changes it produces, not the specific bug fix alone — the specific typo is already fixed and won't recur in that exact form, but the *conditions* that allowed a months-long, undetected, security-relevant silent failure (no assert discipline, no compliance monitoring) remain entirely unaddressed unless the postmortem explicitly surfaces and drives fixes for them.

### Common Weak Answer
"The typo is fixed, the immediate problem is resolved, the postmortem can be brief."

### Why the Weak Answer Fails
This conflates "the specific instance of the bug is fixed" with "the systemic conditions that allowed this class of bug to go undetected for months are addressed" — the former is necessary but nowhere near sufficient for genuine, durable prevention of similar future incidents.

### Follow-Up Questions
1. How would you structure a postmortem template ensuring every incident write-up addresses both proximate and systemic factors?
2. What specific compliance-monitoring mechanism would you build to catch a "security-hardening task hasn't actually run recently" gap proactively?
3. How does this connect directly to the companion EKS repository's postmortem-rigor guidance (Question 103)?

### Key Interview Signals
Distinguishes proximate cause from contributing systemic factors in postmortem analysis, and insists on action items addressing the systemic gaps (assert discipline, compliance monitoring) rather than considering the incident closed once the specific typo is fixed.

### Hands-On Connection
[Lab 14 — Troubleshooting and Recovery](../labs/lab-14-troubleshooting-and-recovery/).

---

## Question 98: The incident nobody could reproduce because nobody kept the evidence

### Scenario
An intermittent, hard-to-reproduce failure affecting roughly 2% of playbook runs against a specific host group has been occurring for weeks. Each time it happens, the on-call engineer re-runs the playbook (which succeeds on retry) and moves on, without capturing any diagnostic detail about the specific failure before retrying.

### Interview Question
Diagnose why this intermittent issue remains unsolved after weeks, and design a better response process.

### Strong Senior-Level Answer
**Initial assessment:** treating each occurrence as a one-off to retry-and-move-past, without capturing diagnostic evidence before retrying, means every single occurrence of this intermittent issue has been an opportunity to gather root-cause evidence that was discarded — after weeks, there's still no accumulated diagnostic data because retrying immediately overwrites/loses the exact failure state that would explain it.

**Technical reasoning:** an intermittent, ~2%-of-runs failure that succeeds on retry is a classic signature of a race condition, a transient network/resource issue, or a timing-sensitive dependency — but diagnosing *which* of these (and the specific mechanism) requires actually capturing the failure's specific error output, timing, and affected-host details at the moment it occurs, not after it's already been retried past.

**Investigation process:** establish that no diagnostic evidence currently exists from any of the weeks of prior occurrences (confirming the actual gap), and design a capture process for the *next* occurrence rather than trying to retroactively diagnose from nothing.

**Recommended solution:** for the next several occurrences, before retrying, capture full verbose output (`-vvv`), the specific failing task and error message, the specific host(s) affected, and the exact timestamp — cross-referencing this against any relevant infrastructure-level signal (network conditions, resource utilization on the affected host at that moment) to begin building an actual evidence base for root-cause diagnosis.

**Risk controls:** balance the operational cost of "don't just retry immediately, capture evidence first" against the urgency of restoring service — for a low-impact, retry-succeeds situation like this, the brief delay to capture diagnostics is a reasonable trade-off; for a genuinely urgent, service-impacting failure, prioritize restoration first but still capture whatever evidence is readily available without meaningfully delaying recovery.

**Validation steps:** after several occurrences with captured evidence, look for a common pattern (same specific task, same specific hosts, correlating timing with some other event) — this is the actual path to root-causing an intermittent issue, which pure retry-and-move-on can never provide.

**Rollback or recovery strategy:** not applicable — this is a diagnostic-process improvement.

**Long-term prevention:** establish "capture diagnostic evidence before retrying" as the standard operational response for any intermittent, retry-succeeds failure pattern — treating each occurrence as a genuine diagnostic opportunity rather than a nuisance to clear as quickly as possible, since without this discipline, an intermittent issue can persist indefinitely with literally zero progress toward root cause, exactly as happened here across several weeks.

### Step-by-Step Implementation
```bash
# Before retrying an intermittent failure - capture evidence FIRST
ansible-playbook site.yml -i inventory --limit affected-host -vvv 2>&1 | tee "incident-$(date +%s).log"
# THEN retry, but now with actual diagnostic evidence preserved for pattern analysis
ansible-playbook site.yml -i inventory --limit affected-host
```

### Under-the-Hood Explanation
An intermittent failure's root cause is only discoverable through accumulated evidence across multiple occurrences — race conditions, transient resource contention, and timing-sensitive dependencies rarely reveal themselves from a single data point, and immediately retrying without capturing the specific failure state (verbose output, exact error, precise timing) destroys the only opportunity to gather that occurrence's contribution to the evidence base, meaning a purely retry-and-move-on response can genuinely never converge on root cause no matter how many occurrences accumulate.

### Common Weak Answer
"Since retrying always fixes it, it's probably not worth investigating further."

### Why the Weak Answer Fails
"Retry always fixes it" is not evidence the issue is unimportant — it's evidence the issue is intermittent and race-condition-like, which is a genuine, real bug pattern deserving actual root-cause investigation, especially since an intermittent issue that "always resolves on retry" today could manifest as a genuinely unrecoverable failure under different, less-fortunate timing conditions in the future.

### Follow-Up Questions
1. How would you balance evidence-capture discipline against the urgency of restoring service for a more impactful, less benign intermittent failure?
2. What specific infrastructure-level signals (network, resource utilization) would you correlate against the captured playbook evidence?
3. How does this connect to the broader theme of "an intermittent, self-resolving issue still deserves genuine investigation" from other troubleshooting categories in this repository series?

### Key Interview Signals
Recognizes that retry-and-move-on discards the only real opportunity to gather root-cause evidence for an intermittent failure, and establishes a deliberate evidence-capture discipline as the actual path to eventually diagnosing and fixing the underlying issue.

### Hands-On Connection
[Lab 14 — Troubleshooting and Recovery](../labs/lab-14-troubleshooting-and-recovery/).
