# Cheat Sheet: AWS Multi-Account Patterns

## Layered architecture (state boundaries = ownership boundaries)
```text
Bootstrap    → state backend, CI/CD OIDC identity      (own state, almost never changes)
Foundation   → accounts/OUs, baseline IAM, core network → (own state, changes rarely)
Platform     → EKS/compute, shared LB, observability    (own state, changes moderately)
Application  → app infra, databases, app IAM            (own state per app per env, changes often)
```
Cross-layer references: **SSM Parameter Store** (or similar), never `terraform_remote_state` across ownership boundaries — decouples consumers from the producer's state/backend entirely.

## Provider targeting
```hcl
provider "aws" {
  alias  = "workload_prod"
  region = var.region
  assume_role {
    role_arn = "arn:aws:iam::${var.account_id}:role/terraform-execution"
  }
}
```
One central CI identity assumes narrowly-scoped roles per account+region — never a single broad credential.

## Governance layers (defense in depth)
1. **SCPs** at the OU level — non-bypassable, independent of any team's Terraform/IAM correctness.
2. **Policy-as-code** in every pipeline — reviewable, testable, org-specific rules.
3. **AWS Config rules**, aggregated across accounts — catches manual/non-Terraform changes SCPs and policy-as-code can't see.

## Account vending
Deterministic, Terraform-driven pipeline (not a manual ticket process): account creation → SCP/OU attachment → state backend bootstrap → baseline IAM (including OIDC CI role) → automated conformance check before handoff.

## Why CLI workspaces are NOT environment isolation
Workspaces share the same configuration code and same backend configuration approach — one flag/selection mistake away from a cross-environment accident. Production isolation = **separate root modules**, separate backend configs, separate credentials per environment.

## Networking at scale
- VPC peering is non-transitive — N accounts needing full connectivity = up to N(N-1)/2 connections. Migrate to **Transit Gateway** (hub-and-spoke) once this becomes unmanageable.
- Centralize NAT/egress and common Interface VPC endpoints in a shared-services account rather than duplicating per application account.

## Multi-region
Same module set, parameterized by region via provider aliasing + a pipeline matrix — never a hand-maintained separate copy for the DR region. State backend itself needs its own cross-region replication story, or Terraform can't execute a DR runbook during the exact regional event it's meant to address.

Full reference: [`docs/terraform-architecture.md`](../docs/terraform-architecture.md), [`interview-questions/05-aws-architecture.md`](../interview-questions/05-aws-architecture.md), [Lab 15](../labs/lab-15-enterprise-capstone/).
