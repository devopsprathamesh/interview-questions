# Interview Questions

A collection of production-grade, senior-level interview preparation repositories for DevOps / Platform / SRE roles. Each subdirectory is a self-contained learning system — not a flashcard list — built around real production failure modes, architecture trade-offs, and hands-on labs, targeted at engineers with roughly 8–15+ years of experience.

There are no "what is a variable" or "what is a provider" questions anywhere in this repo. Every question, lab, and diagram assumes you already operate the tool in production and is built around the decisions and incidents that actually come up at senior/lead/staff level.

All three interview-preparation repositories share the same ten-step **Interview Response Framework** (clarify blast radius → protect production → gather evidence → inspect actual state → root cause → safest remediation → validate → rollback plan → preventive controls → document) and cross-reference each other extensively — the same underlying principles (least privilege, staged rollout, single source of truth, "who watches the watcher," honest capability gaps) recur across all three, expressed through each tool's own idioms.

## Repositories

| Repository | Topic | Status |
|---|---|---|
| [`terraform/`](terraform/README.md) | Terraform, AWS infrastructure, state management, modules, EKS provisioning, policy-as-code | ✅ Complete (all 8 phases) |
| [`ansible/`](ansible/README.md) | Ansible, configuration management, inventory/roles/Vault, AWX, Packer AMI baking | ✅ Complete (all 8 phases) |
| [`eks/`](eks/README.md) | EKS/Kubernetes, networking, IRSA, Karpenter, GitOps (ArgoCD), progressive delivery, policy-as-code | ✅ Complete (all 8 phases) |
| [`floci/floci-local-aws-setup/`](floci/floci-local-aws-setup/README.md) | Running the three repos above against a local AWS emulator instead of a real account | ✅ Setup guide (not an interview-question repo) |

Every one of the three interview-preparation repositories (Terraform, Ansible, EKS) contains, in full: **120 senior-level interview questions** (15 categories, continuously numbered), **15 hands-on labs** culminating in an enterprise capstone, **15 Mermaid architecture/workflow diagrams**, **3 full mock interviews** (Senior / Lead / Staff-Architect, 15 questions each with scoring rubrics), a set of topic **cheat sheets**, deep-dive reference **docs**, and a `PROJECT-ROADMAP.md` documenting exactly what was built and how it was validated — including honest disclosure of what could and couldn't be mechanically tested in the environment these repos were built in (see [Validation and honesty](#validation-and-honesty) below).

Each repository follows a similar shape, with tool-specific differences (Terraform uses `modules/` and `environments/`; Ansible uses `roles/` and `environments/`; EKS uses `manifests/`/`charts/` since Kubernetes has no direct equivalent of a Terraform module or Ansible role at the repo-structure level):

```
<tool>/
├── README.md                # overview, usage paths, cost warning, lab map
├── PROJECT-ROADMAP.md        # single source of truth for build status and validation results
├── docs/                     # deep-dive reference docs (architecture, internals, security, testing, HA/DR, cheat sheet)
├── interview-questions/      # 120 senior-level Q&A across 15 category files
├── labs/                     # 15 hands-on labs, lab-01 → lab-15 enterprise capstone
├── diagrams/                 # 15 Mermaid architecture/workflow diagrams
├── mock-interviews/          # 3 full mock interviews (Senior, Lead, Staff/Architect) with rubrics
├── cheatsheets/               # fast-reference sheets
├── policies/                  # policy-as-code (OPA/Conftest, ansible-lint rules, Kyverno)
├── tests/                     # automated test scaffolding for labs/modules/roles
├── scripts/                   # helper scripts referenced by specific labs
└── modules/ | roles/ | manifests+charts/   # reusable building blocks, named per the tool's own convention
```

## Terraform — Senior Interview Preparation

120 interview questions (15 categories), 15 progressive labs culminating in an enterprise capstone, 7 reusable modules (VPC, security groups, IAM, EKS, RDS, ALB, observability), 15 Mermaid diagrams, 3 mock interviews with rubrics, and 14 cheat sheets covering CLI, state, lifecycle, providers, CI/CD, security, testing, and multi-account patterns.

Start here: [`terraform/README.md`](terraform/README.md)

## Ansible — Senior Interview Preparation

120 interview questions (15 categories, mirroring the Terraform allocation shape), 15 progressive labs culminating in an enterprise capstone with a full `OPERATIONS.md` deliverable, real runnable playbooks/roles/Molecule scenarios, 15 Mermaid diagrams, 3 mock interviews with rubrics, and 11 cheat sheets covering CLI, variable precedence, Vault/secrets, role design, dynamic inventory, testing/Molecule, CI/CD, common failures, AWS integration, performance/scale, and the interview response framework.

Start here: [`ansible/README.md`](ansible/README.md)

## EKS — Senior Interview Preparation

120 interview questions (15 categories covering cluster architecture, networking/VPC CNI, IRSA/IAM, node management/Karpenter, storage/CSI, autoscaling, security hardening, add-ons/upgrades, observability, GitOps/progressive delivery, troubleshooting, HA/DR, performance/scale, governance, and migration/leadership), 15 progressive labs culminating in an enterprise capstone with a full `OPERATIONS.md` deliverable, real Kubernetes manifests/Helm values/Kustomize overlays/Kyverno policies/Argo Rollouts and ArgoCD configs, 15 Mermaid diagrams, 3 mock interviews with rubrics, and 12 cheat sheets. This repository picks up from a cluster already provisioned by the Terraform repository's EKS module and cross-references both companion repos throughout (e.g., the Terraform/Kubernetes-native provisioning boundary, and where Ansible still has a role once workloads move to Kubernetes).

Start here: [`eks/README.md`](eks/README.md)

## Floci — Local AWS Setup

A setup guide, not an interview-question repo: covers installing [Floci](https://floci.io/aws/#quickstart), a local AWS emulator, and pointing the Terraform, Ansible, and EKS repos at it instead of a real AWS account. Includes an honest, lab-by-lab capability matrix — most pure API/Kubernetes-primitive labs are plausible candidates; anything depending on real IAM federation, real load balancers, or real EC2-driven autoscaling (IRSA, the AWS Load Balancer Controller, Karpenter, Packer AMI baking) is flagged as unlikely to work the same locally, not glossed over.

Start here: [`floci/floci-local-aws-setup/README.md`](floci/floci-local-aws-setup/README.md)

## How to use this repo

**Short on time before an interview:** go straight into the relevant tool's `docs/interview-cheatsheet.md` (or `cheatsheets/interview-response-framework.md`) and its most senior-signal `interview-questions/` files (each repo's README calls out which ones), then run the hardest mock interview cold.

**Weeks to prepare:** work through that tool's labs 1–15 in dependency order (each README has a Mermaid lab dependency map), reading the matching `docs/` chapter before each lab and answering the linked interview questions afterward.

**Building a reference platform:** the `modules/`/`roles/`/`manifests+charts/`, and `policies/` directories are usable as a starting point for a real layered, multi-environment AWS/Kubernetes platform — not just interview practice. The Terraform repo provisions the infrastructure; the EKS repo's manifests/Helm charts configure what runs on top of it; the Ansible repo's roles cover everything in between (golden-AMI baking, non-Kubernetes-native configuration management).

## Validation and honesty

Every repository's `PROJECT-ROADMAP.md` ends with a Phase 8 validation report describing exactly what was mechanically checked (YAML/manifest syntax, internal link integrity, question counts, required lab-section presence, ShellCheck against every shell script, a secrets/credentials scan) and what was **not** — none of these repositories were built with access to the real `terraform`, `ansible`, `kubectl`, `helm`, `argocd`, `molecule`, or `ansible-lint` binaries, so no lab content has actually been executed against real infrastructure. This is disclosed plainly in each roadmap rather than implied away: a learner working through any lab here will be the first to actually run it, and should expect the same minor friction as any hands-on material nobody has executed yet.

## Cost warning

All three repositories include labs that provision real, chargeable AWS resources (EC2, EKS, RDS, NAT gateways, ALBs, KMS keys, AMIs, EBS volumes). Every such lab lists which resources cost money, offers a cheaper alternative where one exists (e.g., local Docker/`kind` targets for labs that don't strictly need real AWS, or the [`floci/floci-local-aws-setup/`](floci/floci-local-aws-setup/README.md) emulator for labs that only need the AWS API surface), and includes a mandatory cleanup section — but **no price quoted anywhere in this repo should be treated as current or authoritative**. Verify pricing yourself before running any lab.
