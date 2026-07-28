# Cheat Sheet: Security Hardening

## The five-layer model (non-substitutable)
1. **IAM/IRSA** — AWS API access
2. **Kubernetes RBAC** — in-cluster API authorization
3. **Pod Security Admission** — workload-level constraints
4. **NetworkPolicy** — network-level constraints (only if genuinely enforced — see networking cheat sheet)
5. **Container `securityContext`** — kernel-syscall-level constraints on the running process

Getting four layers right does **not** compensate for a gap in the fifth. [Question 66](../interview-questions/07-security-hardening.md#question-66-least-privilege-checked-at-every-layer-but-one)

## Pod Security Admission — opt-in, per namespace
```yaml
metadata:
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```
**No label = defaults to `privileged` (no restriction at all)**, not a safe default. [Question 61](../interview-questions/07-security-hardening.md#question-61-the-namespace-that-forgot-to-lock-its-doors)

## Full container hardening
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 10001
  seccompProfile: { type: RuntimeDefault }
containers:
  - securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities: { drop: ["ALL"] }
```

## Secrets: base64 ≠ encryption
- Base64 is trivially reversible — **not** a security control.
- Real protections: RBAC (who can `get` the Secret) + etcd encryption at rest (KMS envelope encryption).
- Prefer External Secrets Operator (source of truth stays in Secrets Manager) over raw Kubernetes Secrets for anything sensitive.

## Image supply chain
- ECR **enhanced/continuous** scanning catches CVEs disclosed *after* build-time — basic scanning only checks once, at push. [Question 63](../interview-questions/07-security-hardening.md#question-63-the-image-that-passed-the-scan-but-not-the-audit)
- **Signing ≠ verification.** Signing without an admission-time `verifyImages` policy provides an audit trail, not a deploy-time control. [Question 64](../interview-questions/07-security-hardening.md#question-64-the-signature-nobody-checked)
- SLSA provenance attestation (`cosign attest`) for stronger claims than a basic signature (specific commit, review-gate status). [Question 67](../interview-questions/07-security-hardening.md#question-67-the-compliance-requirement-that-outran-the-policy-engine)

## Runtime security (the gap admission control structurally can't cover)
Falco (eBPF-based) detects anomalous behavior in an **already-running, already-admitted** container — a shell spawn, an unexpected outbound connection. Admission-time controls have zero visibility here by design. [Question 65](../interview-questions/07-security-hardening.md#question-65-the-runtime-anomaly-admission-control-never-sees)

## Automated baseline bootstrap
A security baseline manually applied to one cluster provides zero protection to the next cluster provisioned. Use an "App of Apps" GitOps pattern applying the full baseline (PSA defaults, Kyverno policies, Falco, image verification) automatically to any new cluster. [Question 68](../interview-questions/07-security-hardening.md#question-68-the-security-baseline-that-only-existed-in-one-cluster)
