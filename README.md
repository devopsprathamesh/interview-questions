# Interview Questions

A collection of production-grade, senior-level interview preparation repositories for DevOps / Platform / SRE roles. Each subdirectory is a self-contained learning system — not a flashcard list — built around real production failure modes, architecture trade-offs, and hands-on labs, targeted at engineers with roughly 8–15+ years of experience.

There are no "what is a variable" or "what is a provider" questions anywhere in this repo. Every question, lab, and diagram assumes you already operate the tool in production and is built around the decisions and incidents that actually come up at senior/lead/staff level.

## Repositories

| Repository | Topic | Status |
|---|---|---|
| [`terraform/terraform-senior-interview-preparation/`](terraform/terraform-senior-interview-preparation/README.md) | Terraform, AWS infrastructure, state management, modules, EKS, policy-as-code | ✅ Complete (all 8 phases) |
| [`ansible/ansible-senior-interview-preparation/`](ansible/ansible-senior-interview-preparation/README.md) | Ansible, configuration management, inventory/roles, AWX, Vault | 🚧 In progress (docs & scaffold done; questions, labs, mocks pending) |

Each repository follows the same shape, so once you've worked through one, the other is immediately familiar:

```
<tool>-senior-interview-preparation/
├── README.md                # overview, usage paths, cost warning, lab map
├── PROJECT-ROADMAP.md        # single source of truth for build status
├── docs/                     # deep-dive reference docs (architecture, internals, security, testing, HA/DR, cheat sheet)
├── interview-questions/      # 120 senior-level Q&A across 15 category files
├── labs/                     # 15 hands-on labs, lab-01 → lab-15 enterprise capstone
├── diagrams/                 # 15 Mermaid architecture/workflow diagrams
├── mock-interviews/          # 3 full mock interviews (Senior, Lead, Staff/Architect) with rubrics
├── cheatsheets/              # fast-reference sheets
├── environments/             # dev / staging / production isolation examples
├── policies/                 # policy-as-code (OPA/Conftest, ansible-lint rules)
├── tests/                    # automated test scaffolding for labs/modules/roles
├── modules/ or roles/        # reusable Terraform modules / Ansible roles used across labs
├── scripts/                  # helper scripts referenced by specific labs
└── .github/workflows/        # reference CI/CD pipeline used by the CI/CD lab
```

## Terraform — Senior Interview Preparation

Fully built out: 120 interview questions (15 categories), 15 progressive labs culminating in an enterprise capstone, 7 reusable modules (VPC, security groups, IAM, EKS, RDS, ALB, observability), 15 Mermaid diagrams, 3 mock interviews with rubrics, and 10 cheat sheets covering CLI, state, lifecycle, providers, CI/CD, security, and multi-account patterns.

Start here: [`terraform/terraform-senior-interview-preparation/README.md`](terraform/terraform-senior-interview-preparation/README.md)

## Ansible — Senior Interview Preparation

Structured to mirror the Terraform repository. Phases 1–3 are complete: full repository scaffold, and all core/AWS/Kubernetes/security/CI-CD/testing/HA-DR reference docs plus all 15 diagrams. Phases 4–8 (the 120 interview questions, labs 1–15, mock interviews, cheat sheets, and final validation pass) are **not yet built** — only the first 5 of 15 interview-question category files exist so far, and `roles/`, `environments/`, `tests/`, and `scripts/` are currently empty directories awaiting content.

See [`ansible/ansible-senior-interview-preparation/PROJECT-ROADMAP.md`](ansible/ansible-senior-interview-preparation/PROJECT-ROADMAP.md) for the exact phase-by-phase status and question allocation plan before assuming any file exists.

Start here: [`ansible/ansible-senior-interview-preparation/README.md`](ansible/ansible-senior-interview-preparation/README.md)

## How to use this repo

**Short on time before an interview:** go straight into the relevant tool's `docs/interview-cheatsheet.md` and its most senior-signal `interview-questions/` files (each repo's README calls out which ones), then run the hardest mock interview cold.

**Weeks to prepare:** work through that tool's labs 1–15 in dependency order (each README has a Mermaid lab dependency map), reading the matching `docs/` chapter before each lab and answering the linked interview questions afterward.

**Building a reference platform:** the `modules/`/`roles/`, `environments/`, and `policies/` directories in the completed (Terraform) repository are usable as a starting point for a real layered, multi-environment AWS platform — not just interview practice.

## Cost warning

Both repositories include labs that provision real, chargeable AWS resources (EC2, EKS, RDS, NAT gateways, ALBs, KMS keys, AMIs). Every such lab lists which resources cost money, offers a cheaper alternative where one exists, and includes a mandatory cleanup section — but **no price quoted anywhere in this repo should be treated as current or authoritative**. Verify pricing yourself before running any lab.
