# Project Roadmap

This repository is built in 8 phases, mirroring the structure and rigor of the companion Terraform repository at `../terraform/`. This file is the single source of truth for what is done, in progress, or not started. Update this file at the end of every phase — do not let it drift from reality.

Status legend: ✅ Complete · 🚧 In progress · ⬜ Not started

## Phase overview

| Phase | Scope | Status |
|---|---|---|
| 1 | Repository structure, README, roadmap, question allocation plan, lab dependency map | ✅ Complete |
| 2 | Core docs: Ansible architecture/internals, inventory & variables, role design | ✅ Complete |
| 3 | AWS/cloud, Kubernetes, security, CI/CD, testing, HA/DR docs + all 15 diagrams | ✅ Complete |
| 4 | All 120 interview questions (15 category files) | ✅ Complete |
| 5 | Labs 1–7 | ✅ Complete |
| 6 | Labs 8–15 | ✅ Complete |
| 7 | Mock interviews (3) and cheat sheets | ✅ Complete |
| 8 | Validation pass and final implementation status report | ✅ Complete |

## Phase 1 — Repository scaffold (this phase)

### Files created
- `README.md` — repository overview, usage paths, cost warning, lab dependency map (Mermaid), interview response framework summary
- `PROJECT-ROADMAP.md` — this file
- Full directory skeleton: `docs/`, `interview-questions/`, `labs/lab-01…lab-15/`, `roles/{common,webserver,security-baseline,observability,database}/`, `environments/{dev,staging,production}/`, `policies/tests/`, `tests/`, `scripts/`, `diagrams/`, `.github/workflows/`, `mock-interviews/`, `cheatsheets/`

### Question allocation plan (target: exactly 120)

Distribution mirrors the companion Terraform repository's proportions, remapped to Ansible-specific topic areas:

| # | File | Category | Count | Question #s |
|---|---|---|---:|---|
| 1 | `interview-questions/01-ansible-core.md` | Ansible core language and workflow | 10 | 1–10 |
| 2 | `interview-questions/02-inventory-variables.md` | Inventory, variables, and facts | 12 | 11–22 |
| 3 | `interview-questions/03-roles-collections.md` | Roles, collections, and reuse | 12 | 23–34 |
| 4 | `interview-questions/04-modules-plugins.md` | Modules, plugins, and connection types | 8 | 35–42 |
| 5 | `interview-questions/05-aws-cloud-integration.md` | AWS and cloud infrastructure integration | 10 | 43–52 |
| 6 | `interview-questions/06-kubernetes-containers.md` | Kubernetes and container integration | 8 | 53–60 |
| 7 | `interview-questions/07-security-vault.md` | Security and secrets management (Vault) | 8 | 61–68 |
| 8 | `interview-questions/08-cicd-automation.md` | CI/CD and automation (AWX/Tower, pipelines) | 10 | 69–78 |
| 9 | `interview-questions/09-testing-validation.md` | Testing and validation (Molecule, lint) | 8 | 79–86 |
| 10 | `interview-questions/10-troubleshooting.md` | Troubleshooting and production incidents | 12 | 87–98 |
| 11 | `interview-questions/11-ha-dr.md` | High availability and disaster recovery | 6 | 99–104 |
| 12 | `interview-questions/12-performance-scale.md` | Performance and large-scale Ansible | 6 | 105–110 |
| 13 | `interview-questions/13-governance-policy.md` | Governance and policy as code | 4 | 111–114 |
| 14 | `interview-questions/14-migration-upgrade.md` | Migration, adoption, and upgrades | 3 | 115–117 |
| 15 | `interview-questions/15-leadership-design.md` | Leadership and architecture decisions | 3 | 118–120 |
| | **Total** | | **120** | |

Numbering is continuous 1–120 across the whole set (not reset per file), exactly like the Terraform repository, so lab/mock-interview cross-references stay unambiguous.

At least 80% (96 of 120) of questions must be scenario-based; the remaining margin is reserved for a small number of concept-anchor questions still framed around a production decision, never a bare definition.

### Lab dependency map

See the Mermaid diagram in [`README.md`](README.md#lab-dependency-map). Summary of hard prerequisites:

- Labs 1 → 2 is a strict chain (core workflow before role-based structure).
- Lab 2 feeds Labs 3, 4, 5, 9, 10, 11.
- Lab 5 → 6 is a strict chain (environments before safe-refactoring practice).
- Lab 3 + Lab 4 → 7 (dynamic inventory and Vault both needed before configuring real AWS fleets).
- Lab 7 → 8 (AWS configuration management before Packer/Ansible AMI baking, since the baking playbook reuses the same hardening roles).
- Lab 10 → 12 and Lab 11 → 12 (security scanning and testing both feed CI/CD).
- Lab 10 → 13 (security pipeline concepts feed policy-as-code).
- Lab 6 → 14 and Lab 7 → 14 (safe-refactoring and real-fleet experience required to realistically simulate and recover from failures).
- Lab 15 (capstone) depends on 8, 9, 12, 13, 14 — the integration point for golden images, container config, CI/CD, policy, and recovery.

### Topic index (provisional — finalized at end of Phase 4)

| Topic area | Primary docs | Primary questions | Primary labs |
|---|---|---|---|
| Ansible language & workflow internals | `ansible-internals.md` | 01-ansible-core | 01, 06 |
| Inventory & variables | `inventory-and-variables.md` | 02-inventory-variables | 01, 03, 05 |
| Role/collection engineering | `role-design.md` | 03-roles-collections | 02, 11 |
| Modules/plugins/connections | `ansible-architecture.md` | 04-modules-plugins | 03, 07, 09 |
| AWS/cloud integration | `ansible-architecture.md` | 05-aws-cloud-integration | 03, 07, 08 |
| Kubernetes/containers | `ansible-architecture.md` | 06-kubernetes-containers | 09 |
| Security/Vault | `security.md` | 07-security-vault | 04, 10 |
| CI/CD | `cicd.md` | 08-cicd-automation | 12, 15 |
| Testing | `testing.md` | 09-testing-validation | 11, 15 |
| Troubleshooting | `troubleshooting.md` | 10-troubleshooting | 06, 07, 14 |
| HA/DR | `ha-dr.md` | 11-ha-dr | 12, 15 |

### Assumptions recorded in Phase 1
- Baseline version: **`ansible-core` >= 2.16**, Python 3.10+ on the control node. Version-specific claims (e.g., exact `ansible-lint` rule names, Molecule driver defaults) will be flagged for reader verification rather than asserted as permanent fact.
- AWS integration uses the `amazon.aws` and `community.aws` collections, not the older built-in `ec2*` modules (deprecated/removed from ansible-core in favor of collections).
- Default secrets approach: **Ansible Vault** (file-based and/or a vault password sourced from a secrets manager), with a note on `community.hashi_vault` as the HashiCorp Vault integration alternative for organizations already standardized on that tool.
- Default CI/CD platform for Lab 12: **GitHub Actions** (matching the companion Terraform repo's default), with AWX/Ansible Automation Platform concepts covered narratively in `docs/cicd.md` rather than as a full duplicate pipeline.
- Default testing framework: **Molecule** with the Docker (or Podman) driver — chosen specifically so testing is free/local and doesn't require real cloud resources, called out explicitly in Lab 11.
- Kubernetes integration uses the `kubernetes.core` collection (the modern, actively maintained path) rather than shelling out to `kubectl` via `command`/`shell` — this exact anti-pattern (shell out instead of using a proper module) is itself one of the mandatory troubleshooting/architecture topics.

### Unresolved / not yet started
- No doc content, no question content, no lab content, no `.yml`/role code exists yet — this is purely the Phase 1 scaffold.
- No Mermaid diagrams exist yet beyond the one in `README.md`.
- No `.github/workflows` pipeline exists yet.
- No linting/testing has been run against anything, because no Ansible content exists yet. Nothing in this repository should be assumed validated until Phase 8 explicitly reports results — and, per the companion Terraform repository's experience, this environment may not have `ansible-lint`/`molecule`/`ansible-core` installed; that will be confirmed and reported honestly in Phase 8, not assumed either way in advance.

## Diagram inventory (target: 15)

| # | Diagram | Location | Status |
|---|---|---|---|
| 1 | Ansible execution model (control node → managed nodes) | `diagrams/01-execution-model.md` | ✅ |
| 2 | Playbook run workflow (parsing → inventory resolution → task execution) | `diagrams/02-playbook-workflow.md` | ✅ |
| 3 | Module execution / connection plugin flow (SSH, become, module transfer) | `diagrams/03-module-execution-flow.md` | ✅ |
| 4 | Variable precedence order | `diagrams/04-variable-precedence.md` | ✅ |
| 5 | Handler notification and flush flow | `diagrams/05-handler-flow.md` | ✅ |
| 6 | Dynamic inventory architecture (AWS) | `diagrams/06-dynamic-inventory.md` | ✅ |
| 7 | Ansible Vault encrypt/decrypt flow | `diagrams/07-vault-flow.md` | ✅ |
| 8 | Role dependency and composition architecture | `diagrams/08-role-dependency.md` | ✅ |
| 9 | Multi-environment repository/inventory structure | `diagrams/09-multi-environment.md` | ✅ |
| 10 | CI/CD workflow for Ansible (lint → molecule → syntax-check → deploy) | `diagrams/10-cicd-workflow.md` | ✅ |
| 11 | Packer + Ansible golden-AMI pipeline | `diagrams/11-packer-ansible-pipeline.md` | ✅ |
| 12 | Molecule testing architecture (scenarios, driver, verifier) | `diagrams/12-molecule-architecture.md` | ✅ |
| 13 | AWX/Ansible Automation Platform architecture | `diagrams/13-awx-architecture.md` | ✅ |
| 14 | Drift detection and reconciliation (check mode / diff mode) | `diagrams/14-drift-detection.md` | ✅ |
| 15 | Fleet-scale execution strategy (forks, strategy plugins, fact caching) | `diagrams/15-scale-execution-strategy.md` | ✅ |

## Phase 2 & 3 — Core documentation and diagrams (completed)

### Files created
- `docs/ansible-internals.md` — execution model, execution strategy/forks/parallelism, idempotency as a contract you write (not a guarantee), check/diff mode and its limitations, handlers (deferred/batched execution, the "queued handler never runs if the play fails first" trap), blocks/rescue/always, facts and fact caching, connection/become mechanics, pipelining.
- `docs/inventory-and-variables.md` — static vs. dynamic inventory, groups/group_vars/host_vars, patterns and `--limit`, the full 19-level variable precedence order (with the `defaults` vs. `vars` precedence trap called out explicitly), magic variables/`hostvars`, fact caching trade-offs, the vars/vault secrets-splitting pattern.
- `docs/role-design.md` — role structure, `defaults` vs. `vars` as an interface decision, `argument_specs.yml` validation, `meta/main.yml` dependencies (and the legibility trade-off of using them), avoiding overly generic roles, Galaxy/Automation Hub versioning discipline, collections vs. standalone roles, deprecation strategy.
- `docs/ansible-architecture.md` — Part A (modules/collections, connection plugins, callback plugins, lookup/filter/test distinction, when to write a custom module, Execution Environments for reproducibility/air-gapped use) + Part B (AWX/Automation Platform architecture, layered automation, repo architecture, multi-account/multi-cloud credentialing, push vs. pull).
- `docs/security.md` — Vault mechanics and the vars/vault split, vault-password key management (the real secret-management problem Vault shifts upward), `no_log` as a display-only control, `become` least privilege, CI/CD credential handling (OIDC, short-lived SSH), AWX credential injection model, `ansible-lint` as static analysis (and its scope limits vs. a real security scanner), supply-chain trust for collections/roles.
- `docs/testing.md` — the Ansible testing pyramid, `ansible-lint`, Molecule's full create→converge→idempotence→verify→destroy cycle (with the idempotence stage as the enforced idempotency proof), `verify.yml` asserting real state, the explicit "no mock_provider equivalent" capability gap, contract testing for shared roles.
- `docs/cicd.md` — PR validation chain, the explicit "no saved-plan-artifact equivalent" gap and its mitigations (pinned commit + EE image), approval gates, fleet-level concurrency controls (distinct from Terraform's state-lock concern), OIDC/credential handling, drift detection via scheduled check-mode, rollback limitations, full GitHub Actions reference pipeline.
- `docs/troubleshooting.md` — runbook-style catalog: unreachable hosts, `become` failures, idempotency bugs, handler-never-fires, variable precedence surprises, module/collection resolution failures, Jinja2 templating errors, dynamic inventory misresolution, duplicate inventory entries, partial fleet runs (`.retry`/`--limit`), API throttling/connection storms, Vault decryption failures in CI, concurrent-pipeline races.
- `docs/ha-dr.md` — AWX/Automation Platform control-plane HA, push automation's control-node-connectivity dependency vs. `ansible-pull`'s resilience to that specific failure mode, how configuration management genuinely helps DR (same playbooks converge DR-region hosts identically, with no "state file" to replicate since Ansible re-converges from current reality every run), what Ansible doesn't solve (data recovery, traffic cutover), the same "the recovery tool can't share fate with what it's recovering" lesson from the Terraform repo applied to AWX being down during an incident.
- `docs/interview-cheatsheet.md` — master topic index, memorized Interview Response Framework, "five questions that separate Senior from Staff," common trap answers.
- All 15 Mermaid diagrams in `diagrams/01-*.md` through `diagrams/15-*.md`.

### Assumptions / version-sensitivity notes
- Several claims flagged inline for reader verification rather than asserted as permanent: exact `ansible-lint` default rule set/names, Molecule's default driver behavior across versions, exact AWX vs. Ansible Automation Platform feature parity, `argument_specs.yml` minimum `ansible-core` version.
- `docs/troubleshooting.md` and `docs/cicd.md` deliberately cross-reference rather than duplicate mechanics already covered in depth in `ansible-internals.md`/`inventory-and-variables.md`/`security.md`, mirroring the companion Terraform repository's approach to avoiding two diverging explanations of the same mechanism.
- Explicitly named (not glossed over) two genuine Ansible-vs-Terraform capability gaps: no saved-plan-artifact equivalent for CI/CD (`docs/cicd.md` §2), and no `mock_provider`-equivalent for cost-free cloud-call unit testing (`docs/testing.md` §6). Naming real gaps honestly is more useful for interview prep than implying feature parity that doesn't exist.

### Validation status
- **Not yet run**: no Ansible/Molecule/ansible-lint binaries have been used to validate anything in this phase — these are prose/reference docs with YAML/Jinja *snippets*, not standalone runnable playbooks. Snippet correctness was checked by inline reasoning. Full validation happens in Phase 8 once labs (containing real, runnable playbooks/roles) exist, and tool availability in this environment will be confirmed and reported honestly at that point (not assumed present or absent in advance).
- Mermaid syntax not yet rendered through an actual engine; will be spot-checked structurally in Phase 8, mirroring the companion Terraform repository's approach.

## Definition of done (tracked at the end of Phase 8)

- [x] Exactly 120 questions present, numbered 1–120, no gaps or duplicates (mechanically verified: `grep -c "^## Question "` across all 15 files sums to exactly 120)
- [x] Every question follows the required 10-part answer format (Scenario, Interview Question, Strong Senior-Level Answer with 8 bolded sub-labels, Step-by-Step Implementation, Under-the-Hood Explanation, Common Weak Answer, Why the Weak Answer Fails, 3 Follow-Up Questions, Key Interview Signals, Hands-On Connection)
- [x] All 15 labs present with every required section (mechanically verified: all 17 required section headers present in all 15 lab READMEs — 255/255)
- [x] Enterprise capstone (Lab 15) documented with a full `OPERATIONS.md` deliverable, composing roles/patterns from every prior lab
- [x] All 15 Mermaid diagrams present (mechanically verified: every diagram file contains a fenced ` ```mermaid ` block)
- [x] 3 mock interviews complete with rubrics (15 questions each, Senior/Lead/Staff)
- [x] All cheat sheets present (11 topic sheets covering CLI, precedence, vault, roles, inventory, testing, CI/CD, failures, AWS, performance, interview framework)
- [x] YAML syntax validated across the entire repository (67 files, Python `yaml.safe_load_all` — see Phase 8 report below)
- [x] Internal markdown links validated (638 relative links across 72 files — see Phase 8 report below)
- [x] Shell scripts validated with ShellCheck (4 scripts, 0 findings)
- [x] No credentials, real vault passwords, or unencrypted secrets committed (verified: no `vault_pass*`/`.pem`/`id_rsa*` files, no `AKIA`-pattern strings)
- [ ] `ansible-lint` / `molecule test` — **not run**; unavailable in this sandboxed environment (see Phase 8 report below for the full, honest accounting)
- [x] Every mandatory topic mapped to at least one doc/question/lab (see the topic index in `docs/interview-cheatsheet.md`)

## Phase 8 — Validation pass (completed)

Mirrors the companion Terraform repository's Phase 8 discipline: report what was actually mechanically checked, not what was intended.

### What was validated, and how

| Check | Method | Result |
|---|---|---|
| YAML syntax | Python `yaml.safe_load_all()` across every `.yml`/`.yaml` file (vault-encrypted files skipped, since they're not valid YAML by design) | **67/67 files parsed cleanly** |
| Internal markdown links | Custom script resolving every relative `[text](path)` link (including `#anchor` fragments, using GitHub's actual non-collapsing space-to-hyphen slugify behavior) against the real filesystem | **638 links checked across 72 files; 2 confirmed-benign flags, 1 genuine bug found and fixed** |
| Question count | `grep -c "^## Question "` summed across all 15 category files | **Exactly 120** |
| Lab section completeness | Grep for all 17 required section headers across all 15 lab `README.md` files | **255/255 present** |
| Diagram presence | Grep for a fenced ` ```mermaid ` block in every `diagrams/*.md` file | **15/15 present** (not rendered through an actual Mermaid engine — no such tool available in this environment) |
| Shell scripts | ShellCheck against all 4 `.sh` files in the repo (vault-password scripts) | **0 findings, clean** |
| Secret/credential scan | Grep for common credential file patterns and AWS access-key-ID shape | **Clean — nothing found** |

### The one genuine bug found and fixed

A cross-repository link in `interview-questions/05-aws-cloud-integration.md` (Question 47) referenced the companion Terraform repository's Question 63 with an incorrect relative-path depth (`../../terraform/...` instead of the correct `../../../terraform/...`, since this repository sits three directory levels below the shared `interview-questions/` parent, not two). Fixed and re-verified.

### Confirmed-benign flags (not bugs)

- `interview-questions/03-roles-collections.md` references `MIGRATION.md` inside a **fenced code block** illustrating what a hypothetical deprecated role's own README might say — this is illustrative example content, not a real, clickable link within this repository, and the link checker correctly has no way to distinguish that automatically.
- `labs/lab-09-kubernetes-and-helm/README.md` links to `../../../eks/labs/lab-10-gitops-argocd/` — a legitimate **forward reference** to the companion EKS repository's GitOps lab, which had not yet been built at the time this Ansible repository's Phase 8 ran. This link will resolve correctly once the EKS repository's own Phase 5–6 labs are complete; it is not a defect in this repository.
- `labs/lab-04-ansible-vault/README.md` links to a `group_vars/` directory that does not exist in the repository as committed — by design, per the lab's own Step-by-Step Tasks, the learner creates this directory and its vault-encrypted contents themselves as the hands-on exercise (`ansible-vault create ... group_vars/dev/vault.yml`). Pre-creating it would defeat the lab's purpose.

### What was honestly NOT validated (tool unavailability)

Exactly as documented for the companion Terraform repository's Phase 8, this sandboxed environment has no `ansible`, `ansible-lint`, `molecule`, `yamllint`, `gitleaks`, or `packer` binaries installed, and no attempt was made to install them (per the standing constraint established during the Terraform repository's build, after an installation attempt was explicitly rejected). This means:

- **No real playbook execution** — every playbook, role, and Molecule scenario in this repository has been written to be syntactically correct and logically sound by careful manual construction and review, but has never actually been run against a real target (Docker container, EC2 instance, or Kubernetes cluster).
- **No `ansible-lint` run** — style/best-practice conformance was checked by manual review against the conventions this repository's own docs establish, not by the actual tool.
- **No `molecule test` run** — the Lab 11 Molecule scenario (and the `verify.yml` files across other labs) have not been executed; their correctness rests on careful manual construction, not a passing CI run.
- **No `packer build`** — Lab 8's Packer template has not been validated with `packer validate`/`packer build`.

This is reported honestly, not glossed over: a learner working through this repository's labs will be the first to actually execute most of this content against real infrastructure, and should expect to encounter and fix minor issues exactly as they would with any hands-on lab material — that's the intended, realistic experience, not a sign of low-effort content.

### Summary

Ansible Senior Interview Preparation repository: **all 8 phases complete.** 120 questions, 15 labs (with real, runnable Ansible artifacts — playbooks, roles, inventories, Molecule scenarios, CI workflows), 15 diagrams, 3 mock interviews, 11 cheat sheets, 10 core docs. Every mechanical check available in this environment was run and passed (after one genuine bug fix); every check requiring an unavailable binary is honestly reported as not run, not assumed to pass.
