# EKS Security Hardening

Deep-dive reference for [`interview-questions/07-security-hardening.md`](../interview-questions/07-security-hardening.md) and [Lab 8 — Security Hardening](../labs/lab-08-security-hardening/).

## 1. Pod Security Standards and the Pod Security Admission controller

Kubernetes' built-in **Pod Security Admission** (PSA) controller enforces one of three predefined **Pod Security Standards** — `privileged` (unrestricted), `baseline` (blocks known privilege-escalation vectors), `restricted` (heavily locked down: no privilege escalation, must run as non-root, no host namespaces, restricted volume types, seccomp required) — applied per-namespace via labels:
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: production-app
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```
PSA replaced the older, more flexible but far more complex **PodSecurityPolicy** (removed entirely in Kubernetes 1.25) — a senior-level point worth naming explicitly: if a resume or a legacy cluster mentions PSP, that's a signal of either an old codebase or a knowledge gap needing updating, since PSP-dependent clusters had to migrate to PSA (or a third-party admission controller like Kyverno/OPA Gatekeeper for anything PSA's three fixed levels don't cover) before any 1.25+ upgrade.

## 2. NetworkPolicy — see also `docs/networking.md` §7

`NetworkPolicy` objects are inert without an enforcing CNI capability (native VPC CNI network-policy support, or Calico) — see [`docs/networking.md`](networking.md) §7 for the full mechanism. The security-relevant framing here: a `NetworkPolicy`-based "we isolate namespaces from each other" security claim is only as true as the enforcement mechanism actually being active and correctly configured — verify, don't assume.

## 3. Secrets: what Kubernetes Secrets actually protect (and don't)

A Kubernetes `Secret` is **base64-encoded, not encrypted**, by default in etcd — anyone with etcd read access (or an unencrypted etcd backup) can trivially decode every Secret in the cluster. **etcd encryption at rest** (via an EncryptionConfiguration referencing a KMS key — EKS supports this natively via "envelope encryption for Kubernetes secrets" at cluster-creation or update time) is the actual control that makes Secrets genuinely protected at rest. Beyond that:

- **RBAC** controls who/what can *read* a Secret via the API (`get`/`list` on `secrets`) — the more immediately relevant access-control layer day-to-day.
- **External Secrets Operator** or **AWS Secrets Manager/Parameter Store CSI driver** are the preferred pattern for sourcing real secret *values* — syncing from AWS Secrets Manager into a Kubernetes Secret (or mounting directly via CSI) rather than storing the source-of-truth value as a raw Kubernetes Secret checked in anywhere.
- Never commit real Secret manifests to Git in GitOps workflows — see [`docs/cicd-gitops.md`](cicd-gitops.md) §5 for Sealed Secrets/External Secrets patterns that make GitOps-managed secrets safe to commit.

## 4. Admission control: Kyverno and OPA Gatekeeper

Beyond PSA's three fixed levels, **Kyverno** and **OPA Gatekeeper** provide fully custom admission policy (validating and mutating) — e.g., "every image must come from our approved ECR registry," "every Deployment must set resource requests/limits," "no `:latest` tag in production." Both operate as `ValidatingWebhookConfiguration`/`MutatingWebhookConfiguration` resources intercepting the API server's admission chain — meaning a webhook outage or misconfiguration can itself become an availability problem (every admission-controlled resource creation blocks or fails), a genuine operational trade-off of policy enforcement worth naming explicitly (see [`docs/governance-policy.md`](governance-policy.md) and [Question 61](../interview-questions/07-security-hardening.md#question-61)).

## 5. Image supply-chain security

- **ECR image scanning** (basic, or enhanced via Amazon Inspector) flags known CVEs in container images — the direct analog of the companion Terraform/Ansible repositories' Trivy/dependency-scanning guidance, applied to container images.
- **Image signing** (via Cosign/Sigstore, or AWS Signer) and **admission-time signature verification** (via Kyverno's `verifyImages` policy) close the gap between "we scanned the image at build time" and "we're certain the image running in production is the exact one we scanned," preventing a tampered or substituted image from being silently deployed — the Kubernetes-native equivalent of the companion repositories' artifact-integrity discipline (never re-derive a deployable artifact between review and deploy).
- **SBOM generation** (Software Bill of Materials, via Syft or similar) at build time gives an auditable record of exactly what's in a given image, needed to answer "are we affected by CVE-X" quickly across a whole fleet of images without re-scanning everything from scratch.

## 6. Runtime security

Admission-time and build-time controls don't catch a compromised process doing something malicious *after* a legitimately-approved container is already running — **Falco** (or an equivalent eBPF-based runtime security tool) detects anomalous runtime behavior (an unexpected shell spawned inside a container, an unexpected outbound connection, a write to a sensitive path) as a genuinely distinct security layer from admission control and image scanning, closing the "what if the running container itself starts behaving unexpectedly" gap.

## 7. Least privilege at every layer, not just one

A senior-level security answer for EKS names the **full stack** of least-privilege layers, not just one: IAM (node role and IRSA/Pod Identity, see [`docs/iam-irsa.md`](iam-irsa.md)), Kubernetes RBAC (in-cluster authorization), Pod Security Standards/admission policy (workload-level constraints), NetworkPolicy (network-level constraints), and image supply-chain integrity (build/deploy-time constraints) — a genuinely secure cluster has controls at every one of these layers, not just the one that happened to come up in a specific incident.

## 8. Cluster endpoint access as a security control

See [`docs/eks-architecture.md`](eks-architecture.md) §3 — private or tightly-CIDR-restricted API server endpoint access is itself a meaningful security control, reducing the attack surface for credential-stuffing or exploit attempts against the API server directly, independent of everything happening inside the cluster.

## Common weak vs. senior answers

| Weak answer | Senior answer |
|---|---|
| "Kubernetes Secrets are secure, they're not plaintext" | Knows Secrets are only base64-encoded by default; etcd encryption at rest and RBAC are the actual controls |
| "We block bad images with ECR scanning" | Also verifies image signatures at admission time, closing the gap between scan-time and deploy-time image identity |
| "PodSecurityPolicy handles this" | Knows PSP was removed in 1.25 and PSA (or Kyverno/Gatekeeper) is the current mechanism |
| "NetworkPolicy isolates our namespaces" | Verifies an actual enforcement mechanism is active, not just that policy objects exist |

## Related material

- [`docs/iam-irsa.md`](iam-irsa.md), [`docs/networking.md`](networking.md), [`docs/governance-policy.md`](governance-policy.md), [`docs/cicd-gitops.md`](cicd-gitops.md)
- [Lab 8 — Security Hardening](../labs/lab-08-security-hardening/), [Lab 13 — Policy as Code](../labs/lab-13-policy-as-code-opa/)
