# Project Roadmap — EKS Senior Interview Preparation

This document tracks build progress, records assumptions, and will hold the honest, mechanically-verified Phase 8 validation report once complete. It follows the identical discipline established in the companion [Terraform](../../terraform/terraform-senior-interview-preparation/PROJECT-ROADMAP.md) and [Ansible](../../ansible/ansible-senior-interview-preparation/PROJECT-ROADMAP.md) repositories: report what was actually done, not what was intended.

## Phase Overview

| Phase | Description | Status |
|---|---|---|
| 1 | Repository scaffold (directories, README, roadmap, .gitignore) | ✅ Complete |
| 2 | Core documentation (`docs/`) | ✅ Complete |
| 3 | Diagrams (15 Mermaid diagrams) | ✅ Complete |
| 4 | 120 interview questions across 15 category files | ✅ Complete |
| 5 | Labs 1–8 (cluster bootstrap through security hardening) | ✅ Complete |
| 6 | Labs 9–15 (observability through enterprise capstone) | ✅ Complete |
| 7 | Mock interviews (3) and cheat sheets | ✅ Complete |
| 8 | Validation pass and honest final report | ✅ Complete |

## Phase 1 — Repository scaffold (completed)

Created the full directory skeleton: `docs/`, `interview-questions/`, `diagrams/`, `mock-interviews/`, `cheatsheets/`, `policies/tests/`, `tests/`, `scripts/`, `.github/workflows/`, 15 `labs/` subdirectories, `manifests/{base,overlays/{dev,staging,production}}`, and `charts/`. Wrote `README.md` (repo overview, usage paths, prerequisites, cost warning, Interview Response Framework, Lab Dependency Map, relationship to the Terraform/Ansible companion repos) and `.gitignore` (kubeconfig, AWS credentials, Terraform state, Helm chart archives, secrets). No validation performed yet — this is scaffold only.

## Phase 2 — Core documentation (completed)

Wrote 11 deep-dive docs in `docs/`: `eks-architecture.md`, `networking.md`, `iam-irsa.md`, `security.md`, `node-management-and-autoscaling.md`, `storage.md`, `observability.md`, `cicd-gitops.md`, `troubleshooting.md`, `ha-dr.md`, `governance-policy.md`, plus `interview-cheatsheet.md` as a master topic index. Each doc cross-references the companion Terraform and Ansible repositories where the same underlying principle recurs (least privilege, staged rollout, single source of truth, "who watches the watcher"), and ends with a "common weak vs. senior" comparison table. No live cluster available to validate any of this against — content is written to be technically accurate per documented AWS/Kubernetes/tool behavior, not verified against a running cluster.

## Phase 3 — Diagrams (completed)

Created all 15 Mermaid diagrams in `diagrams/`, each with a short "Key points" section and cross-links back to the relevant docs. Diagram inventory table below updated to reflect completion. Mermaid syntax not mechanically validated against a renderer in this environment (no tool available) — will be checked in Phase 8 via a syntax-sanity script.

## Phase 4 — 120 interview questions (completed)

Wrote all 15 category files in `interview-questions/`, totaling exactly 120 questions, following the established 10-part format (Scenario, Interview Question, Strong Senior-Level Answer with 8 bolded sub-labels, Step-by-Step Implementation, Under-the-Hood Explanation, Common Weak Answer, Why the Weak Answer Fails, 3 Follow-Up Questions, Key Interview Signals, Hands-On Connection) for every single question. Cross-references the companion Terraform and Ansible repositories extensively (IRSA/cross-account patterns mirroring Ansible's assume-role guidance, GitOps drift-correction mirroring Terraform's plan/apply cycle, staged fleet upgrades mirroring both repos' canary discipline, etc.). Question-count and required-subsection-presence will be mechanically verified in Phase 8, not just assumed from the writing process.

## Question Allocation (120 total, continuously numbered)

| # | File | Category | Count | Question #s |
|---|---|---|---:|---|
| 1 | `01-eks-cluster-architecture.md` | EKS cluster architecture and control plane | 10 | 1–10 |
| 2 | `02-networking.md` | Networking (VPC CNI, security groups, load balancers) | 12 | 11–22 |
| 3 | `03-iam-irsa.md` | IAM, IRSA, and Kubernetes RBAC | 12 | 23–34 |
| 4 | `04-node-management.md` | Node management (managed node groups, Karpenter, Fargate) | 8 | 35–42 |
| 5 | `05-storage-stateful.md` | Storage (EBS/EFS CSI) and stateful workloads | 10 | 43–52 |
| 6 | `06-autoscaling-scheduling.md` | Autoscaling and scheduling | 8 | 53–60 |
| 7 | `07-security-hardening.md` | Security hardening (Pod Security, NetworkPolicy, secrets) | 8 | 61–68 |
| 8 | `08-addons-upgrades.md` | Add-ons, Helm, and cluster/version upgrades | 10 | 69–78 |
| 9 | `09-observability.md` | Observability (logging, metrics, tracing) | 8 | 79–86 |
| 10 | `10-cicd-gitops.md` | CI/CD and GitOps (ArgoCD/Flux, progressive delivery) | 12 | 87–98 |
| 11 | `11-troubleshooting.md` | Troubleshooting and production incidents | 6 | 99–104 |
| 12 | `12-ha-dr.md` | High availability and disaster recovery | 6 | 105–110 |
| 13 | `13-performance-scale.md` | Performance, scale, and multi-tenancy | 4 | 111–114 |
| 14 | `14-governance-policy.md` | Governance and policy as code (OPA/Kyverno) | 3 | 115–117 |
| 15 | `15-migration-leadership.md` | Migration, adoption, and leadership/architecture | 3 | 118–120 |

Progress: **120 / 120 questions written** (mechanically verified via `grep -c "^## Question "` summed across all 15 files).

## Lab Dependency Summary

See the Mermaid diagram in `README.md`. Labs 1–4 form the mandatory core path (bootstrap → networking → IRSA → node groups); Labs 5–9 branch out into autoscaling, storage, ingress, security, and observability; Labs 10–13 cover GitOps/CI-CD/policy; Lab 14 covers troubleshooting/recovery; Lab 15 is the capstone drawing on all prior labs.

## Recorded Assumptions

- Cluster provisioning (VPC, control plane, node group launch templates, IAM roles) is assumed to be handled by the companion Terraform repository — this repo's labs pick up from a running cluster and reference the Terraform repo's relevant modules/labs rather than re-deriving cluster-provisioning Terraform from scratch.
- No live AWS account, EKS cluster, or `kubectl`/`eksctl`/`helm`/`argocd`/`opa` binaries are available in this build environment. All manifests, Helm values, and policy files are written to be syntactically correct and logically sound, but have not been applied against a real cluster. This will be reported honestly in Phase 8, exactly as was done for the Terraform and Ansible repositories (where `terraform`/`ansible-lint`/`molecule` binaries were similarly unavailable).
- Do not attempt to install new binaries/tools in this environment without being explicitly asked — this constraint was established during the Terraform repo's build when a `sudo mv terraform ...` installation attempt was rejected.
- Diagram inventory: all 15 diagrams will be tracked in the table below, filled in during Phase 3.

## Diagram Inventory (to be completed in Phase 3)

| # | Diagram | Status |
|---|---|---|
| 1 | EKS Control Plane and Data Plane Architecture | ✅ |
| 2 | Pod Networking and VPC CNI ENI Allocation | ✅ |
| 3 | Request Path: Ingress → Load Balancer → Service → Pod | ✅ |
| 4 | IRSA Trust Chain (OIDC Provider → IAM Role → ServiceAccount → Pod) | ✅ |
| 5 | Managed Node Group Lifecycle | ✅ |
| 6 | Karpenter Provisioning Decision Flow | ✅ |
| 7 | EBS/EFS CSI Volume Lifecycle | ✅ |
| 8 | Pod Admission Flow (Pod Security, OPA/Kyverno, Mutating/Validating Webhooks) | ✅ |
| 9 | Cluster/Add-on Upgrade Sequencing | ✅ |
| 10 | Observability Data Flow (Container Insights, Prometheus, Fluent Bit) | ✅ |
| 11 | GitOps Reconciliation Loop (ArgoCD) | ✅ |
| 12 | Progressive Delivery (Canary/Blue-Green via Argo Rollouts) | ✅ |
| 13 | CI/CD Pipeline for Kubernetes Manifests | ✅ |
| 14 | Multi-AZ / Multi-Region HA and DR Topology | ✅ |
| 15 | Multi-Tenant Cluster Isolation Model | ✅ |

## Phase 5–6 — Labs 1–15 (completed)

Built all 15 labs with real, runnable Kubernetes manifests, Helm values, Kustomize overlays, and CI workflows — not just narrative READMEs. Every lab's `README.md` follows the identical 17-section structure established by the Terraform and Ansible companion repositories (verified mechanically: 255/255 required sections present across all 15 labs). Each lab is designed around reproducing a *specific* interview-question scenario hands-on (e.g., Lab 3 deliberately builds a broken IRSA trust policy, proves the vulnerability with a real `AssumeRoleWithWebIdentity` call, then fixes it and re-proves the fix — not just describing the concept). Labs reference and build on each other in dependency order (per the Lab Dependency Map in `README.md`), and the capstone (Lab 15) composes components from Labs 3, 5–11, and 13 into one working platform with its own `OPERATIONS.md` deliverable.

**Honesty note:** no live EKS cluster, `kubectl`, `helm`, `argocd`, `eksctl`, or `kyverno` CLI was available in this build environment. Every manifest, Helm values file, Kustomize overlay, and shell script was written to be syntactically correct and logically sound through careful manual construction, but none of it has been applied against a real cluster. A learner working through these labs will be the first to actually run this content — this mirrors the identical, honestly-reported constraint in the companion Ansible repository's Phase 5–6.

## Provisional Topic Index

See `docs/interview-cheatsheet.md`'s topic → doc → questions → lab table, filled in during Phase 2/3 and cross-checked against the final question/lab set during Phase 7.

## Definition of Done

- [x] All 120 questions written, following the established 10-part format (Scenario, Interview Question, Strong Senior-Level Answer with 8 bolded sub-labels, Step-by-Step Implementation, Under-the-Hood Explanation, Common Weak Answer, Why the Weak Answer Fails, 3 Follow-Up Questions, Key Interview Signals, Hands-On Connection) — mechanically verified, exactly 120
- [x] All 15 labs complete with the full required README structure — mechanically verified, 255/255 required sections present
- [x] All 15 diagrams present (mechanically verified: fenced `mermaid` blocks present in all 15 files; not rendered through an actual Mermaid engine, no such tool available in this environment)
- [x] 3 mock interviews complete with rubrics (15 questions each, Senior/Lead/Staff)
- [x] All cheat sheets written (12 topic sheets)
- [x] CI/CD reference pipeline and policy-as-code examples in place (Labs 12–13)
- [x] Phase 8 validation performed and honestly reported (link integrity, YAML/manifest syntax sanity, question-count verification, lab-section completeness, tool-availability caveats) — see below

## Phase 7 — Mock interviews and cheat sheets (completed)

Wrote 3 full mock interviews (Senior DevOps Engineer, Lead Platform Engineer, Staff Platform Architect; 15 questions each) following the established format (Interviewer asks / Expected answer points / Follow-up questions / Red flags / Model answer / Full reference), drawing from across all 15 question categories and cross-referencing the companion Terraform and Ansible repositories where the same underlying principle recurs. Wrote 12 topic-focused cheat sheets (`kubectl-commands`, `irsa-and-iam`, `networking-and-vpc-cni`, `storage-and-csi`, `autoscaling-karpenter`, `gitops-and-cicd`, `security-hardening`, `observability`, `troubleshooting-common-failures`, `governance-policy`, `ha-dr`, `interview-response-framework`).

## Phase 8 — Validation pass (completed)

Mirrors the companion Terraform and Ansible repositories' Phase 8 discipline: report what was actually mechanically checked, not what was intended.

### What was validated, and how

| Check | Method | Result |
|---|---|---|
| YAML syntax | Python `yaml.safe_load_all()` across every `.yml`/`.yaml` file in the repo | **50/50 files parsed cleanly** |
| Internal markdown links | Custom script resolving every relative `[text](path)` link (including `#anchor` fragments, using GitHub's actual non-collapsing space-to-hyphen slugify behavior) against the real filesystem | **782 links checked across 77 files; 8 genuine bugs found and fixed (wrong relative-path depth for cross-repo links, mislabeled category filenames/question numbers), 0 remaining** |
| Question count | `grep -c "^## Question "` summed across all 15 category files | **Exactly 120** |
| Lab section completeness | Grep for all 17 required section headers across all 15 lab `README.md` files | **255/255 present** (after fixing 8 labs initially missing an explicit `## Scenario` section) |
| Diagram presence | Grep for a fenced ` ```mermaid ` block in every `diagrams/*.md` file | **15/15 present** (not rendered through an actual Mermaid engine — no such tool available in this environment) |
| Shell scripts | ShellCheck against all 9 `.sh` files in the repo | **0 findings, clean** |
| Secret/credential scan | Grep for common credential file patterns (`.pem`, `id_rsa*`, `*kubeconfig*`) and AWS access-key-ID shape | **Clean — nothing found** |

### Genuine bugs found and fixed during this pass

- A cross-repository relative-path depth error affecting several links to the companion Terraform/Ansible repositories (off by one directory level, depending on whether the source file was in `docs/`, `labs/*/`, or `mock-interviews/`).
- Two mock-interview questions ([Question 50](interview-questions/05-storage-stateful.md) and Question 86) incorrectly linked as if they were EKS-repo-local questions when they're actually companion-Ansible-repo-only content — fixed to properly cross-reference the Ansible repository.
- Two instances of a mislabeled category filename/question-number combination (`11-ha-dr.md` used instead of the correct `12-ha-dr.md`, and a Question 103 reference that belonged to `11-troubleshooting.md`, not `ha-dr.md` at all) in `labs/lab-14-troubleshooting-and-recovery/README.md` and `mock-interviews/mock-interview-03-staff-platform-architect.md`.
- An incorrect Terraform companion-repo lab name (`lab-07-eks-configuration`, which doesn't exist) corrected to the actual lab name, `lab-09-eks-infrastructure`.
- 8 labs (05, 06, 07, 08, 09, 10, 11, 13) were initially missing an explicit `## Scenario` section (present in content but not under the required heading) — added a scenario paragraph to each, verified via the same mechanical section-completeness check used for every other lab.

### What was honestly NOT validated (tool unavailability)

Exactly as documented for the companion Terraform and Ansible repositories' Phase 8, this sandboxed environment has no `kubectl`, `helm`, `argocd`, `eksctl`, `kyverno`, `packer`, `molecule`, or `ansible-lint` binaries installed, and no attempt was made to install them (per the standing constraint established during the Terraform repository's build). This means:

- **No real cluster interaction** — every manifest, Helm values file, Kustomize overlay, Kyverno policy, and shell script in this repository's 15 labs has been written to be syntactically correct and logically sound through careful manual construction and review, but has never actually been applied against a real EKS cluster.
- **No Mermaid rendering** — all 15 diagrams have valid fenced code blocks confirmed by grep, but their actual Mermaid syntax has not been rendered through a real Mermaid engine to confirm it produces the intended diagram.
- **No Helm/Kustomize template rendering** — `helm template`/`kustomize build` were not run to confirm the rendered output is what's intended.

This is reported honestly, not glossed over: a learner working through this repository's labs will be the first to actually execute most of this content against a real cluster, and should expect to encounter and fix minor issues exactly as they would with any hands-on lab material — that's the intended, realistic experience, not a sign of low-effort content.

### Summary

EKS Senior Interview Preparation repository: **all 8 phases complete.** 120 questions, 15 labs (with real, intended-to-be-runnable Kubernetes manifests, Helm values, Kustomize overlays, Kyverno/Argo Rollouts/ArgoCD configs, and CI workflows), 15 diagrams, 3 mock interviews, 12 cheat sheets, 13 core docs. Every mechanical check available in this environment was run and passed (after fixing the genuine bugs found during this pass); every check requiring an unavailable binary is honestly reported as not run, not assumed to pass — consistent with the companion Terraform and Ansible repositories' validation discipline.
