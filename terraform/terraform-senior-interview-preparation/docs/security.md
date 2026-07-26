# Security and Secrets Management

Security in Terraform is not a checklist you run once — it's a set of controls at every layer: the code you write, the state it produces, the pipeline that runs it, and the credentials that authorize it. This document backs [`interview-questions/07-security.md`](../interview-questions/07-security.md) and [`interview-questions/13-governance.md`](../interview-questions/13-governance.md), and is exercised in [Lab 10](../labs/lab-10-security-validation/) and [Lab 13](../labs/lab-13-policy-as-code/).

## 1. Secrets in state — the fact every senior engineer must internalize

**`sensitive = true` on a variable or output only affects Terraform's own CLI/log/UI rendering.** It redacts the value from `terraform plan`/`apply` console output and from `terraform output` unless `-json` with explicit access. It does **not** encrypt, omit, or redact the value from the state file itself. If a resource's schema stores a database password, a private key, or an API token as an attribute, that value exists in `terraform.tfstate` **in plaintext** (or in whatever form the provider returns it — sometimes not even encrypted at rest by the provider), regardless of how the variable feeding it was marked.

**The actual controls, in order of importance:**
1. **Encrypt state at rest** with SSE-KMS (not default SSE-S3) so decryption is itself an auditable, key-policy-gated action — see [`state-management.md`](state-management.md#6-state-encryption-and-access-control).
2. **Restrict state access** to the minimum set of roles/humans who need it, scoped per environment.
3. **Avoid storing secrets as plain resource arguments where a secrets-manager reference is possible** — e.g., prefer `aws_db_instance.manage_master_user_password = true` (AWS-managed, rotated via Secrets Manager, no password ever passes through Terraform config or state as plaintext) over a hand-supplied `password` argument, where the provider/resource supports it.
4. **Rotate anything that did land in state** if state was ever exposed (committed to git, shared insecurely, backend misconfigured) — treat it exactly like a leaked credential, because it is one.
5. **Native state encryption** (Terraform 1.10+ `encryption` block, where supported) adds a second, Terraform-Core-level encryption layer independent of backend storage encryption — verify current support for your version/backend.

## 2. Sensitive variables and outputs — what they're actually for

```hcl
variable "db_password" {
  type      = string
  sensitive = true
}

output "db_connection_string" {
  value     = "postgres://${var.db_user}:${var.db_password}@${aws_db_instance.main.endpoint}"
  sensitive = true
}
```

Their real purpose: **preventing accidental human exposure** — a secret flashing across a terminal during a live screen-share, landing in a CI log that gets archived and read by anyone with CI access, or being pasted into a Slack message with a plan output. This is a meaningful, necessary control, but it is a **UI/log hygiene control, not a storage/encryption control** — conflating the two is one of the most common weak answers on this topic (see [`interview-questions/07-security.md`](../interview-questions/07-security.md)).

## 3. A sensitive value exposed in a plan / CI logs — investigation and remediation

A canonical senior scenario. Investigation steps:
1. **Determine exactly what was exposed and where** — which CI job, which log line, is the log archived/retained, who has access to it (repo collaborators, a broader CI-platform audience, a third-party log aggregator).
2. **Determine the exposure mechanism** — a variable that should have been `sensitive` and wasn't; a value interpolated into a resource argument that isn't marked sensitive in the *provider schema* (Terraform can only redact what the schema or your own `sensitive` marking tells it to; a secret concatenated into an unrelated non-sensitive output can still leak); or a `local-exec` provisioner echoing an environment variable into stdout.
3. **Contain**: restrict/delete the exposed log if the platform allows it (understanding logs may already be cached/exported elsewhere — treat deletion as risk reduction, not proof of eradication).
4. **Rotate the credential immediately** — this is non-negotiable regardless of how contained the exposure appears; a log you can't fully guarantee was never viewed is a compromised secret.
5. **Fix the root cause**: mark the variable/output `sensitive`, move the value into a secrets manager reference instead of a literal pass-through, and add CI-side secret-scanning (see §4) as a backstop that doesn't rely on remembering to mark every sensitive field correctly by hand.
6. **Prevent recurrence**: add this pattern to your policy-as-code checks (§8) or a pre-commit/CI secret scanner so a future missing `sensitive` marking is caught before merge, not after a leak.

## 4. CI/CD secret handling

- Never store long-lived cloud credentials as CI secrets when OIDC federation is available (§5) — a stored secret is a standing liability (needs rotation, can be exfiltrated from CI platform storage) that OIDC's short-lived, per-run tokens eliminate.
- For secrets that must exist in CI (a third-party API token with no federation option), use the CI platform's native secret store (GitHub Actions Encrypted Secrets, GitLab CI/CD variables marked protected+masked), never plaintext in the pipeline YAML or a committed `.env`.
- Add automated secret-scanning to every pipeline run (gitleaks, truffleHog, or the secret-detection features of your chosen SAST/IaC scanner) as a backstop — see [Lab 10](../labs/lab-10-security-validation/).
- Mask/redact secret values in CI log output at the platform level in addition to Terraform's own `sensitive` marking — defense in depth, since either layer alone can have a gap.

## 5. AWS IAM roles and OIDC authentication

Covered in provider-configuration detail in [`terraform-architecture.md`](terraform-architecture.md#5-authentication--avoiding-credentials-in-code); the security-framing summary:
- **OIDC federation** (GitHub Actions ↔ AWS STS, or Terraform Cloud's dynamic provider credentials) eliminates stored long-lived AWS credentials entirely from CI. The trust policy on the assumed role should condition on **specific repository, branch, and (where supported) environment** claims in the OIDC token — a trust policy that only checks the OIDC provider without constraining the subject claim effectively trusts *any* repository that can present a token from that identity provider, which is a common, dangerous misconfiguration.
- **Least privilege**: the CI execution role should hold only the permissions its actual Terraform configurations need — scoped by resource ARN patterns and environment path where feasible, not `*:*` "because it's easier." A compromised or over-broad CI role is the single highest-leverage target in the entire pipeline; treat its policy with the same review rigor as production IAM policy for humans.
- **Separate roles per environment**: the dev-environment CI role should not have any path to assume into or act on production resources — this is what makes "wrong AWS account" or "wrong environment" pipeline mistakes fail safely (access denied) instead of silently succeeding against the wrong environment.

## 6. State bucket policies, encryption, and KMS

Minimum bucket policy controls for a production state bucket:
- Deny any request not using TLS (`aws:SecureTransport` condition).
- Deny unencrypted `PutObject` (enforce `s3:x-amz-server-side-encryption` = `aws:kms`).
- Restrict `s3:GetObject`/`s3:PutObject` to specific IAM roles/paths, not account-wide access.
- Enable **versioning** (recovery — see [`state-management.md`](state-management.md#7-state-corruption-loss-and-recovery)) and **CloudTrail data events** on the bucket (audit — see §7).
- A dedicated **KMS key per environment** (or at minimum per sensitivity tier) so a compromised dev KMS key/grant can't decrypt production state, and so key policies can independently gate who may decrypt each environment's data.

## 7. Audit logging

CloudTrail management + data events covering the state bucket, the CI execution roles' `AssumeRole` calls, and KMS key usage together answer: who read/wrote state, when, from what identity, and whether any decrypt operation happened outside expected CI activity. This is the forensic backbone for investigating a suspected state exposure (§3) or a suspicious out-of-band infrastructure change (drift investigation — see [`state-management.md`](state-management.md#11-manual-infrastructure-changes-and-drift)).

## 8. Static analysis and IaC scanning

| Tool | Primary focus | Notes |
|---|---|---|
| `terraform validate` | Syntax/internal consistency | Not a security tool — catches config errors, not misconfigurations |
| **Checkov** | Broad IaC security/compliance rule set (AWS, Azure, GCP, Kubernetes, Dockerfiles) | Large built-in rule library; supports custom policies in Python/YAML |
| **tfsec** (now largely folded into Trivy's config scanning) | Terraform-specific security misconfiguration scanning | Fast, Terraform-native; verify current maintenance status/successor tooling before asserting it as actively developed in an interview — the ecosystem has consolidated tools over time |
| **Trivy** (config scanning mode) | Unified scanner covering IaC misconfig, container images, and dependency vulnerabilities | Increasingly the consolidated choice covering what tfsec/several standalone scanners used to do separately |
| **Terrascan** | Policy-driven IaC scanning (OPA-based rule engine under the hood) | Similar space to Checkov/tfsec; choice is often organizational preference |
| **TFLint** | Terraform-specific linting (provider-aware best practices, deprecated syntax, some correctness checks) | Complements security scanners; not itself a security tool |

**Practical guidance for an interview and for real pipelines:** know *what class* of problem each tool catches (misconfiguration vs. lint vs. policy) rather than memorizing exact current tool names/rankings, since this space consolidates and renames tools over time — verify current tool status before treating any specific claim as durable. [Lab 10](../labs/lab-10-security-validation/) wires at least one scanner into a pipeline against intentionally insecure configuration so you practice reading and fixing real findings.

## 9. Policy as code

Static scanners catch generic misconfigurations (public S3, open security groups); **policy as code** enforces your organization's *specific* rules as a mandatory, versioned, testable gate — no public buckets in this org's accounts, mandatory `CostCenter`/`Owner` tags, no instance types above a size threshold in non-prod, deployments restricted to approved regions only.

- **OPA (Open Policy Agent) + Conftest**: write policies in Rego, evaluate them against a `terraform show -json` plan or against raw `.tf`/JSON, fail the pipeline on violation. Open-source, cloud/tool-agnostic, works with any CI platform.
- **Sentinel**: HashiCorp's policy-as-code framework, native to Terraform Cloud/Enterprise, with tighter integration (policy sets attached directly to workspaces, soft-mandatory/hard-mandatory enforcement levels built in) at the cost of being TFC/TFE-specific.

**Enforcement levels matter**: a policy engine that only *warns* provides no actual guarantee — production-grade governance requires **hard-mandatory** policies that block apply on violation for non-negotiable rules (public exposure, unencrypted storage), with a narrow, audited override/exception process rather than a universal bypass flag. See [Lab 13](../labs/lab-13-policy-as-code/) and [`interview-questions/13-governance.md`](../interview-questions/13-governance.md).

## 10. Security group validation and public exposure prevention

Common production incidents and their prevention layers:
- **0.0.0.0/0 ingress on a sensitive port** (database, SSH, RDP) — caught by static scanning (§8) at PR time, and again by policy-as-code (§9) as a hard gate, plus AWS Config rules as a runtime backstop for anything that slips through (e.g., manual console changes outside Terraform entirely).
- **Public S3 buckets** — block public access settings should be enforced at the **account level** (S3 Account Public Access Block) as defense in depth, not solely relying on every bucket resource being configured correctly in every Terraform module.
- **Layered defense**: PR-time scan → policy-as-code plan gate → account-level guardrails (SCPs, Config rules) → runtime monitoring (GuardDuty). No single layer should be treated as sufficient on its own — this layered framing is exactly what a Staff-level answer should emphasize over "we run Checkov in CI."

## 11. Supply-chain risk: provider and module trust

- Every provider and module is executable code (or, for providers, a binary) that runs with whatever credentials your Terraform execution environment holds. A compromised or malicious provider/module has the same blast radius as a compromised CI credential.
- **Mitigations**: pin exact versions (module `version` constraints, provider lock file — see [`terraform-architecture.md`](terraform-architecture.md#3-provider-version-constraints-and-the-dependency-lock-file) and [`module-design.md`](module-design.md#5-module-versioning-and-semantic-versioning)); prefer HashiCorp-verified or well-known partner providers for anything touching production credentials; maintain an internal allowlist/review process for third-party community modules before they're used in production paths; use provider/module mirrors in regulated environments (see [`terraform-architecture.md`](terraform-architecture.md#6-provider-installation-mirrors-and-air-gapped-environments)) so you control exactly which binaries/sources are reachable at all.
- Treat a module registry compromise or a typosquatted module name the same way you'd treat a compromised npm/PyPI package — it's the same class of supply-chain risk, just less commonly discussed in a Terraform-specific context.

## Common weak answer vs. senior answer

| Scenario | Weak answer | Senior answer |
|---|---|---|
| "How do you protect secrets?" | "Mark variables as `sensitive`" | `sensitive` only redacts CLI/log output; real protection is state encryption (SSE-KMS), least-privilege state access, secrets-manager-managed credentials where possible, and rotation if ever exposed |
| Preventing public S3 buckets | "Add a Checkov check in CI" | Layer PR-time scanning with a hard-mandatory policy-as-code gate *and* account-level Public Access Block as a backstop for anything outside Terraform's control |
| CI/CD AWS auth | "Store an access key as a CI secret" | Use OIDC federation with a trust policy scoped to specific repo/branch/environment claims; no long-lived credentials in CI at all |
| A secret appeared in CI logs | "Delete the log" | Rotate the credential immediately regardless of containment confidence, then fix the root cause (sensitive marking, secrets-manager reference, or scanner) so it can't recur |

## Related material
- Interview questions: [`interview-questions/07-security.md`](../interview-questions/07-security.md), [`interview-questions/13-governance.md`](../interview-questions/13-governance.md)
- Hands-on: [Lab 10 — Terraform Security Pipeline](../labs/lab-10-security-validation/), [Lab 13 — Policy as Code](../labs/lab-13-policy-as-code/)
- Diagrams: [`diagrams/06-remote-state-architecture.md`](../diagrams/06-remote-state-architecture.md), [`diagrams/08-multi-account.md`](../diagrams/08-multi-account.md)
