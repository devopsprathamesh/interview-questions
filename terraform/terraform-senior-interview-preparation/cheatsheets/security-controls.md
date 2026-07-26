# Cheat Sheet: Security Controls

## The one fact everyone must know
**`sensitive = true` only redacts CLI/log/UI output.** It does not encrypt, omit, or protect the value in state — the value is still written to state in whatever form the provider returns, plaintext or not. Actual protections:
- State encryption at rest: **SSE-KMS**, not default SSE-S3 (auditable key usage, access-controlled decryption).
- Least-privilege access to the state bucket, scoped per environment.
- Provider/service-managed credentials where possible (`manage_master_user_password = true` on RDS) — no plaintext password ever passes through Terraform at all.
- Rotate anything that was ever exposed, regardless of how contained the exposure looks.

## IAM / OIDC
- CI credentials: OIDC federation, short-lived, no stored secrets.
- Trust policy conditions on `sub` **and** `aud` — a missing `sub` condition means any workflow from the same OIDC issuer (potentially org-wide) can assume the role.
- CI execution role: least privilege derived **empirically** (IAM Access Analyzer from real CloudTrail history), not guessed from scratch.

## Static analysis tool landscape
| Tool | Catches |
|---|---|
| `terraform validate` | Syntax/internal consistency only — not a security tool |
| Checkov | Broad IaC misconfiguration rule set, custom policies supported |
| tfsec / Trivy (config mode) | Terraform-specific security misconfig — verify current tool consolidation status |
| Terrascan | Policy-driven (OPA-based) IaC scanning |
| TFLint | Linting/best-practice, not security |

## Policy as code
- **OPA/Conftest**: platform-agnostic, evaluates plan JSON from any CI. Right default for self-managed Terraform.
- **Sentinel**: native to Terraform Cloud/Enterprise's run pipeline. Right default only if already on TFC/TFE.
- Enforcement must be **hard-mandatory** for non-negotiable rules (public exposure, encryption) — a warning-only gate provides no real guarantee.
- Exceptions require a mandatory justification **and expiration date**, enforced by the policy engine itself, not just documented.

## Layered defense (no single layer is sufficient)
PR-time static scan → policy-as-code plan gate → account-level guardrails (SCPs, S3 Account Public Access Block) → runtime monitoring (Config rules, GuardDuty). Policy-as-code only catches Terraform-originated changes — account-level/Config-rule controls are the backstop for manual/out-of-band changes.

## Supply chain
- Pin exact provider/module versions; commit `.terraform.lock.hcl`.
- Prefer HashiCorp-verified/partner providers for security-critical paths; vet or fork community modules used for security-relevant resources.
- Provider/module mirrors for air-gapped/regulated environments — same checksum trust model as the public registry.

Full reference: [`docs/security.md`](../docs/security.md), [`interview-questions/07-security.md`](../interview-questions/07-security.md), [Lab 10](../labs/lab-10-security-validation/), [Lab 13](../labs/lab-13-policy-as-code/).
