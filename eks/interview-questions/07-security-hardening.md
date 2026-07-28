# Category 7: Security Hardening (Pod Security, NetworkPolicy, Secrets)

Questions 61–68 of 120. Category weight: 8 questions. Deep-dive reference: [`docs/security.md`](../docs/security.md).

---

## Question 61: The namespace that forgot to lock its doors

### Scenario
A new namespace is created for a team's workloads with no Pod Security Admission labels set at all. Weeks later, a security review finds a pod running as root with a hostPath volume mount, something that would have been blocked under the `baseline` or `restricted` standard.

### Interview Question
Explain why this wasn't blocked, and design the fix.

### Strong Senior-Level Answer
**Initial assessment:** per [`docs/security.md`](../docs/security.md) §1, Pod Security Admission is opt-in per namespace via labels — a namespace with no `pod-security.kubernetes.io/enforce` label defaults to the permissive `privileged` standard (effectively no restriction at all), meaning this pod's risky configuration was never actually evaluated against any meaningful security standard.

**Technical reasoning:** PSA enforcement is entirely namespace-scoped and label-driven — there's no cluster-wide default that silently protects an unlabeled namespace; the absence of a label is functionally equivalent to explicitly choosing the least restrictive standard, a fact that's easy to overlook when creating namespaces without a standardized template.

**Investigation process:** confirm via `kubectl get namespace <name> -o yaml` the absence of PSA labels, and audit other namespaces in the cluster for the same gap — this is very likely not an isolated incident if namespace creation isn't standardized.

**Recommended solution:** add the appropriate PSA labels (`restricted` for most workloads, `baseline` where genuinely necessary with documented exceptions) to this namespace, and audit/fix every other unlabeled namespace across the cluster.

**Risk controls:** applying `restricted` to a namespace with already-running non-compliant pods will flag (in `audit`/`warn` mode) or block (in `enforce` mode) those pods on their next admission event (e.g., a rolling update) — roll out in `audit` mode first to see what would be affected before flipping to `enforce`, per the standard policy-rollout discipline established in [`docs/governance-policy.md`](../docs/governance-policy.md) §3.

**Validation steps:** after enforcement, confirm a deliberately-submitted non-compliant pod spec (root user, hostPath mount) is genuinely rejected, and confirm legitimate existing workloads continue to function.

**Rollback or recovery strategy:** temporarily set `enforce` back to `baseline` (or `audit`-only) if enforcement breaks a legitimate workload, while that workload is brought into compliance or granted an explicitly-reviewed exception.

**Long-term prevention:** bake PSA labels into the standard namespace-creation template/GitOps manifest (never create a namespace without them), and add a Kyverno/Gatekeeper policy specifically rejecting any *new* namespace lacking PSA labels — a structural guardrail closing this gap at its source.

### Step-by-Step Implementation
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: my-team-namespace
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: latest
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

### Under-the-Hood Explanation
The Pod Security Admission controller checks a pod's spec against the standard indicated by its namespace's labels at admission time — with no label present, it falls through to the built-in cluster-level default (`privileged` unless a cluster-wide default has been separately configured), meaning nothing about pod creation in an unlabeled namespace is evaluated against `baseline`/`restricted` criteria at all.

### Common Weak Answer
"Just fix this one pod's configuration, that solves the immediate problem."

### Why the Weak Answer Fails
Fixing the one discovered pod doesn't address the namespace-level gap that allowed it (and potentially others not yet found) in the first place — the durable fix is the namespace-level PSA label plus a structural guardrail preventing any future namespace from being created without one.

### Follow-Up Questions
1. How would you audit an entire cluster for namespaces missing PSA labels at scale?
2. What's the difference between `enforce`, `audit`, and `warn` PSA modes, and when would you use all three simultaneously?
3. How would you handle a legitimate workload that genuinely needs privileged access despite the namespace's general `restricted` standard?

### Key Interview Signals
Understands PSA's opt-in, label-driven, namespace-scoped enforcement model precisely, and closes the gap structurally (template + admission policy) rather than just fixing the one discovered instance.

### Hands-On Connection
[Lab 8 — Security Hardening](../labs/lab-08-security-hardening/).

---

## Question 62: The Secret that was never actually secret

### Scenario
A team discovers that `kubectl get secret my-db-credential -o jsonpath='{.data.password}' | base64 -d` reveals their production database password in plaintext to anyone with basic `get secrets` RBAC permission in that namespace — which, on investigation, turns out to be a fairly broad group of engineers via an overly generous `Role`.

### Interview Question
Diagnose the layered failure here and design the fix.

### Strong Senior-Level Answer
**Initial assessment:** per [`docs/security.md`](../docs/security.md) §3, this reflects a fundamental misunderstanding treated as a security control — base64 encoding was never intended as protection, and the actual protections (RBAC scoping and etcd encryption at rest) were both insufficiently applied here: RBAC too broad, and (separately, worth checking) etcd encryption possibly not even enabled.

**Technical reasoning:** anyone with `get`/`list` RBAC permission on `secrets` in this namespace can trivially decode any Secret's contents — this is expected, standard Kubernetes behavior, not a vulnerability in Kubernetes itself; the actual security failure is that RBAC access to `secrets` was granted more broadly than the principle of least privilege warrants for a production database credential specifically.

**Investigation process:** confirm exactly which `Role`/`RoleBinding` grants this broad group access to `secrets` in this namespace, and confirm separately whether etcd encryption at rest is enabled for the cluster (an independent, complementary protection layer) — both are worth checking, since fixing RBAC alone doesn't address an unencrypted etcd's exposure to anyone with direct etcd/backup access (though on EKS, that's AWS-managed and not customer-accessible per [`docs/eks-architecture.md`](../docs/eks-architecture.md) §6, still worth confirming for completeness).

**Recommended solution:** tighten RBAC so only the specific ServiceAccount(s)/identities that genuinely need this credential (the application itself, via IRSA-fetched or CSI-mounted secrets, not broad human access) can read it — and migrate the actual credential *value* to be sourced from AWS Secrets Manager via External Secrets Operator or the Secrets Manager CSI driver (per [`docs/security.md`](../docs/security.md) §3), rather than a manually-created, broadly-readable Kubernetes Secret.

**Risk controls:** rotate the exposed credential immediately, since its value has been readable by a broader group than intended for an unknown period — treat this as a genuine credential-exposure incident requiring rotation, not just an access-control fix.

**Validation steps:** after tightening RBAC, confirm `kubectl auth can-i get secrets --as=<previously-broad-identity>` now correctly returns "no" for this specific Secret/namespace, and confirm the application itself still functions correctly with its narrower, appropriate access path.

**Rollback or recovery strategy:** not applicable to the RBAC tightening itself; the credential rotation is the actual recovery action for the exposure that already occurred.

**Long-term prevention:** treat any `Role`/`ClusterRole` granting broad `get`/`list` access to `secrets` as a standing, high-priority review flag (similar to the RBAC wildcard concern in Question 31), and standardize on External Secrets Operator/CSI-driver-sourced secrets (never manually-created Kubernetes Secrets with directly-embedded sensitive values) for anything genuinely sensitive going forward.

### Step-by-Step Implementation
```yaml
# Tightened RBAC - only the specific application ServiceAccount, not broad engineer access
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: read-db-credential
  namespace: production
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    resourceNames: ["my-db-credential"]   # scoped to this specific secret, not all secrets
    verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: app-read-db-credential
  namespace: production
subjects:
  - kind: ServiceAccount
    name: my-app-sa
roleRef: { kind: Role, name: read-db-credential, apiGroup: rbac.authorization.k8s.io }
```

### Under-the-Hood Explanation
`kubectl get secret -o jsonpath` followed by `base64 -d` simply reverses the encoding Kubernetes applies to Secret data for API-transport purposes — this is a documented, expected, and trivially-reversible transformation, not encryption; the *actual* protections are RBAC (controlling who can issue this `get` request in the first place) and etcd encryption at rest (controlling whether the stored data itself is protected from direct storage-layer access) — both entirely independent of the base64 encoding itself.

### Common Weak Answer
"Kubernetes Secrets are insecure by design, we should stop using them entirely."

### Why the Weak Answer Fails
This overreacts to a misunderstanding of what Secrets ever claimed to provide — Secrets remain a reasonable *delivery* mechanism for credential values into pods when combined with proper RBAC scoping and, for the actual value's source of truth, an external secrets manager; the fix is correcting the surrounding controls, not abandoning the mechanism entirely.

### Follow-Up Questions
1. How would you audit every `Role`/`ClusterRole` across the cluster for overly broad `secrets` access, at scale?
2. What's the actual protection etcd encryption at rest provides, given RBAC already gates API-level access?
3. How would migrating to External Secrets Operator change this specific incident's blast radius if it recurred?

### Key Interview Signals
Correctly identifies base64 encoding as never having been a security control, and locates the actual failure precisely in RBAC scoping (and potentially etcd encryption), fixing both rather than either over-trusting or over-reacting to the Secrets mechanism itself.

### Hands-On Connection
[Lab 8 — Security Hardening](../labs/lab-08-security-hardening/).

---

## Question 63: The image that passed the scan but not the audit

### Scenario
A container image passes ECR vulnerability scanning cleanly at build time. Three days later, a new CVE is disclosed affecting a library baked into that same image. The image, already deployed to production, remains running with no automatic re-evaluation.

### Interview Question
Diagnose this gap and design a process that catches newly-disclosed CVEs in already-deployed images.

### Strong Senior-Level Answer
**Initial assessment:** a build-time-only scan is a point-in-time check — it cannot catch a vulnerability disclosed *after* the image was built and scanned, and without a mechanism for ongoing re-evaluation, an image can silently become non-compliant with the organization's vulnerability posture the moment a new CVE affecting its contents is disclosed, with nobody notified.

**Technical reasoning:** ECR's **enhanced scanning** (via Amazon Inspector integration) continuously re-scans images already stored in the registry against updated CVE databases, not just at push time — this is the specific capability needed to catch newly-disclosed CVEs affecting already-pushed (and potentially already-deployed) images, which basic, push-time-only scanning does not provide.

**Investigation process:** confirm whether ECR enhanced scanning is enabled for this repository — if only basic scanning is configured, this exact gap (no re-evaluation after initial push) is expected, structural behavior, not a malfunction.

**Recommended solution:** enable ECR enhanced scanning (continuous re-scanning), and establish an alerting/response process for newly-flagged CVEs on already-deployed images — feeding into a triage process (assess actual exploitability/exposure for this specific deployment, not just CVE severity in the abstract) and a remediation path (rebuild and redeploy with a patched base image/library version).

**Risk controls:** define clear severity-based SLAs for response (e.g., critical CVEs in production images require assessment within 24 hours) so a newly-flagged vulnerability doesn't simply sit in a dashboard unaddressed indefinitely.

**Validation steps:** confirm enhanced scanning is actually active and generating findings by checking for a known, deliberately-outdated test image's expected flagged vulnerabilities, and confirm the alerting pipeline correctly routes new findings to the responsible team.

**Rollback or recovery strategy:** for a genuinely critical, actively-exploited CVE affecting a running production image, the recovery path is an expedited rebuild-and-redeploy (or, if urgent enough, considering the workload's isolation/exposure while remediation is prepared) rather than an infrastructure rollback per se.

**Long-term prevention:** treat continuous image re-scanning (not just build-time scanning) as a required, standing control for any production image registry, with a documented triage/SLA process — this closes the "vulnerable but nobody knows" gap that a point-in-time-only scan leaves open indefinitely.

### Step-by-Step Implementation
```bash
# Enable ECR enhanced scanning (continuous re-scan via Inspector)
aws ecr put-registry-scanning-configuration --scan-type ENHANCED \
  --rules '[{"scanFrequency":"CONTINUOUS_SCAN","repositoryFilters":[{"filter":"*","filterType":"WILDCARD"}]}]'
```

### Under-the-Hood Explanation
Basic ECR scanning runs a vulnerability check once, at image-push time, against the CVE database as it existed at that moment — it has no ongoing awareness of newly-disclosed CVEs affecting already-scanned images. Enhanced scanning, via Amazon Inspector, continuously monitors both the image's contents and the evolving CVE database, generating new findings whenever a previously-clean image's components are later found vulnerable, regardless of how long ago the image was originally pushed.

### Common Weak Answer
"We already scan at build time, that should be sufficient."

### Why the Weak Answer Fails
Build-time scanning only reflects the CVE landscape as it existed at that specific moment — it provides zero protection against vulnerabilities disclosed afterward for images that continue running in production, which is exactly the gap this scenario describes and enhanced/continuous scanning exists to close.

### Follow-Up Questions
1. How would you triage a newly-disclosed critical CVE across potentially many already-deployed images efficiently?
2. What's the actual remediation SLA your organization should target for different CVE severity levels, and how would you enforce it?
3. How does this connect to the image-signing/admission-verification discussion in `docs/security.md` §5 — are they complementary controls?

### Key Interview Signals
Recognizes build-time scanning as a point-in-time check with a specific, structural blind spot for post-deployment CVE disclosure, and designs continuous re-scanning plus a triage/SLA process as the actual fix.

### Hands-On Connection
[Lab 8 — Security Hardening](../labs/lab-08-security-hardening/) and [Lab 12 — CI/CD Pipeline](../labs/lab-12-cicd-pipeline/).

---

## Question 64: The signature nobody checked

### Scenario
An organization implements image signing (via Cosign) as part of its CI pipeline — every image is signed after passing scans. Six months later, a security review finds that no admission-time verification of these signatures actually exists; any image, signed or not, deploys successfully.

### Interview Question
Explain what value, if any, the signing process has actually provided, and fix the gap.

### Strong Senior-Level Answer
**Initial assessment:** per [`docs/security.md`](../docs/security.md) §5, signing an image without admission-time signature *verification* provides essentially no security benefit at deploy time — it creates an auditable record that a specific pipeline signed a specific image, useful for forensic/audit purposes after the fact, but does nothing to *prevent* an unsigned or tampered image from being deployed, since nothing actually checks the signature before allowing deployment.

**Technical reasoning:** the entire point of image signing as a *security control* (versus a compliance/audit artifact) is closing the gap between "we scanned this image" and "we're certain the image running in production is the exact one we scanned" — that gap is only closed if admission-time verification actively rejects any image lacking a valid signature from the trusted signing identity, which this organization never implemented.

**Investigation process:** confirm definitively (as described) that no `ValidatingWebhookConfiguration`/Kyverno `verifyImages` policy currently checks signatures at admission time — and audit whether any unsigned or improperly-signed images have, in fact, been deployed during this six-month gap, which would confirm the practical, not just theoretical, exposure.

**Recommended solution:** implement Kyverno's `verifyImages` policy (or an equivalent Gatekeeper external-data-provider-based check) requiring a valid Cosign signature from the trusted signing identity for every image before admission — closing the actual enforcement gap the six months of signing-without-verification left wide open.

**Risk controls:** roll out signature-verification enforcement in audit mode first (per the standard policy-rollout discipline), since six months of unsigned/unverified deployment history may include currently-running images that would fail a newly-introduced strict verification requirement — identify and address any such gaps before flipping to full enforcement.

**Validation steps:** deliberately attempt to deploy an unsigned test image after implementing verification, confirming it's genuinely rejected — and confirm properly-signed images continue deploying successfully.

**Rollback or recovery strategy:** temporarily relax to audit-only mode if enforcement blocks a legitimate, currently-running image unexpectedly, while that image's signing/build process is corrected.

**Long-term prevention:** treat "is the control we implemented actually enforced, or just recorded" as a standing verification question for any security control introduced — exactly the same lesson as the NetworkPolicy-enforcement-gap pattern (Question 14) and the etcd-encryption-vs-RBAC distinction (Question 62), here applied to image signing specifically: a signature that's never checked provides an audit trail, not a security boundary.

### Step-by-Step Implementation
```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: verify-image-signatures
spec:
  validationFailureAction: Audit   # start in audit mode, per standard rollout discipline
  rules:
    - name: check-signature
      match:
        any:
          - resources: { kinds: [Pod] }
      verifyImages:
        - imageReferences: ["*.dkr.ecr.*.amazonaws.com/*"]
          attestors:
            - entries:
                - keys:
                    publicKeys: |-
                      -----BEGIN PUBLIC KEY-----
                      ... trusted signing identity's public key ...
                      -----END PUBLIC KEY-----
```

### Under-the-Hood Explanation
Cosign signing produces a signature artifact stored alongside the image (typically in the same registry) — this artifact exists independently of whether anything ever checks it; only an admission-time verification policy (Kyverno's `verifyImages`, checked against the trusted public key/attestor) actually gates deployment based on the signature's presence and validity, which is the step this organization had never implemented despite faithfully signing every image for six months.

### Common Weak Answer
"We're signing every image, so we're already protected against supply-chain tampering."

### Why the Weak Answer Fails
Signing alone, without admission-time verification, provides no actual deployment-time protection — this is precisely the gap discovered here; "we sign images" and "we verify signatures before deployment" are two entirely different, independently-necessary steps, and only the second one is an actual security control at deploy time.

### Follow-Up Questions
1. How would you audit the past six months for any unsigned or improperly-signed images that were actually deployed during the enforcement gap?
2. What's the operational risk of `verifyImages` enforcement if the Kyverno webhook itself becomes unavailable (connecting to the `failurePolicy` discussion in Question 33)?
3. How would you extend this verification to also check for a valid SBOM attestation, not just a basic signature?

### Key Interview Signals
Precisely distinguishes signing (an artifact) from verification (an enforcement mechanism), recognizing that six months of the former without the latter provided essentially no deploy-time security benefit, and closes the actual gap with proper admission-time enforcement.

### Hands-On Connection
[Lab 8 — Security Hardening](../labs/lab-08-security-hardening/) and [Lab 13 — Policy as Code](../labs/lab-13-policy-as-code-opa/).

---

## Question 65: The runtime anomaly admission control never sees

### Scenario
A container, having passed every build-time scan and admission-time policy check, is later compromised via an application-level vulnerability during runtime — the attacker spawns a reverse shell inside the already-running container. No alert fires, since nothing is monitoring runtime process behavior.

### Interview Question
Explain why the existing controls didn't catch this, and what closes the gap.

### Strong Senior-Level Answer
**Initial assessment:** per [`docs/security.md`](../docs/security.md) §6, build-time scanning and admission-time policy are both point-in-time or point-of-entry controls — they evaluate the image/manifest *before* the container starts running, and have no visibility whatsoever into what a legitimately-admitted, previously-clean container actually *does* once it's executing; a runtime compromise via an application vulnerability is a fundamentally different failure mode these controls were never designed to catch.

**Technical reasoning:** a reverse shell spawned inside a running container is a runtime process-behavior event — detecting it requires a runtime security tool (Falco or equivalent, using eBPF-based kernel-level observation) actively watching for anomalous behavior (an unexpected child process, an unexpected outbound network connection, a write to a sensitive path) as it happens, a genuinely distinct security layer from anything build-time or admission-time controls provide.

**Investigation process:** confirm no runtime security tooling is currently deployed at all — if this is the case, the absence of any alert is expected, structural behavior (nothing was watching), not a detection failure by a tool that should have caught it.

**Recommended solution:** deploy Falco (or an equivalent eBPF-based runtime security tool) with a ruleset covering common anomalous-behavior patterns (unexpected shell spawns, unexpected outbound connections, sensitive file writes), integrated with the observability/alerting pipeline (per [`docs/observability.md`](../docs/observability.md)) so a genuine runtime anomaly generates an actionable alert.

**Risk controls:** tune the ruleset to the organization's actual workloads to avoid excessive false positives (which would erode trust in the alerting and lead to alerts being ignored) — this requires iteration based on real observed behavior, not a default ruleset applied blindly.

**Validation steps:** deliberately trigger a benign-but-detectable anomalous behavior pattern (e.g., a test shell spawn in a test container) and confirm Falco generates the expected alert, validating the detection pipeline end-to-end before relying on it for genuine incidents.

**Rollback or recovery strategy:** for the actual incident described, standard incident response applies: isolate the compromised pod/node, investigate the actual extent of compromise (what the reverse shell was used for), rotate any credentials the compromised pod had access to (via its IRSA role, importantly, since that's now a potentially-compromised identity), and patch the underlying application vulnerability that enabled the initial compromise.

**Long-term prevention:** treat build-time scanning, admission-time policy, and runtime security monitoring as three genuinely distinct, complementary layers of the full security posture (per [`docs/security.md`](../docs/security.md) §7's full-stack least-privilege framing) — no single layer substitutes for another, and a security program relying only on the first two has a real, demonstrated blind spot for exactly this class of runtime compromise.

### Step-by-Step Implementation
```yaml
# Falco rule example - detect unexpected shell spawned in a container
- rule: Unexpected Shell Spawned in Container
  desc: Detect a shell process spawned inside a container unexpectedly
  condition: spawned_process and container and shell_procs and not proc.pname in (allowed_parent_procs)
  output: "Shell spawned in container (user=%user.name container=%container.name shell=%proc.name parent=%proc.pname)"
  priority: WARNING
```

### Under-the-Hood Explanation
Falco uses eBPF (or a kernel module, in older configurations) to observe system calls at the kernel level in near-real-time, evaluating them against a configured ruleset for known-anomalous patterns — this operates entirely independently of and after any build-time/admission-time check, since it's observing actual runtime behavior of an already-running, already-admitted container, precisely the point in the lifecycle where scanning and admission policy have no further visibility at all.

### Common Weak Answer
"Our image scanning and admission policies should have caught this."

### Why the Weak Answer Fails
This conflates two entirely different security-control categories — scanning/admission policy evaluate the image/manifest before a container runs, while this compromise occurred entirely within a legitimately-admitted, already-running container via an application-level vulnerability, a class of event those controls have no mechanism to observe at all, let alone prevent.

### Follow-Up Questions
1. How would you tune a runtime security ruleset to minimize false positives for your organization's specific, legitimate application behaviors?
2. What's the incident-response process once Falco fires a genuine alert — what are the first three actions?
3. How does this scenario reinforce the "IRSA role may itself be compromised" consideration during incident response?

### Key Interview Signals
Clearly distinguishes runtime security as a genuinely separate control layer from build-time/admission-time controls, and designs both the detection mechanism and the incident-response implications (including credential rotation for the compromised pod's IRSA role) rather than treating this as a gap in the existing (structurally incapable) controls.

### Hands-On Connection
[Lab 8 — Security Hardening](../labs/lab-08-security-hardening/) and [Lab 14 — Troubleshooting and Recovery](../labs/lab-14-troubleshooting-and-recovery/).

---

## Question 66: Least privilege, checked at every layer but one

### Scenario
An architecture review of a workload finds: IRSA correctly scoped, RBAC correctly scoped, Pod Security Standards correctly enforced, NetworkPolicy correctly enforced and verified. The reviewer declares the workload "fully secured." A colleague points out the container image itself still runs as root with no seccomp profile configured.

### Interview Question
Was the colleague's objection valid? Explain why "correctly configured at four layers" doesn't necessarily mean "fully secured."

### Strong Senior-Level Answer
**Initial assessment:** yes, the objection is valid — per [`docs/security.md`](../docs/security.md) §7, a genuinely secure posture requires attention at *every* layer (IAM/IRSA, RBAC, Pod Security Standards, NetworkPolicy, and image/container-level hardening including user/seccomp/capabilities), and getting four layers right doesn't compensate for a gap at a fifth; each layer addresses a distinct category of risk that the others don't cover.

**Technical reasoning:** running as root inside the container (even with all four other layers correctly configured) means a container-escape or privilege-escalation vulnerability within the application itself has a meaningfully larger blast radius than it would running as an unprivileged user — and the absence of a seccomp profile means the container's process has access to the full default syscall surface, rather than a minimal, workload-appropriate subset, an entirely separate risk dimension IRSA/RBAC/PSA/NetworkPolicy don't address at all.

**Investigation process:** review the container image/pod spec specifically for `runAsNonRoot`, `runAsUser`, `allowPrivilegeEscalation`, `readOnlyRootFilesystem`, `capabilities.drop`, and `seccompProfile` settings — none of which are covered by the four already-reviewed layers, confirming this is a genuinely distinct gap, not overlap with what's already been checked.

**Recommended solution:** harden the pod's `securityContext` explicitly: `runAsNonRoot: true` with a specific non-root `runAsUser`, `allowPrivilegeEscalation: false`, `capabilities.drop: ["ALL"]` (adding back only specifically-needed capabilities), `readOnlyRootFilesystem: true` where the application permits it, and an explicit `seccompProfile` (at minimum `RuntimeDefault`, ideally a custom, minimal profile for genuinely sensitive workloads).

**Risk controls:** validate that `runAsNonRoot`/dropped capabilities don't break legitimate application functionality (some applications genuinely need specific capabilities, or write access to specific paths) — test thoroughly rather than applying blindly and discovering breakage in production.

**Validation steps:** confirm the hardened `securityContext` is actually enforced (ideally backed by a Pod Security Standard/admission policy requiring it, not just a one-off manual configuration on this specific pod) and confirm the application continues functioning correctly.

**Rollback or recovery strategy:** if a specific hardening setting breaks functionality, address the specific application dependency (e.g., add back only the one genuinely-needed capability) rather than reverting the entire hardening effort.

**Long-term prevention:** treat this five-layer model (IAM/IRSA, RBAC, Pod Security Standards, NetworkPolicy, container/image-level hardening) as the complete checklist for any "is this workload secured" review, explicitly checking each layer independently rather than declaring victory once a subset is verified correct.

### Step-by-Step Implementation
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 10001
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop: ["ALL"]
  seccompProfile:
    type: RuntimeDefault
```

### Under-the-Hood Explanation
Each of the five layers operates at a genuinely different point in the request/execution path — IRSA/RBAC govern what the workload's *identity* can do against AWS/Kubernetes APIs, Pod Security Standards and NetworkPolicy govern what the *pod spec* and its *network access* are permitted to be, and container-level `securityContext`/seccomp settings govern what the actual *running process* can do at the kernel-syscall level — none of these mechanisms overlaps with or substitutes for another, which is exactly why a gap at any one layer represents a genuinely distinct, uncovered risk.

### Common Weak Answer
"If IAM, RBAC, and network policy are all locked down, that's basically full defense-in-depth."

### Why the Weak Answer Fails
This treats three (or four) layers as "basically" complete without checking the remaining, genuinely distinct layer at all — "basically" defense-in-depth that skips an entire category of control isn't actually defense-in-depth; each layer must be independently verified, since none of them compensates for a gap in another.

### Follow-Up Questions
1. How would you build an automated checklist/scanner verifying all five layers for every workload in a cluster, rather than relying on manual architecture reviews?
2. What's the risk trade-off of `readOnlyRootFilesystem: true` for an application that genuinely needs to write temporary files (connecting back to Question 52's `emptyDir` discussion)?
3. How would you prioritize remediation if you discovered this exact gap across hundreds of existing workloads simultaneously?

### Key Interview Signals
Correctly identifies that security layers are independent and non-substitutable, refusing to declare a workload "fully secured" based on a subset of correctly-configured controls, and completes the full five-layer picture explicitly.

### Hands-On Connection
[Lab 8 — Security Hardening](../labs/lab-08-security-hardening/).

---

## Question 67: The compliance requirement that outran the policy engine

### Scenario
A new compliance mandate requires that every pod's image be provably built from a source commit that passed a specific code-review process, verifiable at admission time. The team's current Kyverno policies check image signatures (Question 64) but have no way to verify anything about the *provenance* of how the image was built.

### Interview Question
Design an approach to satisfy this stronger provenance requirement.

### Strong Senior-Level Answer
**Initial assessment:** signature verification alone (confirming an image was signed by a trusted CI identity) doesn't inherently prove anything about *what process* produced that image — satisfying this stronger requirement needs **attestations** (structured, signed metadata about the build process itself, such as SLSA provenance attestations) rather than just a signature confirming "this image came from our CI system."

**Technical reasoning:** Cosign supports attaching signed **attestations** to an image (in-toto/SLSA provenance format) alongside the basic signature — these attestations can encode specific claims (source repository, commit SHA, whether required review/approval gates were satisfied before build) that Kyverno's `verifyImages` can then check at admission time via its attestation-verification capability, not just the basic signature check already in place.

**Investigation process:** confirm the CI pipeline currently generates any provenance metadata at all, and if not, determine what's needed to generate SLSA-compliant provenance attestations (typically requiring CI pipeline changes to capture and sign build-process metadata, not just the final artifact).

**Recommended solution:** extend the CI pipeline to generate and sign SLSA provenance attestations (capturing source commit, build trigger, and confirmation that required review gates were satisfied) alongside the existing image signature, and extend the Kyverno `verifyImages` policy to additionally verify this attestation's presence and specific claims (e.g., rejecting any image whose attestation doesn't confirm a passed code-review gate).

**Risk controls:** roll out attestation-verification enforcement in audit mode first, exactly like the original signature-verification rollout (Question 64) — this is a new, stronger requirement that existing, already-signed-but-not-attested images won't satisfy, requiring a transition period.

**Validation steps:** deliberately attempt to deploy an image with a valid signature but no (or an insufficient) provenance attestation, confirming it's rejected once enforcement is active, and confirm a properly-attested image deploys successfully.

**Rollback or recovery strategy:** temporarily relax to audit mode if enforcement blocks a legitimate image during the transition, while its build pipeline is updated to generate the required attestation.

**Long-term prevention:** treat provenance attestation (not just basic signing) as the standard, going-forward requirement for any new compliance mandate around build-process integrity, recognizing that "we sign our images" and "we can prove exactly how this image was built and reviewed" are meaningfully different claims requiring different underlying mechanisms.

### Step-by-Step Implementation
```bash
# Generate and attach a signed SLSA provenance attestation (CI pipeline step)
cosign attest --predicate provenance.json --type slsaprovenance --key cosign.key my-registry/my-app:v1.2.3
```
```yaml
# Kyverno policy checking the attestation, not just the basic signature
verifyImages:
  - imageReferences: ["*.dkr.ecr.*.amazonaws.com/*"]
    attestations:
      - predicateType: https://slsa.dev/provenance/v0.2
        conditions:
          - all:
              - key: "{{ builder.id }}"
                operator: Equals
                value: "https://github.com/my-org/my-ci-system"
```

### Under-the-Hood Explanation
An attestation is a separate, signed piece of metadata (distinct from the image's own signature) making specific, structured claims about the build process — Kyverno's attestation-verification capability checks both that the attestation is validly signed by a trusted identity *and* that its claimed content (specific fields like builder identity or review-gate status) matches required conditions, giving admission-time enforcement of process-level claims that a basic image signature alone (which only proves "this specific CI identity vouches for this image," with no further detail) cannot express.

### Common Weak Answer
"We already verify signatures, that should satisfy any compliance requirement about build integrity."

### Why the Weak Answer Fails
Signature verification and provenance-attestation verification answer different questions — "was this image signed by our trusted CI" versus "can we prove exactly what process, including specific review gates, produced this image" — the stronger compliance mandate here specifically requires the latter, which basic signing alone doesn't provide.

### Follow-Up Questions
1. What CI pipeline changes are needed to capture and sign genuinely trustworthy provenance metadata (not just self-reported claims)?
2. How would you handle the transition period for existing images that were signed but never attested?
3. How does SLSA's own maturity-level framework (SLSA 1 through 4) relate to how rigorous this provenance requirement actually needs to be?

### Key Interview Signals
Distinguishes signature verification from provenance-attestation verification as answering genuinely different questions, and designs the CI pipeline and admission-policy changes needed to satisfy a stronger, process-level compliance requirement.

### Hands-On Connection
[Lab 8 — Security Hardening](../labs/lab-08-security-hardening/), [Lab 12 — CI/CD Pipeline](../labs/lab-12-cicd-pipeline/), and [Lab 13 — Policy as Code](../labs/lab-13-policy-as-code-opa/).

---

## Question 68: The security baseline that only existed in one cluster

### Scenario
An organization has thoroughly hardened one flagship EKS cluster (PSA, NetworkPolicy, Kyverno policies, Falco, image verification — everything from this category). A newly-provisioned cluster for a different team starts from a bare Terraform-provisioned state with none of this baseline applied, since "we'll get to it eventually."

### Interview Question
Design a mechanism ensuring every new cluster starts with this security baseline automatically, rather than depending on someone remembering to apply it.

### Strong Senior-Level Answer
**Initial assessment:** manually replicating a security baseline cluster-by-cluster, dependent on someone "getting to it eventually," is exactly the same non-durable, memory-dependent process this repository series consistently flags as insufficient — every question in this category (PSA labels, NetworkPolicy enforcement, image verification, runtime security) represents a control that provides zero protection until it's actually applied, and a new cluster with none of them applied is exactly as exposed as if the entire security program didn't exist.

**Technical reasoning:** the durable fix is treating the entire security baseline as a **GitOps-managed, standardized bootstrap** applied automatically to every new cluster as part of its provisioning process — not a manual checklist executed inconsistently per cluster, but a defined set of manifests/Helm charts/policies that any new cluster's GitOps controller reconciles from day one.

**Investigation process:** enumerate the flagship cluster's actual baseline (PSA defaults, core NetworkPolicy defaults, the standard Kyverno ClusterPolicy set, Falco with its tuned ruleset, image-verification policy) as a concrete, versioned artifact — turning "the security team's tribal knowledge of what a properly-hardened cluster looks like" into an explicit, reproducible specification.

**Recommended solution:** package this baseline as a dedicated Git repository (or a clearly-delineated section of the platform's shared GitOps repo) that every new cluster's ArgoCD/Flux instance is bootstrapped to include automatically as part of cluster provisioning (e.g., an ArgoCD "App of Apps" pattern referencing the baseline, applied immediately after the cluster's Terraform provisioning completes and before any team-specific workloads are onboarded).

**Risk controls:** version the baseline explicitly, so a cluster's baseline version is trackable and any future baseline update can be rolled out deliberately (reviewed, tested) across the fleet rather than clusters silently drifting to different baseline versions over time.

**Validation steps:** for the newly-provisioned cluster, confirm the baseline is genuinely applied and enforced (using the same positive-control testing discipline established throughout this category — attempt to deploy a deliberately non-compliant pod and confirm it's rejected) before any team workload is onboarded to it.

**Rollback or recovery strategy:** if applying the baseline to the new cluster reveals an incompatibility with this team's specific workload needs, address it via a documented, reviewed exception (a namespace-level policy override, clearly justified) rather than skipping the baseline application entirely.

**Long-term prevention:** make baseline-bootstrap application a mandatory, automated, non-skippable step in the cluster-provisioning pipeline itself (e.g., a Terraform module output triggering the GitOps controller's baseline-app bootstrap as part of the same provisioning workflow) — removing the "we'll get to it eventually" option entirely by making the baseline's absence structurally impossible for any cluster that went through the standard provisioning path.

### Step-by-Step Implementation
```yaml
# ArgoCD "App of Apps" - the security baseline bootstrapped automatically for every new cluster
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: security-baseline
spec:
  source:
    repoURL: https://github.com/my-org/platform-security-baseline
    targetRevision: v3.2.0   # explicitly versioned, reviewed before any bump
    path: baseline
  destination:
    server: https://kubernetes.default.svc
  syncPolicy:
    automated: { prune: true, selfHeal: true }
```

### Under-the-Hood Explanation
Once this baseline application is part of the standard cluster-bootstrap sequence (triggered automatically as part of provisioning, not a manual follow-up task), every new cluster's GitOps controller reconciles it identically and continuously — exactly the same self-healing, continuously-enforced guarantee GitOps provides for any other managed resource (per [`docs/cicd-gitops.md`](../docs/cicd-gitops.md) §1-2), applied here to the security baseline itself rather than application workloads.

### Common Weak Answer
"Add a step to the cluster-provisioning runbook reminding the team to apply the security baseline."

### Why the Weak Answer Fails
A runbook reminder is exactly the kind of memory-dependent process that already failed here ("we'll get to it eventually") — the durable fix removes the dependency on anyone remembering or prioritizing a manual step, by making baseline application an automatic, structural part of the provisioning process itself.

### Follow-Up Questions
1. How would you handle updating the baseline across an entire existing fleet of clusters, not just new ones going forward?
2. What governance process would you establish for reviewing and approving baseline changes before they roll out fleet-wide?
3. How would you validate that a cluster claiming to have the baseline applied actually has it fully, correctly enforced, not just partially?

### Key Interview Signals
Recognizes that a security baseline provides no protection until consistently applied, and designs an automated, GitOps-based bootstrap mechanism removing dependency on manual process discipline, rather than a checklist or reminder-based approach.

### Hands-On Connection
[Lab 8 — Security Hardening](../labs/lab-08-security-hardening/) and [Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).
