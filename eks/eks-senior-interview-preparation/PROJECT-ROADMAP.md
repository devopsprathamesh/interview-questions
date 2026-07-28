# Project Roadmap — EKS Senior Interview Preparation

This document tracks build progress, records assumptions, and will hold the honest, mechanically-verified Phase 8 validation report once complete. It follows the identical discipline established in the companion [Terraform](../../terraform/terraform-senior-interview-preparation/PROJECT-ROADMAP.md) and [Ansible](../../ansible/ansible-senior-interview-preparation/PROJECT-ROADMAP.md) repositories: report what was actually done, not what was intended.

## Phase Overview

| Phase | Description | Status |
|---|---|---|
| 1 | Repository scaffold (directories, README, roadmap, .gitignore) | ✅ Complete |
| 2 | Core documentation (`docs/`) | ✅ Complete |
| 3 | Diagrams (15 Mermaid diagrams) | ✅ Complete |
| 4 | 120 interview questions across 15 category files | ✅ Complete |
| 5 | Labs 1–8 (cluster bootstrap through security hardening) | ⬜ Not started |
| 6 | Labs 9–15 (observability through enterprise capstone) | ⬜ Not started |
| 7 | Mock interviews (3) and cheat sheets | ⬜ Not started |
| 8 | Validation pass and honest final report | ⬜ Not started |

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

Progress: **0 / 120 questions written** as of this roadmap entry (Phase 4 starting next).

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
| 1 | EKS Control Plane and Data Plane Architecture | ⬜ |
| 2 | Pod Networking and VPC CNI ENI Allocation | ⬜ |
| 3 | Request Path: Ingress → Load Balancer → Service → Pod | ⬜ |
| 4 | IRSA Trust Chain (OIDC Provider → IAM Role → ServiceAccount → Pod) | ⬜ |
| 5 | Managed Node Group Lifecycle | ⬜ |
| 6 | Karpenter Provisioning Decision Flow | ⬜ |
| 7 | EBS/EFS CSI Volume Lifecycle | ⬜ |
| 8 | Pod Admission Flow (Pod Security, OPA/Kyverno, Mutating/Validating Webhooks) | ⬜ |
| 9 | Cluster/Add-on Upgrade Sequencing | ⬜ |
| 10 | Observability Data Flow (Container Insights, Prometheus, Fluent Bit) | ⬜ |
| 11 | GitOps Reconciliation Loop (ArgoCD) | ⬜ |
| 12 | Progressive Delivery (Canary/Blue-Green via Argo Rollouts) | ⬜ |
| 13 | CI/CD Pipeline for Kubernetes Manifests | ⬜ |
| 14 | Multi-AZ / Multi-Region HA and DR Topology | ⬜ |
| 15 | Multi-Tenant Cluster Isolation Model | ⬜ |

## Provisional Topic Index

Will be filled in during Phase 7 as part of the interview cheat sheet, mapping each doc/lab/diagram to the question numbers that reference it — mirrors `docs/interview-cheatsheet.md` in both companion repositories.

## Definition of Done

- [ ] All 120 questions written, following the established 10-part format (Scenario, Interview Question, Strong Senior-Level Answer with 8 bolded sub-labels, Step-by-Step Implementation, Under-the-Hood Explanation, Common Weak Answer, Why the Weak Answer Fails, 3 Follow-Up Questions, Key Interview Signals, Hands-On Connection)
- [ ] All 15 labs complete with the full required README structure
- [ ] All 15 diagrams present and valid Mermaid syntax
- [ ] 3 mock interviews complete with rubrics
- [ ] All cheat sheets written
- [ ] CI/CD reference pipeline and policy-as-code examples in place
- [ ] Phase 8 validation performed and honestly reported (link integrity, YAML/manifest syntax sanity, question-count verification, lab-section completeness, tool-availability caveats)
