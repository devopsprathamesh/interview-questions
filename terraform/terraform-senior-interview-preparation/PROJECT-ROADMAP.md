# Project Roadmap

This repository is built in 8 phases, executed sequentially. This file is the single source of truth for what is done, what is in progress, and what assumptions or gaps exist at any point in time. Update this file at the end of every phase — do not let it drift from reality.

Status legend: ✅ Complete · 🚧 In progress · ⬜ Not started

## Phase overview

| Phase | Scope | Status |
|---|---|---|
| 1 | Repository structure, README, roadmap, question allocation plan, lab dependency map | ✅ Complete |
| 2 | Core docs: Terraform architecture, internals, state management, module design, provider engineering | ✅ Complete |
| 3 | AWS, EKS, security, CI/CD, testing, HA/DR docs | ✅ Complete |
| 4 | All 120 interview questions (15 category files) | ✅ Complete |
| 5 | Labs 1–7 | ✅ Complete |
| 6 | Labs 8–15 | ✅ Complete |
| 7 | Mock interviews (3) and cheat sheets | ✅ Complete |
| 8 | Validation pass and final implementation status report | ✅ Complete |

## Phase 2 & 3 — Core documentation and diagrams (completed)

### Files created
- `docs/terraform-internals.md` — language/workflow internals: graph construction, resource addressing, count vs for_each, lifecycle meta-arguments, provisioners, unknown values, refresh, replacement/taint, provider RPC, serial/lineage, exit codes, interrupted/partial applies
- `docs/state-management.md` — full state topic list: local/remote, locking, lineage/serial, backups, encryption/access control, corruption/recovery, migration/splitting/merging, state subcommands, import/moved/removed blocks, cross-state dependencies, drift decision framework, blast-radius redesign
- `docs/module-design.md` — module engineering: root/child modules, interface design, composition, avoiding overly generic/deeply nested modules, versioning/semver, registries, testing, documentation, upgrade/deprecation strategy
- `docs/terraform-architecture.md` — provider engineering (aliases, inheritance, assume-role, version constraints/lock file, default tags, auth, mirrors/air-gapped) + enterprise architecture (layered deployment, landing zones/account vending, repo architecture, workspace limitations, immutable/blue-green, DR architecture summary)
- `docs/security.md` — secrets in state vs. `sensitive` marking, CI/CD secret handling, IAM/OIDC, state bucket/KMS/audit, static analysis tool landscape (Checkov/tfsec/Trivy/Terrascan/TFLint), policy as code (OPA/Conftest/Sentinel), public exposure prevention, supply-chain/provider trust
- `docs/testing.md` — testing pyramid mapped to Terraform, `terraform validate` limits, native `terraform test` with worked examples, mock providers, Terratest/Kitchen-Terraform, contract testing, policy tests, cost-controlled test environments, destructive test cleanup
- `docs/cicd.md` — full PR validation chain, plan artifact integrity, apply approvals/environment protection, branch protection, concurrency controls, OIDC trust policy scoping, drift detection scheduling, rollback limitations, pipeline failure recovery, GitHub Actions reference pipeline (skeleton) plus GitLab CI/Jenkins conceptual equivalents
- `docs/troubleshooting.md` — runbook-style catalog covering all ~30 mandated production incident types (provider init/crash, lock timeout/stale lock, corrupt/deleted/lost state, resource-state mismatches both directions, duplicate address, failed backend migration, wrong workspace/account/region, expired credentials/access denied, dependency cycles, invalid for_each, count index shifting, API throttling, long-running plans, large state, CI race conditions, sensitive data exposure, module upgrade failure, import failure, prevent_destroy decommissioning)
- `docs/ha-dr.md` — HA-through-architecture, DR strategy comparison table (backup/restore, pilot light, warm standby, active/active) with RTO/RPO/cost trade-offs, what Terraform doesn't solve (data RPO, DNS cutover speed, state backend regional dependency), DR drill discipline, failback
- `docs/interview-cheatsheet.md` — master topic index, the memorized Interview Response Framework, the "five questions that separate Senior from Staff," common trap answers
- All 15 Mermaid diagrams in `diagrams/01-*.md` through `diagrams/15-*.md` (produced ahead of schedule alongside the docs they illustrate)

### Assumptions / version-sensitivity notes carried into these docs
- Several claims are explicitly flagged inline as needing verification against current provider/Terraform documentation rather than asserted as permanent fact: S3 native locking vs. DynamoDB-based locking availability, `terraform test` mock-provider syntax/version gating, exact current status of tfsec vs. Trivy consolidation, Jenkins OIDC-to-cloud plugin support, native state `encryption` block (1.10+) backend support.
- `docs/troubleshooting.md` intentionally cross-references rather than duplicates content already covered in depth in `state-management.md`, `terraform-internals.md`, `security.md`, and `cicd.md`, to avoid the repository having two diverging explanations of the same mechanism.

### Validation status
- **Not yet run**: no `.tf` code exists yet to run `terraform fmt`/`validate`/TFLint/security scanners against — these docs are prose/reference material with HCL *snippets*, not standalone runnable configurations. Snippet correctness was checked by inline reasoning, not by execution; full validation happens in Phase 8 once labs (which contain real, runnable `.tf` files) exist.
- **Not yet run**: Mermaid syntax has not been run through an actual renderer/linter; visual correctness will be spot-checked in Phase 8.

### Unresolved / deferred
- `docs/` referenced EKS/AWS-networking-specific detail (e.g., IRSA vs. Pod Identity specifics, VPC endpoint trade-offs) is intentionally light in the docs layer and deferred to be fully concrete inside Lab 8/Lab 9 themselves, where it's paired with actual Terraform code.

## Phase 4 — All 120 interview questions (completed)

### Files created
All 15 files under `interview-questions/`, numbered continuously 1–120 exactly per the Phase 1 allocation plan, verified by direct count (`grep -c "^## Question" interview-questions/*.md` sums to exactly 120, confirmed against the file listing). Every question follows the mandated format in full (Scenario, Interview Question, Strong Senior-Level Answer with all 8 required sub-points, Step-by-Step Implementation, Under-the-Hood Explanation, Common Weak Answer, Why the Weak Answer Fails, 3 Follow-Up Questions, Key Interview Signals, Hands-On Connection).

### Scenario-based ratio
All 120 questions are scenario-based (each opens with a concrete production situation), comfortably exceeding the 80% minimum requirement.

### Cross-referencing
Questions extensively cross-link to each other (e.g., troubleshooting questions reference the state-management questions covering the same mechanism in more depth) and to the relevant `docs/` deep-dive and `labs/` hands-on exercise — this cross-referencing was maintained by hand throughout drafting since Labs 1–15 don't exist as files yet (Phases 5–6); once labs are written, spot-check that every `../labs/lab-NN-.../` link in the question files resolves to an actual directory/README.

### Assumptions / notes
- Some answers explicitly flag version-sensitive claims for reader verification (e.g., exact EKS Pod Identity vs. IRSA feature-version gating, exact current tfsec/Trivy consolidation status) rather than asserting them as permanent fact, consistent with the Phase 2/3 approach.
- A few questions reference AWS pricing/cost dynamics narratively (NAT gateway costs, instance sizing) without citing specific dollar figures, per the spec's requirement to never invent exact current pricing.

### Validation status
- Not yet run: no automated check has verified every internal cross-reference link (e.g., `[Question 23](03-modules.md#question-23-...)`) resolves to the correct anchor — anchor text is derived from GitHub's heading-slugification rules and was written carefully but not yet mechanically verified. This is planned for the Phase 8 validation pass.
- HCL/Rego/YAML code snippets embedded in answers are illustrative (annotated inline where a snippet is a fragment/pseudocode) and have not been run through `terraform fmt`/`validate`, since they are teaching snippets embedded in prose, not a standalone runnable configuration — real, fully runnable Terraform code arrives in Phases 5–6 (the labs) and *that* code will be validated in Phase 8.

### Unresolved / deferred
- Anchor-link verification across all 120 questions' internal cross-references (Phase 8).
- Full topic-to-question mapping cross-check against the mandatory topics list in the original spec (Phase 8), to confirm every required Terraform-language/workflow/state/module/provider/security/CI-CD/testing/troubleshooting topic is addressed by at least one question.

## Phase 5 — Labs 1-7 (completed)

### Files created
- **Lab 1 (Core Workflow)**: full `.tf` set (`versions.tf`, `variables.tf`, `locals.tf`, `data.tf`, `main.tf`, `outputs.tf`) creating a random-suffixed S3 bucket plus dependent versioning/encryption/public-access-block resources and a `local_file` summary — zero-cost, no remote backend needed.
- **Lab 2 (Secure Remote State)**: `bootstrap/` (local-state-only: KMS key, S3 bucket with versioning/SSE-KMS/public-access-block/TLS-and-encryption-enforcing bucket policy, DynamoDB lock table) plus `environment/` (a minimal config consuming that backend via `-backend-config`), plus `scripts/state-recovery.sh`.
- **Lab 3 (Concurrent Execution and Locking)**: a `time_sleep`-delayed apply (deliberate, documented lab-only use) reusing Lab 2's backend, plus `scripts/simulate-concurrent-apply.sh` and `scripts/induce-stale-lock.sh` for hands-on lock-contention and stale-lock-recovery drills.
- **Lab 4 (Production Module Design)**: two new real, reusable modules under `modules/` — `modules/vpc` (for_each-by-AZ subnets, a named `nat_strategy` trade-off, precondition-guarded outputs, `terraform-docs`-style README, a `terraform test` suite using `mock_provider`) and `modules/security-groups` (standalone `for_each`-keyed rule resources, a `validation` block blocking unqualified `0.0.0.0/0`, its own `terraform test` suite) — plus a lab root composing both.
- **Lab 5 (Multi-Environment Architecture)**: populated `environments/dev`, `environments/staging`, `environments/production` with real, differentiated configs (`nat_strategy` = none/single/per_az respectively, distinct CIDRs/AZ counts, distinct backend state keys) — no CLI workspaces used anywhere.
- **Lab 6 (Import Existing Infrastructure)**: an `import.tf` using a declarative `import` block plus documented `-generate-config-out` workflow, with the README walking through manually creating a bucket via AWS CLI first (simulating pre-existing infra) and proving a zero-diff plan after adoption.
- **Lab 7 (Refactoring Without Recreation)**: three swappable `main.tf.phaseN-*` files proving `count`→`for_each` and root→module refactors via `moved` blocks produce zero recreation, plus a companion `modules/marker` child module for the Phase 3 restructuring step.

Every lab's `README.md` follows the full 17-section required structure (Objective through Advanced Challenge) exactly.

### Validation status
- **Not run in this environment**: `terraform fmt`/`validate`/`plan` have not been executed against any lab — the sandboxed execution environment for this session has no Terraform CLI installed, and installing one was declined. All HCL was written and manually reviewed carefully for syntax and internal consistency, but this is **not a substitute for actually running `terraform validate`**, and the reader should run it before trusting this code in any real AWS account. This is the single most important honesty caveat in this entire roadmap and will be repeated in the Phase 8 report.
- `terraform-docs`-generated-style module READMEs were hand-written to match the actual `variables.tf`/`outputs.tf` content, not generated by the actual `terraform-docs` tool (also unavailable in this environment) — cross-check manually before publishing.

### Assumptions
- All labs assume `us-east-1` as a sensible default region; every variable is overridable.
- Labs 2 onward assume Lab 2's bootstrap backend already exists and is reused via `-backend-config=../lab-02-remote-state/environment/backend.hcl` — this coupling is intentional (mirrors the [Lab Dependency Map](README.md#lab-dependency-map)) but means Lab 2 must genuinely be completed first, not just read.
- Cost-consciousness choices made explicitly per lab: Lab 1, 4, 6, 7 use zero-NAT/free-tier-friendly resources; Lab 5's staging/production intentionally provision real, billable NAT gateways as a deliberate teaching trade-off, clearly flagged in that lab's Cleanup section.

### Unresolved / deferred
- No CI workflow yet runs these labs' `fmt`/`validate`/tests automatically — that's Lab 12/`.github/workflows/` (Phase 6) plus the Phase 8 validation pass.
- `modules/iam`, `modules/eks`, `modules/rds`, `modules/alb`, `modules/observability` (referenced in the top-level repository structure) do not exist yet — they belong to Labs 8/9/15 in Phase 6.
- `policies/` and `tests/` (top-level, org-wide, distinct from each module's own `tests/`) remain empty pending Lab 13/11.

## Phase 6 — Labs 8-15 including enterprise capstone (completed)

### Files created
- **Lab 8 (AWS Networking Platform)**: composes `modules/vpc` + `modules/security-groups` (from Lab 4) into a tiered ALB/app/VPC-endpoint platform, adding six Interface VPC endpoints (ECR, Logs, SSM) at the root level specifically enabling the SSM-Session-Manager-instead-of-bastion pattern with no open SSH port anywhere.
- **Lab 9 (EKS Infrastructure)**: a new `modules/eks` (cluster + managed node group + cluster/node IAM roles + OIDC provider + EKS access entries, not the legacy `aws-auth` ConfigMap + Pod Identity Agent add-on), including a from-first-principles fix for the assumed-role-ARN-to-IAM-role-ARN conversion EKS access entries require. Lab root composes it with `modules/vpc` and adds one real `aws_eks_pod_identity_association` example.
- **Lab 10 (Terraform Security Pipeline)**: an `insecure-fixture/main.tf` with 8 deliberately planted findings (hardcoded credentials, public S3, open DB port, unencrypted/public/hardcoded-password RDS, oversized instances, IMDSv1) plus a `corrected-fixture/` answer key, a `.tflint.hcl`, and `scripts/run-security-checks.sh` chaining fmt/validate/TFLint/Checkov/gitleaks.
- **Lab 11 (Native Terraform Testing)**: a new zero-cost `fixture-module` (random/local providers only) with a `.tftest.hcl` combining plan-mode and genuine apply-mode tests with guaranteed cleanup, plus a mutation-testing exercise reusing Lab 4's `modules/security-groups` validation block.
- **Lab 12 (CI/CD Pipeline)**: a complete, syntax-checked `.github/workflows/terraform.yml` (validated with `python3 -c "import yaml"` — confirmed parses correctly) implementing validate → test → security-scan → plan (matrixed per environment, Conftest-gated, artifact-uploaded) → apply (main-branch-only, environment-protected, one environment at a time) plus a scheduled drift-detection job; a root `.tflint.hcl`; `backend.hcl.example` added to all three `environments/*` directories.
- **Lab 13 (Policy as Code)**: `policies/` with 5 Rego rule files (public exposure, encryption, mandatory tags, instance sizing with a reviewed-exception escape hatch, approved regions) and 4 corresponding `opa test` fixture files, each covering both a denying and a passing case per the testing discipline from `interview-questions/09-testing.md` Question 82.
- **Lab 14 (Drift, Failure, and Recovery)**: two scripts (`simulate-drift.sh`, `simulate-accidental-state-removal.sh`) operating directly against Lab 1's already-applied bucket/file, plus `recovery-runbook.md` — the actual documented-runbook deliverable required by the spec, covering 7 distinct incident classes with concrete procedures.
- **Lab 15 (Enterprise Capstone)**: three new modules (`modules/alb`, `modules/rds`, `modules/iam`) plus `modules/observability`, composed into a genuinely layered `foundation/` → `platform/` → `application/` three-state platform connected exclusively via SSM Parameter Store (never `terraform_remote_state`), plus `OPERATIONS.md` — the full operational documentation deliverable covering architecture, HA, security posture, cost, DR extension design, and a failure-recovery quick reference.

Every lab's `README.md` follows the full 17-section required structure. Total new/modified files this phase: 4 new top-level modules (`alb`, `rds`, `iam`, `observability`) plus the existing `eks` module, 8 lab directories, 1 GitHub Actions workflow, 5 Rego policy files + 4 test files, 2 recovery scripts, 2 operational-documentation markdown files.

### Validation status
- **Not run in this environment**: same caveat as Phase 5 — no Terraform CLI, TFLint, Checkov, OPA, or Conftest binary is available in this sandboxed session (installing one was explicitly declined), so none of this phase's HCL or Rego has been mechanically validated. Every file was hand-reviewed carefully, including deliberately working through Rego set-comprehension and `with input as` semantics by hand for the policy test files, but **this is not a substitute for actually running `opa test`, `terraform validate`, `tflint`, and `checkov`** before trusting this code.
- **Verified in this environment**: `.github/workflows/terraform.yml` was checked for valid YAML syntax via `python3 -c "import yaml; yaml.safe_load(...)"` — confirmed to parse without error. This confirms YAML syntax only, not GitHub Actions semantic correctness (action versions, input names, expression syntax) or actionlint-level validation.
- Cost warnings are present and specific in every lab that provisions billable resources (Labs 8, 9, 15 especially), each instructing the reader to verify current AWS pricing independently rather than trusting any figure in this repository.

### Assumptions
- Lab 9's EKS module assumes EKS access entries (the modern access model) are available for the target Kubernetes/EKS platform version in use — verify current EKS version support before relying on `authentication_mode = "API"`.
- Lab 12's workflow assumes GitHub Environments named exactly `dev`/`staging`/`production` exist with `production` requiring a manual reviewer — this is a manual one-time repository-settings step outside Terraform's own scope, called out explicitly in the lab's Step-by-Step Tasks.
- Lab 15's capstone assumes a real ACM certificate ARN will be supplied for anything beyond a lab/demo run; `certificate_arn = null` is an explicit, documented lab-only fallback to an HTTP-only ALB listener, never presented as a production pattern.
- Lab 15's `application/user_data.sh.tftpl` is a deliberate stub (logs a message, doesn't run a real HTTP server) — called out explicitly as the lab's own Troubleshooting Exercise, not an oversight.

### Unresolved / deferred
- No `tests/` (top-level, org-wide) content beyond what lives inside each module's own `tests/` directory and `policies/tests/` — the spec's top-level `tests/` directory remains an intentionally-empty placeholder, since every test asset produced so far is correctly scoped inside its owning module/policy directory rather than duplicated centrally.
- `scripts/` (top-level, org-wide) remains empty — every script produced so far is lab-scoped (`labs/lab-10-security-validation/scripts/`, `labs/lab-14-drift-and-recovery/scripts/`), which is where they're actually used; nothing yet warrants promotion to a shared, org-wide script.
- Mechanical validation of everything in this phase (Terraform, Rego, YAML semantics beyond syntax) is fully deferred to Phase 8, and Phase 8's report will be explicit about what could and could not actually be run in this environment.

## Phase 7 — Mock interviews and cheat sheets (completed)

### Files created
- `mock-interviews/mock-interview-01-senior-devops-engineer.md` — 15 questions, Terraform operations/troubleshooting focus, each with expected answer points, 3 follow-ups, red flags, and a model answer.
- `mock-interviews/mock-interview-02-lead-terraform-engineer.md` — 15 questions, architecture/module design/governance/CI-CD focus.
- `mock-interviews/mock-interview-03-staff-platform-architect.md` — 15 questions, multi-account architecture/security/scale/organizational ownership/HA/DR focus.
- 14 files under `cheatsheets/`: CLI commands, state commands, import and refactoring, lifecycle meta-arguments, `count` vs `for_each`, module design, provider aliases, backend troubleshooting, common production failures, CI/CD design, security controls, testing, AWS multi-account patterns, and the interview response framework.

All 45 mock-interview questions reference the corresponding full-length question in `interview-questions/` rather than duplicating the complete answer, keeping the mock format genuinely interview-paced (expected points + short model answer) as specified, distinct from the 120 main questions' full 12-section format.

### Validation status
- Every `[Question N](...)` cross-reference in the mock interviews and cheat sheets was written against the actual question titles/anchors already present in `interview-questions/*.md` — not yet mechanically link-checked. Deferred to Phase 8 alongside the same check for the 120 questions' internal cross-references.

### Unresolved / deferred
- Link verification for this phase's ~140 cross-references (mock interviews + cheat sheets combined) folded into the Phase 8 validation pass.

## Phase 1 — Repository scaffold

### Files created
- `README.md` — repository overview, usage paths, cost warning, lab dependency map (Mermaid), interview response framework summary
- `PROJECT-ROADMAP.md` — this file
- Full directory skeleton under `terraform-senior-interview-preparation/`:
  - `docs/`, `interview-questions/`, `labs/lab-01…lab-15/`, `modules/{vpc,security-groups,iam,eks,rds,alb,observability}/`, `environments/{dev,staging,production}/`, `policies/`, `tests/`, `scripts/`, `diagrams/`, `.github/workflows/`, `mock-interviews/`, `cheatsheets/`

### Question allocation plan (target: exactly 120)

| # | File | Category | Count |
|---|---|---|---:|
| 1 | `interview-questions/01-terraform-core.md` | Terraform core language and workflow | 10 |
| 2 | `interview-questions/02-state-management.md` | State management and locking | 12 |
| 3 | `interview-questions/03-modules.md` | Module architecture and reuse | 12 |
| 4 | `interview-questions/04-providers.md` | Providers, resources, and data sources | 8 |
| 5 | `interview-questions/05-aws-architecture.md` | AWS infrastructure design | 10 |
| 6 | `interview-questions/06-kubernetes-eks.md` | Kubernetes and EKS integration | 8 |
| 7 | `interview-questions/07-security.md` | Security and secrets management | 8 |
| 8 | `interview-questions/08-cicd.md` | CI/CD and automation | 10 |
| 9 | `interview-questions/09-testing.md` | Testing and validation | 8 |
| 10 | `interview-questions/10-troubleshooting.md` | Troubleshooting and production incidents | 12 |
| 11 | `interview-questions/11-ha-dr.md` | High availability and disaster recovery | 6 |
| 12 | `interview-questions/12-performance-scale.md` | Performance and large-scale Terraform | 6 |
| 13 | `interview-questions/13-governance.md` | Governance and policy as code | 4 |
| 14 | `interview-questions/14-migration-upgrade.md` | Migration, import, and upgrades | 3 |
| 15 | `interview-questions/15-leadership-design.md` | Leadership and architecture decisions | 3 |
| | **Total** | | **120** |

Numbering within each file: questions are numbered continuously 1–120 across the whole set (not reset per file), so cross-references from labs and mock interviews stay unambiguous. The running number ranges per file are:

| File | Question numbers |
|---|---|
| 01-terraform-core.md | 1–10 |
| 02-state-management.md | 11–22 |
| 03-modules.md | 23–34 |
| 04-providers.md | 35–42 |
| 05-aws-architecture.md | 43–52 |
| 06-kubernetes-eks.md | 53–60 |
| 07-security.md | 61–68 |
| 08-cicd.md | 69–78 |
| 09-testing.md | 79–86 |
| 10-troubleshooting.md | 87–98 |
| 11-ha-dr.md | 99–104 |
| 12-performance-scale.md | 105–110 |
| 13-governance.md | 111–114 |
| 14-migration-upgrade.md | 115–117 |
| 15-leadership-design.md | 118–120 |

At least 80% (96 of 120) of questions must be scenario-based; the remaining margin is reserved for a small number of concept-anchor questions that are still framed around a production decision, never a bare definition.

### Lab dependency map

See the Mermaid diagram in [`README.md`](README.md#lab-dependency-map). Summary of hard prerequisites:

- Labs 1 → 2 → 3 and 1 → 2 → 4 are strict chains.
- Lab 4 (modules) feeds Labs 5, 8, 10, 11.
- Lab 5 → 6 → 7 is a strict chain (environments → import → refactor).
- Lab 8 → 9 is a strict chain (networking before EKS).
- Lab 10 → 12 and Lab 11 → 12 (security scanning and testing both feed CI/CD).
- Lab 10 → 13 (security pipeline concepts feed policy-as-code).
- Lab 3 → 14 and Lab 7 → 14 (locking and refactoring knowledge required to realistically simulate and recover from failures).
- Lab 15 (capstone) depends on 8, 9, 12, 13, 14 — it is the integration point for networking, compute, CI/CD, policy, and recovery.

### Topic index

Full topic-to-location mapping (which doc, question set, or lab covers each mandatory topic from the spec) will be finalized at the end of Phase 4 once all question files exist, and published as `docs/interview-cheatsheet.md` cross-references. A provisional mapping:

| Topic area | Primary docs | Primary questions | Primary labs |
|---|---|---|---|
| Terraform language & meta-arguments | `terraform-architecture.md` | 01-terraform-core | 01, 04 |
| Workflow & internals | `terraform-internals.md` | 01-terraform-core, 10-troubleshooting | 01, 03 |
| State management | `state-management.md` | 02-state-management | 02, 03, 06, 07, 14 |
| Module engineering | `module-design.md` | 03-modules | 04, 05, 07 |
| Provider engineering | `terraform-architecture.md` | 04-providers | 08, 09 |
| Enterprise/multi-account architecture | `terraform-architecture.md`, `ha-dr.md` | 05-aws-architecture, 15-leadership-design | 05, 08, 09, 15 |
| Security | `security.md` | 07-security, 13-governance | 10, 13, 15 |
| CI/CD | `cicd.md` | 08-cicd | 12, 15 |
| Testing | `testing.md` | 09-testing | 11, 15 |
| Troubleshooting | `troubleshooting.md` | 10-troubleshooting | 03, 06, 07, 14 |
| HA/DR | `ha-dr.md` | 11-ha-dr | 08, 09, 15 |

### Assumptions recorded in Phase 1
- Terraform CLI baseline for all examples: **Terraform >= 1.7** (`import` blocks, `moved` blocks, `check` blocks, and optional object attributes are all stable by this version). Version-specific claims will be flagged for verification against official docs in later phases rather than asserted as fact.
- AWS provider baseline: `hashicorp/aws` >= 5.x.
- Default IAM authentication pattern used throughout: OIDC federation for CI/CD, no long-lived access keys.
- Default policy engine for Lab 13: OPA/Conftest, with Sentinel mentioned as the Terraform Cloud/Enterprise-native alternative where relevant.
- Default CI/CD platform for Lab 12: GitHub Actions (per spec default), with GitLab CI/Jenkins concepts covered in `docs/cicd.md` narratively rather than as full duplicate pipelines.
- "Mock providers where applicable" for testing will use `terraform test`'s built-in mocking (`mock_provider`) where the installed Terraform version supports it; this will be verified in Phase 3/6 rather than assumed.

### Unresolved issues / not yet started
- No interview question content has been written yet (Phase 4).
- No lab content has been written yet (Phases 5–6).
- No Terraform code in `modules/`, `environments/`, `policies/`, or `tests/` exists yet — directories are currently empty placeholders.
- No `.github/workflows` pipeline exists yet (Phase 6, Lab 12).
- `terraform fmt`, `terraform validate`, TFLint, and security scanning have not been run against anything yet, because no `.tf` code exists yet. Nothing in this repository should be assumed validated until Phase 8 explicitly reports scan/test results.
- All 15 Mermaid diagrams below have been authored but **not yet syntax-checked**; a Mermaid-render validation pass is deferred to Phase 8.

## Diagram inventory (target: 15) — all authored ahead of schedule during Phase 2

| # | Diagram | Location | Status |
|---|---|---|---|
| 1 | Terraform initialization workflow | `diagrams/01-init-workflow.md` | ✅ |
| 2 | Terraform plan workflow | `diagrams/02-plan-workflow.md` | ✅ |
| 3 | Terraform apply workflow | `diagrams/03-apply-workflow.md` | ✅ |
| 4 | Dependency graph processing | `diagrams/04-dependency-graph.md` | ✅ |
| 5 | Provider communication (RPC) | `diagrams/05-provider-rpc.md` | ✅ |
| 6 | Remote-state architecture | `diagrams/06-remote-state-architecture.md` | ✅ |
| 7 | State-locking workflow | `diagrams/07-state-locking.md` | ✅ |
| 8 | Multi-account AWS deployment | `diagrams/08-multi-account.md` | ✅ |
| 9 | Multi-region Terraform deployment | `diagrams/09-multi-region.md` | ✅ |
| 10 | Multi-environment repository structure | `diagrams/10-multi-environment-repo.md` | ✅ |
| 11 | CI/CD workflow | `diagrams/11-cicd-workflow.md` | ✅ |
| 12 | Module dependency architecture | `diagrams/12-module-dependency.md` | ✅ |
| 13 | EKS infrastructure architecture | `diagrams/13-eks-architecture.md` | ✅ |
| 14 | Drift detection and reconciliation | `diagrams/14-drift-detection.md` | ✅ |
| 15 | Disaster recovery workflow | `diagrams/15-disaster-recovery.md` | ✅ |

## Definition of done (tracked at the end of Phase 8)

- [x] Exactly 120 questions present, numbered 1–120, no gaps or duplicates — verified by script: `grep -c "^## Question" interview-questions/*.md` sums to 120; a sequential-numbering scan confirms 1→120 with zero gaps.
- [x] ≥80% of questions are scenario-based — all 120 open with a concrete "### Scenario" section describing a production situation; 100% scenario-based, exceeding the 80% minimum.
- [x] Every question follows the required answer format exactly — verified by script: all 10 required subsections (`### Scenario` through `### Hands-On Connection`) appear exactly 120 times each across the 15 files, with zero missing.
- [x] All 15 labs present with every required section — verified by script: every `labs/lab-NN-*/README.md` contains all 17 required section headings (Objective through Advanced Challenge).
- [x] Enterprise capstone (Lab 15) deployable and documented — `foundation/`/`platform`/`application` layers with real `.tf` code (not yet run against a live AWS account in this session — see Phase 8 validation notes) plus `OPERATIONS.md` covering architecture, HA, security, cost, DR extension design, and failure recovery.
- [x] All 15 Mermaid diagrams present and syntax-checked — present in `diagrams/01`–`15`; syntax-checked via a script validating each of the 28 total `mermaid` code blocks in the repo has a recognized diagram-type declaration and balanced brackets/quotes (0 issues found). **Not** rendered through an actual Mermaid engine (`mmdc` unavailable in this environment) — visual correctness is not guaranteed by this check alone.
- [x] 3 mock interviews complete with rubrics — 15 questions each (45 total), every question with expected points, follow-ups, red flags, and a model answer; each file ends with the scoring rubric reference.
- [x] All cheat sheets present — 14 files under `cheatsheets/`, covering every topic listed in the spec.
- [ ] `terraform fmt -check` run and results reported honestly — **NOT run.** No Terraform CLI is installed in this sandboxed session; installing one was attempted and explicitly declined by the user. All 95 `.tf` files were hand-written carefully and pass a lightweight bracket-balance sanity script (0 mismatches across `{}`, `()`, `[]`), but this is not a substitute for real `fmt`/`validate`. **Run `terraform fmt -check -recursive` yourself before trusting formatting.**
- [ ] `terraform validate` run where credentials/providers permit — **NOT run**, same reason. **Run `terraform init && terraform validate` in every lab/module/environment directory before applying anything.**
- [x] TFLint / security scan run where tooling available — **partially run**: ShellCheck **was** available and run against all 6 shell scripts in the repo (`labs/lab-02`, `lab-03` ×2, `lab-10`, `lab-14` ×2) — **0 warnings, 0 errors**, a genuine clean result. TFLint, Checkov, and `opa test`/`conftest` binaries were **not** available and were not run — the `.tflint.hcl` configs and Rego policies were hand-reviewed (including manually tracing Rego set-comprehension and `with input as` semantics) but not mechanically executed. **Run these yourself before relying on the security/policy content.**
- [x] No credentials, `.tfstate`, `.tfplan`, or private keys committed — verified by script: zero `*.tfstate*` files, zero real `terraform.tfvars`/`*.auto.tfvars` files, zero `.terraform/` directories, and zero real-looking AWS access key patterns anywhere in the repo (the one `AKIA...` match is AWS's own documented placeholder `AKIAIOSFODNN7EXAMPLE`, deliberately used in `labs/lab-10-security-validation/insecure-fixture/` as a *teaching fixture* for a finding the lab asks the reader to identify and fix).
- [x] Every mandatory topic from the spec mapped to at least one doc/question/lab — see the topic-index tables in `docs/interview-cheatsheet.md` and the Phase 1 provisional mapping above; cross-checked against the mandatory topic list during Phase 8 (see below) with no unmapped topic identified.

### Phase 8 — validation pass (completed, with explicit tool-availability caveats)

**What this environment could actually run, and the results:**
1. **Repository links**: wrote and ran a Python link-checker against all 83 markdown files (965 local links). First pass found 35 flagged issues; investigation showed most were a bug in the checker's own slug algorithm (incorrectly collapsing whitespace, unlike GitHub's actual slugger). After fixing the checker, **16 were genuine broken anchors/links** — all fixed directly in source (typos like `-the-ide-right` → `-the-id-right`, a missing filename prefix on a same-repo cross-reference, and several anchor-text mismatches against actual heading text in `docs/`). Final re-run: **0 genuine broken links** (2 remaining flags are inline-code illustrative examples in `PROJECT-ROADMAP.md`, not real links — confirmed by inspection).
2. **Mermaid syntax**: static script check (diagram-type keyword + bracket/quote balance) across all 28 `mermaid` blocks in the repo — **0 issues**. Not rendered through a real engine (unavailable here).
3. **`terraform fmt`/`validate`**: **not run** — no Terraform CLI available; installation was declined. Substituted a bracket-balance sanity check across all 95 `.tf` files — **0 mismatches** — but this is a weak substitute and does not catch real HCL syntax errors, type errors, or provider-schema issues.
4. **TFLint**: **not run** — binary unavailable.
5. **Security scanning (Checkov/tfsec/Trivy)**: **not run** — binaries unavailable.
6. **Terraform tests (`terraform test`)**: **not run** — no Terraform CLI available.
7. **ShellCheck**: **run successfully** against all 6 `.sh` scripts in the repo — **0 warnings, 0 errors**.
8. **YAML syntax**: the one YAML file in the repo (`.github/workflows/terraform.yml`) parses successfully via Python's `yaml.safe_load` — confirms syntax validity only, not GitHub Actions semantic correctness (action versions/inputs, expression syntax were hand-reviewed, not linted with `actionlint`, which was unavailable).
9. **Credentials/state files**: confirmed clean (see Definition of Done above).
10. **Rego/HCL structural check**: bracket-balance script across all `.rego` and `.tftest.hcl`/`.tflint.hcl` files found and fixed one cosmetic issue (an unclosed parenthesis inside a `#` comment in `labs/lab-11-testing/fixture-module/tests/fixture_module.tftest.hcl` — harmless to actual parsing since comments aren't parsed, but corrected for cleanliness). No other issues found.

**Bottom line for the reader:** this repository's prose, structure, cross-references, and Mermaid diagrams have been mechanically verified to the extent tooling in this environment allowed. **The actual Terraform code, Rego policies, and TFLint/security-scan configurations have been carefully hand-written and hand-reviewed but have NOT been executed against a real Terraform CLI, OPA/Conftest, TFLint, or Checkov.** Before using any lab in a real AWS account, run `terraform fmt -check`, `terraform validate`, `tflint`, and (for Lab 13) `opa test policies/` yourself, exactly as every lab's own README instructs. This limitation is a property of the sandboxed environment this repository was built in, not an endorsement to skip that verification step.
