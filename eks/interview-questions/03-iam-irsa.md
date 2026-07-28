# Category 3: IAM, IRSA, and Kubernetes RBAC

Questions 23–34 of 120. Category weight: 12 questions. Deep-dive reference: [`docs/iam-irsa.md`](../docs/iam-irsa.md).

---

## Question 23: The trust policy that trusted everyone

### Scenario
A security review finds an IRSA role's trust policy conditions only on the OIDC provider ARN, with no namespace/ServiceAccount subject condition. Any pod in the cluster, using any ServiceAccount, can successfully assume this role.

### Interview Question
Explain the exact gap and fix it without breaking the legitimate workload that needs this role.

### Strong Senior-Level Answer
**Initial assessment:** this is precisely the trust-policy gap named in [`docs/iam-irsa.md`](../docs/iam-irsa.md) §2 — conditioning only on the OIDC provider without also checking the `sub` (subject: namespace + ServiceAccount) claim means the trust policy only verifies "this token came from *some* pod in *this cluster*," not "this token came from the *specific* pod this role was intended for."

**Technical reasoning:** the OIDC token's `sub` claim encodes `system:serviceaccount:<namespace>:<serviceaccount-name>` — a trust policy `Condition` block must explicitly match this value (via `StringEquals` on the `<oidc-provider>:sub` key) for the trust relationship to be meaningfully scoped; without it, `sts:AssumeRoleWithWebIdentity` succeeds for a token from any ServiceAccount in the cluster, since all such tokens share the same trusted OIDC provider.

**Investigation process:** confirm exactly which ServiceAccount(s) *should* legitimately assume this role (checking which pods currently do, via CloudTrail's `AssumeRoleWithWebIdentity` events showing the actual calling identity) — this identifies both the correct subject condition to add and any currently-unauthorized pod that's been assuming the role and shouldn't be.

**Recommended solution:** add the explicit `sub` condition scoping the trust policy to the exact namespace/ServiceAccount combination that should be authorized, and (per [`docs/iam-irsa.md`](../docs/iam-irsa.md) §2) also condition on `aud` (audience) to further ensure the token was issued specifically for AWS STS.

**Risk controls:** before tightening the trust policy, confirm via the CloudTrail-derived list that no *other*, currently-unnoticed-but-legitimate workload is also relying on this over-broad trust relationship — tightening it correctly for the intended workload while accidentally breaking an unrelated, undocumented dependency is a real risk worth checking for first.

**Validation steps:** after tightening, confirm the intended ServiceAccount's pods can still successfully assume the role, and confirm a test pod using a *different* ServiceAccount is now correctly denied (`AccessDenied` on `AssumeRoleWithWebIdentity`) — positive-control testing in both directions.

**Rollback or recovery strategy:** revert the trust policy condition if the tightening breaks a legitimate, previously-undiscovered dependency, while that dependency is properly incorporated (either given its own correctly-scoped role, or explicitly added to this one's condition if genuinely appropriate).

**Long-term prevention:** treat trust-policy subject-scoping as a mandatory, reviewed requirement for every new IRSA role — bake a policy-as-code check (via Conftest/OPA against the Terraform plan, mirroring the companion Terraform repository's guidance) verifying every `aws_iam_role` with an OIDC-federated trust policy includes a `sub` condition, catching this gap before it's ever applied.

### Step-by-Step Implementation
```json
{
  "Effect": "Allow",
  "Principal": { "Federated": "arn:aws:iam::ACCOUNT:oidc-provider/oidc.eks.REGION.amazonaws.com/id/CLUSTER_ID" },
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Condition": {
    "StringEquals": {
      "oidc.eks.REGION.amazonaws.com/id/CLUSTER_ID:sub": "system:serviceaccount:payments:payment-processor",
      "oidc.eks.REGION.amazonaws.com/id/CLUSTER_ID:aud": "sts.amazonaws.com"
    }
  }
}
```

### Under-the-Hood Explanation
AWS STS evaluates the trust policy's `Condition` block against the claims actually present in the presented OIDC token — if the condition doesn't check a given claim (like `sub`), STS simply doesn't restrict based on it, meaning any validly-signed token from the trusted OIDC provider (i.e., any pod in the cluster with any ServiceAccount) satisfies the trust policy regardless of which specific ServiceAccount issued it.

### Common Weak Answer
"Just add a comment in the role saying it's only meant for the payment service."

### Why the Weak Answer Fails
A comment is not an enforcement mechanism — it does nothing to actually prevent any other pod in the cluster from assuming this role; only an explicit, evaluated `Condition` block in the trust policy provides real, technical enforcement.

### Follow-Up Questions
1. How would you audit every existing IRSA role in the cluster for this same missing-subject-condition gap at scale?
2. What's the risk if a namespace is later deleted and recreated — does the `sub` condition remain valid?
3. How does EKS Pod Identity's association model avoid needing this same manually-authored condition?

### Key Interview Signals
Identifies the precise missing claim condition (not just "the trust policy is too broad") and designs both an immediate fix and a policy-as-code prevention for future roles.

### Hands-On Connection
[Lab 3 — IRSA and IAM](../labs/lab-03-irsa-and-iam/).

---

## Question 24: The pod that fell back to the node

### Scenario
A security audit finds a workload's ServiceAccount has no IRSA annotation at all, yet the pod is successfully making AWS API calls (S3 GetObject). Nobody remembers configuring this intentionally.

### Interview Question
Explain how this is possible, and assess the actual risk.

### Strong Senior-Level Answer
**Initial assessment:** per [`docs/iam-irsa.md`](../docs/iam-irsa.md) §7, a pod without an IRSA-annotated ServiceAccount silently falls back to the node's own IAM instance-profile role — this pod is almost certainly using the node role's permissions, not a pod-scoped identity at all, and the real risk depends entirely on how broad that node role's permissions are.

**Technical reasoning:** there's no error or warning when a pod lacks IRSA configuration — the AWS SDK inside the pod simply falls through IAM's standard credential-resolution chain to whatever credentials are available in the environment, which on EC2 (including EKS worker nodes) means the instance metadata service's node-role credentials, entirely transparently.

**Investigation process:** confirm via the node's IAM role definition exactly what permissions this pod actually has access to (likely far broader than just S3 GetObject on a specific bucket, if the node role is scoped for general node operation needs like ENI/EBS management) — and check whether *other* pods sharing the same node also implicitly have access to these same broad permissions, since they all share the identical fallback.

**Recommended solution:** create a properly-scoped IRSA role for this specific workload (permissions limited to exactly the S3 access it needs) and annotate its ServiceAccount accordingly — removing its dependency on the node role's broader permission set entirely.

**Risk controls:** after adding IRSA for this workload, confirm the node role itself doesn't need to retain S3 access for any *other* legitimate purpose — if this workload was the only reason the node role had that permission, remove it from the node role too, tightening the shared fallback surface for every other pod on that node as well.

**Validation steps:** after the fix, confirm the pod's AWS calls now use the new IRSA role's credentials (verifiable via CloudTrail's `userIdentity` field showing the assumed role, not the node's instance-profile role) and confirm functionality is unaffected.

**Rollback or recovery strategy:** if the new IRSA role is missing a permission the workload actually needs (discovered via `AccessDenied` errors after cutover), add the specific missing permission to the new role rather than reverting to the node-role fallback.

**Long-term prevention:** audit every ServiceAccount across the cluster for missing IRSA annotations as a standing security review item (a straightforward `kubectl get serviceaccounts -A -o json` query checking for the annotation's absence), and add an admission policy (Kyverno/Gatekeeper) requiring the annotation on any ServiceAccount used by a pod that makes AWS API calls, if that can be reliably identified — or more practically, keep the node role itself as minimal as technically possible so an unnoticed fallback carries lower risk regardless.

### Step-by-Step Implementation
```bash
# Audit: find every ServiceAccount lacking the IRSA annotation
kubectl get serviceaccounts -A -o json | \
  jq -r '.items[] | select(.metadata.annotations["eks.amazonaws.com/role-arn"] == null) | "\(.metadata.namespace)/\(.metadata.name)"'
```
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-app-sa
  namespace: my-namespace
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/my-app-scoped-role
```

### Under-the-Hood Explanation
The AWS SDK's default credential-provider chain checks several sources in order (environment variables, IRSA's projected token/role-ARN environment injection, then finally the EC2 instance metadata service) — a pod without IRSA configuration simply has nothing at the earlier steps in this chain, falling through transparently to the instance metadata service, which returns the node's own instance-profile credentials exactly as it would for any process running directly on that EC2 instance.

### Common Weak Answer
"That's fine, it's working, no need to change anything."

### Why the Weak Answer Fails
"It's working" conflates functional success with security correctness — the pod is running with a shared, likely-broader-than-necessary permission set never intended specifically for it, exactly the least-privilege violation IRSA exists to prevent, and any other pod sharing the node inherits the same exposure.

### Follow-Up Questions
1. How would you build continuous, automated detection for new pods lacking IRSA configuration going forward, not just a one-time audit?
2. What's the node role's minimum necessary permission set, and how would you verify nothing else legitimately depends on it being broader?
3. How does EKS Pod Identity change the ease of avoiding this exact fallback gap?

### Key Interview Signals
Recognizes the silent, no-error nature of the node-role fallback and treats "it's currently working" as orthogonal to "it's correctly scoped," pursuing the least-privilege fix regardless of current functional success.

### Hands-On Connection
[Lab 3 — IRSA and IAM](../labs/lab-03-irsa-and-iam/).

---

## Question 25: Pod Identity or IRSA for the new cluster?

### Scenario
A team standing up a brand-new EKS cluster asks whether to use IRSA or the newer EKS Pod Identity for workload AWS access, since both are viable and their existing older clusters use IRSA.

### Interview Question
Make a recommendation and justify the trade-offs.

### Strong Senior-Level Answer
**Initial assessment:** both are legitimate, per [`docs/iam-irsa.md`](../docs/iam-irsa.md) §3 — this isn't a case where one is deprecated or clearly inferior; the decision should weigh operational simplicity (Pod Identity) against consistency with the existing fleet's established pattern (IRSA) and any tooling/automation already built around IRSA's specific trust-policy structure.

**Technical reasoning:** Pod Identity removes the need for per-cluster OIDC-provider trust-policy plumbing (no cluster-specific OIDC provider ARN/subject-condition boilerplate in every role's trust policy), simplifying role creation and reducing the surface for the exact trust-policy misconfiguration in Question 23 — a genuine operational and security-hygiene improvement. IRSA remains extremely widely supported and is what any existing automation/module library already targets.

**Investigation process:** confirm whether the organization already has significant tooling (Terraform modules, CI/CD checks, policy-as-code rules) built specifically around IRSA's trust-policy structure — if so, factor in the cost of maintaining two parallel patterns (existing clusters on IRSA, new cluster on Pod Identity) versus the benefit of Pod Identity's simplification for this one new cluster.

**Recommended solution:** for a genuinely new cluster with no existing IRSA-specific tooling debt forcing consistency, Pod Identity is generally the better default going forward given its reduced misconfiguration surface (no per-role OIDC-condition boilerplate to get wrong) — but if the organization has substantial existing IRSA-specific automation, adopting Pod Identity only for this one cluster creates a maintenance burden (two patterns to support) that may outweigh the benefit unless a broader, deliberate migration to Pod Identity across the fleet is also planned.

**Risk controls:** whichever is chosen, ensure the organization doesn't end up with an unplanned, inconsistent mix (some clusters/roles on IRSA, others on Pod Identity, with no clear rationale) — make this a deliberate, documented platform decision, not an ad hoc per-cluster choice.

**Validation steps:** for Pod Identity specifically, confirm the EKS Pod Identity Agent add-on is installed and healthy, and confirm a test pod correctly receives scoped credentials via a Pod Identity association before relying on it for production workloads.

**Rollback or recovery strategy:** migrating a workload between IRSA and Pod Identity later is possible (both ultimately provide the pod scoped AWS credentials, just via different plumbing) but requires a deliberate cutover per workload — not a reason to avoid deciding now, but worth knowing it's not entirely free to change later.

**Long-term prevention:** document the organization's chosen default (and the reasoning) for new clusters, and consider whether a broader, planned migration of existing IRSA-based clusters to Pod Identity is worth its own dedicated project versus maintaining IRSA as the standard indefinitely.

### Step-by-Step Implementation
```bash
# EKS Pod Identity - simpler, no per-cluster OIDC trust-policy boilerplate
aws eks create-pod-identity-association \
  --cluster-name my-new-cluster \
  --namespace my-namespace \
  --service-account my-app-sa \
  --role-arn arn:aws:iam::ACCOUNT:role/my-app-scoped-role
```
```json
// The IAM role's trust policy for Pod Identity - simpler, no OIDC-provider-specific conditions needed
{
  "Effect": "Allow",
  "Principal": { "Service": "pods.eks.amazonaws.com" },
  "Action": ["sts:AssumeRole", "sts:TagSession"]
}
```

### Under-the-Hood Explanation
Pod Identity's EKS Pod Identity Agent (a DaemonSet) intercepts credential requests from pods and vends temporary credentials based on the EKS-API-managed association (namespace + ServiceAccount + role), rather than requiring the pod's SDK to perform an `AssumeRoleWithWebIdentity` call against a cluster-specific OIDC provider — removing the OIDC-provider-ARN and subject-condition boilerplate from the trust policy entirely, since the association itself (not the trust policy's own conditions) is what scopes which ServiceAccount can use which role.

### Common Weak Answer
"IRSA is legacy now, always use Pod Identity for everything."

### Why the Weak Answer Fails
IRSA is not being deprecated and remains extremely widely deployed — treating it as obsolete ignores the genuine cost of introducing an inconsistent pattern across a fleet with substantial existing IRSA-specific tooling, a real trade-off this answer dismisses rather than reasoning through.

### Follow-Up Questions
1. How would you plan a fleet-wide migration from IRSA to Pod Identity if the organization eventually decided to standardize on it?
2. What existing IRSA-specific tooling (Terraform modules, policy checks) would need updating to support Pod Identity as well?
3. Are there any workload types where IRSA's trust-policy-based model has a capability Pod Identity's association model doesn't?

### Key Interview Signals
Weighs Pod Identity's genuine simplification against the real cost of introducing a second pattern alongside existing IRSA-based tooling, rather than declaring one universally superior.

### Hands-On Connection
[Lab 3 — IRSA and IAM](../labs/lab-03-irsa-and-iam/).

---

## Question 26: The aws-auth typo that locked everyone out

### Scenario
An engineer manually edits the `aws-auth` ConfigMap to add a new IAM role mapping, introduces a YAML indentation error, and applies the change. Immediately afterward, no IAM principal (including the previously-working ones) can authenticate to the cluster at all.

### Interview Question
Diagnose why a single ConfigMap edit locked out everyone, and design a safer process going forward.

### Strong Senior-Level Answer
**Initial assessment:** the `aws-auth` ConfigMap (per [`docs/iam-irsa.md`](../docs/iam-irsa.md) §4) is a single, monolithic YAML-in-a-ConfigMap structure mapping every IAM principal to cluster access — a syntax error anywhere in it can invalidate the entire mapping, not just the newly-added entry, which is exactly the fragility this legacy mechanism is known for.

**Technical reasoning:** the authenticator component parsing `aws-auth` needs a well-formed ConfigMap to derive *any* IAM-to-Kubernetes-identity mapping — a malformed entry (even just one, due to a YAML structural error like bad indentation) can cause the entire parse to fail or behave unpredictably, effectively breaking authentication for every previously-working principal simultaneously, since there's no partial-failure isolation between individual entries in this mechanism.

**Investigation process:** if any access remains (e.g., a cluster admin with a separate, out-of-band access path, or the ability to fix the ConfigMap via infrastructure automation rather than direct cluster access), inspect the ConfigMap's current content for the structural error; if genuinely locked out entirely, this requires whatever break-glass access mechanism was pre-established (see the companion Terraform repository's break-glass guidance, directly analogous here).

**Recommended solution:** immediately, fix the YAML structural error and reapply (via whatever access path remains available); going forward, migrate to **EKS Access Entries** (per [`docs/iam-irsa.md`](../docs/iam-irsa.md) §4) — an EKS-API-managed mechanism where each access mapping is its own discrete API object, with proper validation on each individual entry and no risk of one entry's error invalidating every other principal's access simultaneously.

**Risk controls:** until fully migrated to Access Entries, never edit `aws-auth` directly via `kubectl edit` — manage it exclusively via Terraform (or another version-controlled, plan-reviewed mechanism) so changes are validated before being applied, and always retain a pre-established break-glass access path independent of `aws-auth`'s own correctness (e.g., a root/administrative AWS credential with a separate emergency-access procedure).

**Validation steps:** after migrating to Access Entries, confirm each individual principal's access can be added/modified/removed independently without any risk to other principals' existing access, and confirm the CloudTrail audit trail now clearly shows who changed which specific access mapping and when.

**Rollback or recovery strategy:** for the immediate lockout, whatever break-glass path exists (a separate root credential, an out-of-band access mechanism established specifically for this failure mode) is the recovery path — this incident is exactly why such a path must be established *before* it's needed, not improvised during the lockout itself.

**Long-term prevention:** fully migrate from `aws-auth` to Access Entries, manage all cluster access mappings exclusively via version-controlled, reviewed Terraform changes (never direct `kubectl edit`), and maintain a documented, tested break-glass access procedure independent of the cluster's own normal authentication path.

### Step-by-Step Implementation
```hcl
# Terraform - EKS Access Entries, one discrete, independently-validated object per principal
resource "aws_eks_access_entry" "engineer" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = "arn:aws:iam::ACCOUNT:role/platform-engineer"
}

resource "aws_eks_access_policy_association" "engineer_admin" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_eks_access_entry.engineer.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope { type = "cluster" }
}
```

### Under-the-Hood Explanation
`aws-auth` is a single ConfigMap parsed as one YAML document by the AWS IAM Authenticator webhook — a malformed structure anywhere in that document can fail the entire parse, since YAML parsing isn't naturally partial/per-entry-isolated. Access Entries, by contrast, are individual EKS API objects, each independently validated by the EKS API at creation/update time — a malformed or incorrect entry simply fails its own API call, with zero effect on any other principal's already-established access entry.

### Common Weak Answer
"Just be more careful editing YAML next time."

### Why the Weak Answer Fails
This relies on manual care as the safeguard against a structurally fragile mechanism — the actual fix (migrating to Access Entries, and never hand-editing `aws-auth` directly regardless) removes the fragility itself rather than hoping future edits are more careful.

### Follow-Up Questions
1. What break-glass access mechanism would you establish specifically for a scenario where the normal IAM-to-cluster-access mapping is broken?
2. How would you migrate an existing, live cluster from `aws-auth` to Access Entries without a disruptive cutover?
3. How does this incident mirror the companion Terraform repository's break-glass access guidance?

### Key Interview Signals
Identifies the structural fragility of the `aws-auth` mechanism itself (not just "there was a typo") and proposes the architecturally superior replacement (Access Entries) alongside a pre-established break-glass path for this exact failure mode.

### Hands-On Connection
[Lab 3 — IRSA and IAM](../labs/lab-03-irsa-and-iam/).

---

## Question 27: "But I have AdministratorAccess in IAM"

### Scenario
An engineer with the `AdministratorAccess` IAM policy attached to their role is confused why they get `Forbidden` errors running `kubectl get pods` against a cluster they should "obviously" have full access to.

### Interview Question
Explain the actual cause and the correct mental model.

### Strong Senior-Level Answer
**Initial assessment:** this is the exact IAM-vs-RBAC layer confusion named in [`docs/iam-irsa.md`](../docs/iam-irsa.md) §5 — broad IAM permissions control what this principal can do against *AWS APIs* generally, but say nothing about what it can do *inside the Kubernetes cluster* once authenticated, which is governed entirely separately by Kubernetes RBAC.

**Technical reasoning:** even with `AdministratorAccess`, this principal needs to (1) be mapped to *some* Kubernetes identity at all (via `aws-auth` or an Access Entry) and (2) have that Kubernetes identity granted appropriate RBAC permissions (`Role`/`ClusterRole` bindings) — `AdministratorAccess` alone satisfies neither of these two independent, Kubernetes-specific requirements.

**Investigation process:** confirm whether this principal has *any* `aws-auth`/Access Entry mapping at all (if not, they can't authenticate to the cluster in the first place, a distinct failure from an RBAC-authorization failure) — and if mapped, confirm what RBAC `Role`/`ClusterRoleBinding` (if any) is associated with their mapped Kubernetes identity.

**Recommended solution:** add both pieces explicitly: an Access Entry (or `aws-auth` mapping) associating this IAM principal with a Kubernetes identity, and an appropriate `ClusterRoleBinding` (e.g., to the built-in `cluster-admin` ClusterRole, if genuinely warranted, or a more scoped role reflecting least-privilege even for administrators) granting that identity the intended in-cluster permissions.

**Risk controls:** resist the temptation to grant `cluster-admin` broadly just because a principal has broad IAM permissions — apply the same least-privilege reasoning to Kubernetes RBAC independently of whatever IAM permission level the principal happens to have, since the two are genuinely separate authorization decisions.

**Validation steps:** after adding the mapping and RBAC binding, confirm `kubectl get pods` (and whatever else is intended) now succeeds, and confirm the granted RBAC scope isn't broader than actually needed for this principal's role.

**Rollback or recovery strategy:** not applicable — this is an access-provisioning gap, not something to roll back.

**Long-term prevention:** document this two-layer model explicitly for the team (IAM: can you talk to the cluster; RBAC: what can you do once you're talking to it) so this exact confusion doesn't recur for the next engineer expecting broad IAM permissions to automatically translate into in-cluster access.

### Step-by-Step Implementation
```hcl
resource "aws_eks_access_entry" "engineer" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = "arn:aws:iam::ACCOUNT:role/senior-engineer"
}

resource "aws_eks_access_policy_association" "engineer_view" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_eks_access_entry.engineer.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"  # least-privilege, not automatically cluster-admin
  access_scope { type = "cluster" }
}
```

### Under-the-Hood Explanation
IAM authenticates *who* is calling the EKS API/cluster endpoint (via `AssumeRole` and the resulting signed request) — but Kubernetes' own RBAC system, entirely independent of IAM, determines *what that authenticated identity is authorized to do* once inside the cluster; these are two distinct authorization systems, sequentially applied but with no automatic mapping of permission level from one to the other.

### Common Weak Answer
"Just grant them cluster-admin since they clearly have high enough IAM permissions to deserve it."

### Why the Weak Answer Fails
This conflates the two layers again in the opposite direction — IAM permission level says nothing about what RBAC scope is actually *appropriate* for this individual's role in the cluster; granting `cluster-admin` reflexively based on IAM breadth, rather than deliberate least-privilege reasoning, is exactly the habit this question is testing for.

### Follow-Up Questions
1. How would you design a standard set of RBAC roles mapped to common IAM-principal categories (engineers, CI, on-call) reflecting appropriate least privilege for each?
2. What's the audit trail difference between `aws-auth` and Access Entries for tracking who granted this access and when?
3. How would you explain this two-layer model concisely to someone new to Kubernetes on AWS?

### Key Interview Signals
Clearly separates IAM (cluster API reachability) from Kubernetes RBAC (in-cluster authorization) as two independent systems, and applies least-privilege reasoning to the RBAC layer independently of the principal's IAM breadth.

### Hands-On Connection
[Lab 3 — IRSA and IAM](../labs/lab-03-irsa-and-iam/).

---

## Question 28: The ServiceAccount token that outlived its pod by a year

### Scenario
A security audit finds a long-lived ServiceAccount token Secret (from an older Kubernetes version's auto-generated token behavior) that was extracted and copied into a CI system's credentials store over a year ago, for a pod that no longer exists. The token is still technically valid.

### Interview Question
Explain the risk, and how modern Kubernetes versions address it structurally.

### Strong Senior-Level Answer
**Initial assessment:** this is exactly the risk [`docs/iam-irsa.md`](../docs/iam-irsa.md) §6 describes — older Kubernetes versions auto-created a long-lived, unbounded ServiceAccount token Secret for every ServiceAccount, which, once extracted, remains valid indefinitely regardless of whether the original pod (or even the ServiceAccount itself, in some cases) still exists, a genuine standing credential-leak risk with no natural expiration.

**Technical reasoning:** modern Kubernetes (1.24+) no longer auto-creates these long-lived Secret-based tokens by default — ServiceAccount tokens are instead requested on-demand via the `TokenRequest` API, short-lived and audience-scoped, automatically rotated by the kubelet for actively-running pods, with no equivalent long-lived artifact to accidentally extract and reuse indefinitely.

**Investigation process:** confirm exactly which extracted token this is, whether it's still accepted by the API server (test carefully, in a way that doesn't itself constitute unauthorized access), and audit the CI system's credentials store for any *other* similarly-extracted long-lived tokens that might exist from the same era.

**Recommended solution:** revoke/delete the specific long-lived token Secret (and, if the associated ServiceAccount still exists and is in active legitimate use, verify workloads using it have since transitioned to the modern, short-lived `TokenRequest`-based token model rather than depending on the old Secret specifically); remove the extracted copy from the CI credentials store entirely, replacing whatever it was used for with a properly-scoped IRSA/Pod Identity-based or, if genuinely needed for direct cluster API access, a `TokenRequest`-based short-lived credential appropriate to the CI use case.

**Risk controls:** audit for any other similarly-long-lived, manually-extracted credentials across the organization's CI/automation systems — this exact pattern (a convenient, long-lived credential extracted once and never revisited) is a recurring risk category independent of this specific token.

**Validation steps:** confirm the deleted token Secret is genuinely no longer accepted by the API server, and confirm whatever legitimate function the CI system was performing with it continues to work correctly via its replacement credential mechanism.

**Rollback or recovery strategy:** if deleting the old token breaks a still-active legitimate dependency discovered only after the fact, provision the correct modern replacement (rather than recreating the old long-lived pattern) for that dependency.

**Long-term prevention:** audit for any remaining long-lived ServiceAccount token Secrets across the cluster (a leftover artifact possible even on modern Kubernetes versions if something explicitly creates one) as a standing security review item, and ensure any Kubernetes-version upgrade that introduces the modern token model is actually leveraged by migrating away from any legacy long-lived tokens still in active use, not just leaving them running alongside the new default.

### Step-by-Step Implementation
```bash
# Find any long-lived ServiceAccount token Secrets still present
kubectl get secrets -A --field-selector type=kubernetes.io/service-account-token

# Delete the identified stale, extracted token's Secret
kubectl delete secret <extracted-token-secret-name> -n <namespace>
```

### Under-the-Hood Explanation
Prior to Kubernetes 1.24, every ServiceAccount automatically got a companion Secret containing a long-lived, non-expiring JWT token, mounted into any pod using that ServiceAccount — since 1.24, tokens are instead requested on-demand via the `TokenRequest` API with a bounded lifetime (default one hour, auto-renewed by the kubelet for the pod's actual lifetime), meaning there's no longer a standing, extractable, indefinitely-valid artifact of the same kind — a token that is extracted today expires naturally within its short bound, dramatically reducing (though not eliminating) the value of extracting and storing one long-term.

### Common Weak Answer
"Tokens don't expire so this isn't really different from a normal API key, treat it the same way."

### Why the Weak Answer Fails
This misses that the *entire point* of the modern token model is eliminating the standing, indefinitely-valid credential category this old-style token represents — treating it as "just an API key" ignores that its indefinite validity is specifically the security regression the platform has since moved away from, and the correct response is migrating off it, not just managing it more carefully.

### Follow-Up Questions
1. How would you detect if any workload is still depending on the legacy long-lived token model after a cluster upgrade to a modern Kubernetes version?
2. What's the actual default token lifetime under the `TokenRequest` model, and how is it kept fresh for a long-running pod?
3. How does this scenario relate to the companion Ansible repository's guidance on short-lived, audience-scoped tokens replacing long-lived credentials generally?

### Key Interview Signals
Recognizes the specific structural improvement modern Kubernetes token handling provides (bounded lifetime, no standing extractable artifact) and pursues migration off the legacy pattern rather than just managing the old credential more carefully.

### Hands-On Connection
[Lab 3 — IRSA and IAM](../labs/lab-03-irsa-and-iam/).

---

## Question 29: One role, five accounts, one pod

### Scenario
A platform team needs a single set of Kubernetes controllers (running in one "hub" cluster) to manage resources across five separate AWS accounts (one per business unit), each with its own IAM boundary.

### Interview Question
Design the cross-account access architecture for this pod-based automation.

### Strong Senior-Level Answer
**Initial assessment:** this is the pod-level equivalent of the companion Ansible repository's [Question 42](../../ansible/interview-questions/04-modules-plugins.md#question-42-one-playbook-five-aws-accounts) cross-account automation-identity pattern — a central IRSA/Pod Identity role in the hub cluster, chained via a second-hop `sts:AssumeRole` into each target account's own scoped role, per [`docs/iam-irsa.md`](../docs/iam-irsa.md) §8.

**Technical reasoning:** the pod's IRSA (or Pod Identity) role in the hub cluster's account establishes its base identity via the normal trust chain; that role's own permissions are then limited to *only* `sts:AssumeRole` against five specific, named target-account roles (one per business unit), each of those target roles independently scoped to only the specific permissions that business unit's automation actually needs — no single credential grants broad access across all five accounts simultaneously.

**Investigation process:** confirm exactly what actions the controller needs to perform in each target account (informed by each business unit's actual requirements, which may differ) — this determines each target-account role's specific least-privilege policy, rather than provisioning five identical, broadly-scoped roles for convenience.

**Recommended solution:** one IRSA/Pod Identity role in the hub cluster's account, with an inline policy allowing `sts:AssumeRole` against exactly the five target-account role ARNs (and nothing else); each target-account role's own trust policy conditioned specifically on the hub role's ARN (not open to any principal), and each target role's permission policy scoped to that specific business unit's actual needs.

**Risk controls:** ensure the hub role's `AssumeRole` permission is an explicit allowlist of exactly the five target-account role ARNs — never a wildcard permission that would allow assuming *any* role matching a naming pattern across those accounts, which would undermine the whole point of per-account scoping.

**Validation steps:** confirm the controller successfully performs its intended actions in each of the five accounts, and confirm (via a deliberate test) that it cannot assume any role in the five accounts *other than* the specific one designated for each, nor any role in an unrelated sixth account.

**Rollback or recovery strategy:** if a specific target account's role needs a permission adjustment, that account's role can be updated independently without affecting the hub role or any other target account's role — a well-isolated blast radius by design.

**Long-term prevention:** as new business units/accounts are onboarded, extend this pattern (a new target-account role, added to the hub role's explicit allowlist) rather than ever creating a single broad, cross-account credential as a shortcut for convenience.

### Step-by-Step Implementation
```json
// Hub role's own permission policy - explicit allowlist, not a wildcard
{
  "Effect": "Allow",
  "Action": "sts:AssumeRole",
  "Resource": [
    "arn:aws:iam::111111111111:role/hub-automation-target-role",
    "arn:aws:iam::222222222222:role/hub-automation-target-role",
    "arn:aws:iam::333333333333:role/hub-automation-target-role",
    "arn:aws:iam::444444444444:role/hub-automation-target-role",
    "arn:aws:iam::555555555555:role/hub-automation-target-role"
  ]
}
```
```json
// Each target account's role trust policy - scoped to the specific hub role ARN only
{
  "Effect": "Allow",
  "Principal": { "AWS": "arn:aws:iam::HUB_ACCOUNT:role/hub-controller-irsa-role" },
  "Action": "sts:AssumeRole"
}
```

### Under-the-Hood Explanation
This is a two-hop credential chain: the pod's IRSA/Pod Identity role is established via the standard OIDC trust chain in the hub account, then that role's own (narrowly-scoped) permissions allow a second `sts:AssumeRole` call into each target account — with each target account's trust policy independently restricting which principal (specifically the hub role's ARN) can assume it, giving genuine per-account isolation even though one central pod-based controller orchestrates actions across all five.

### Common Weak Answer
"Just give the hub role admin access in all five accounts so the controller can do whatever it needs."

### Why the Weak Answer Fails
This is exactly the broad, shared-credential-for-everything anti-pattern this repository series consistently warns against — a single compromised or misbehaving controller pod would then have unrestricted access across five separate business units' AWS accounts, an enormous, avoidable blast radius compared to the per-account-scoped role-chaining design.

### Follow-Up Questions
1. How would you extend this pattern if a sixth business unit/account is onboarded later?
2. What's the audit-trail visibility difference (via CloudTrail) for this chained-role design versus a single broad credential?
3. How would you handle a business unit needing genuinely different permission scopes for different parts of the same controller's work?

### Key Interview Signals
Designs a genuinely least-privilege, per-account-scoped chained-role architecture rather than a single broad credential, explicitly naming the parallel to the companion Ansible repository's equivalent cross-account automation-identity pattern.

### Hands-On Connection
[Lab 3 — IRSA and IAM](../labs/lab-03-irsa-and-iam/) and [Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).

---

## Question 30: The RoleBinding that outlived the project

### Scenario
A `RoleBinding` granting a contractor's IAM-mapped identity edit access to a production namespace was created for a three-month project. The project ended fourteen months ago; the binding is still active, and the contractor's IAM credentials (per a separate audit) are also still technically valid.

### Interview Question
What's the actual failure here, and how do you design against it recurring?

### Strong Senior-Level Answer
**Initial assessment:** this is an access-lifecycle management gap, not a technical misconfiguration — the `RoleBinding` and the underlying IAM credentials were both correctly scoped and functioning exactly as configured; the failure is that neither was tied to any expiration or offboarding process reflecting the project's actual, known three-month duration.

**Technical reasoning:** Kubernetes `RoleBinding`s (and IAM role/user credentials) have no inherent time-bound expiration unless explicitly designed with one — a binding created for a temporary need persists indefinitely by default, entirely dependent on someone remembering to remove it when the need ends, exactly the "remember to be careful" non-control this repository series consistently flags as insufficient.

**Investigation process:** confirm the actual current access this contractor's identity retains (both the Kubernetes RBAC scope and whatever AWS-level access their credentials still permit) and assess whether any access occurred during the fourteen-month gap that shouldn't have (a genuine incident-investigation question, not just a cleanup task).

**Recommended solution:** immediately revoke both the `RoleBinding` and the underlying IAM credentials; going forward, tie any time-bound access grant (contractor, temporary project work) to an explicit, tracked expiration — either a calendar-based offboarding checklist with a hard reminder, or, more robustly, a policy/automation that periodically audits for and flags any access grant associated with an inactive/expired external identity.

**Risk controls:** for any external or temporary identity granted cluster/AWS access, require the grant to be tied to a specific, tracked end date at creation time — never an open-ended grant for a known-temporary need.

**Validation steps:** after revocation, confirm the contractor's identity can no longer authenticate to the cluster or perform any AWS action, and audit for any other similarly-stale grants from other past temporary engagements that might share this same gap.

**Rollback or recovery strategy:** not applicable — this is a revocation, not a change requiring rollback consideration.

**Long-term prevention:** implement a periodic (e.g., quarterly) access review specifically checking for RBAC bindings and IAM grants associated with contractors/external identities whose engagement has ended, and consider automating detection (e.g., correlating HR/vendor-management offboarding events with a corresponding access-revocation checklist) rather than relying on manual memory for the specific timing of a temporary engagement's end.

### Step-by-Step Implementation
```bash
# Immediate revocation
kubectl delete rolebinding contractor-edit-access -n production
aws iam delete-role --role-name contractor-temporary-role   # or deactivate access keys, per how they authenticated
```
```bash
# Standing audit: find RBAC bindings referencing known-external/contractor identity patterns
kubectl get rolebindings,clusterrolebindings -A -o json | \
  jq -r '.items[] | select(.subjects[]?.name | test("contractor|external")) | "\(.metadata.namespace // "cluster")/\(.metadata.name)"'
```

### Under-the-Hood Explanation
Kubernetes RBAC bindings and IAM role/credential grants are both purely declarative, persistent objects with no built-in awareness of "this was meant to be temporary" — they remain fully valid and enforced until explicitly deleted/revoked by an external process, meaning any time-bound access intent must be operationalized through an actual process or automation, since neither Kubernetes nor IAM natively expires access based on an unstated, informal time expectation.

### Common Weak Answer
"We'll just remember to clean up contractor access when their project ends."

### Why the Weak Answer Fails
This is precisely the informal, memory-dependent process that failed here for fourteen months — a durable fix requires either an enforced expiration mechanism or a tracked, periodic audit process, not renewed reliance on the same kind of manual remembering that already didn't work.

### Follow-Up Questions
1. How would you design an automated system tying access grants to an actual, enforced expiration date?
2. What would you investigate regarding potential unauthorized access during the fourteen-month gap?
3. How would this same lifecycle-management gap apply to IRSA roles created for a temporary migration or one-off project, not just human contractor access?

### Key Interview Signals
Frames this as an access-lifecycle process gap rather than a one-off cleanup task, and designs a systematic, periodic-review or automation-based prevention rather than relying on improved manual diligence.

### Hands-On Connection
[Lab 3 — IRSA and IAM](../labs/lab-03-irsa-and-iam/) and [Lab 8 — Security Hardening](../labs/lab-08-security-hardening/).

---

## Question 31: The custom role that granted secrets read to everyone

### Scenario
A custom `ClusterRole` intended to give a monitoring service read access to `pods` and `configmaps` cluster-wide was written with an overly broad `resources: ["*"]` wildcard instead of listing specific resource types, inadvertently also granting cluster-wide read access to `secrets`.

### Interview Question
Diagnose the risk and design the correct, minimal role.

### Strong Senior-Level Answer
**Initial assessment:** a `resources: ["*"]` wildcard in a `ClusterRole` rule grants access to every resource type in the specified API group, including `secrets` — a real, common RBAC-authoring mistake where the intent ("give broad read access to a few specific, low-sensitivity resource types") is expressed far more broadly than intended via an overly convenient wildcard.

**Technical reasoning:** unlike NetworkPolicy's inert-if-unenforced failure mode, RBAC wildcards are actively, immediately enforced exactly as written — this isn't a silent gap needing external verification to discover, but a directly consequential over-grant the moment the `ClusterRoleBinding` is applied, since any identity bound to this role now has cluster-wide `secrets` read access whether intended or not.

**Investigation process:** review the `ClusterRole`'s actual applied permissions (`kubectl auth can-i --list --as=system:serviceaccount:monitoring:monitoring-sa`) to confirm exactly what this over-broad wildcard currently grants, and check (via audit logs, if available) whether `secrets` were actually read by this identity beyond what was intended — determining whether this is a latent over-grant or one that's already been exploited/used, even if unintentionally.

**Recommended solution:** rewrite the rule to explicitly enumerate only the intended resource types (`pods`, `configmaps`), removing the wildcard entirely — least privilege expressed precisely rather than convenient over-inclusion.

**Risk controls:** treat any RBAC rule using a `resources: ["*"]` (or similarly broad `apiGroups: ["*"]`) wildcard as a required manual-review flag in any RBAC change process — these wildcards are convenient to write but almost always broader than the actual intent, exactly as happened here.

**Validation steps:** after tightening, confirm `kubectl auth can-i get secrets --as=system:serviceaccount:monitoring:monitoring-sa` now correctly returns "no," and confirm the monitoring service's actual intended functionality (reading pods/configmaps) is unaffected.

**Rollback or recovery strategy:** if the monitoring service turns out to need some additional, currently-uncovered resource type after tightening, add that specific resource type explicitly rather than reintroducing a wildcard.

**Long-term prevention:** add an automated policy check (via `kyverno test`/`gator test`, or a simple CI-level YAML lint rule) flagging any RBAC `Role`/`ClusterRole` manifest using a `resources: ["*"]` wildcard for mandatory human review before merge — catching this exact mistake pattern before it's ever applied.

### Step-by-Step Implementation
```yaml
# Before (over-broad)
rules:
  - apiGroups: [""]
    resources: ["*"]        # accidentally includes secrets
    verbs: ["get", "list", "watch"]

# After (precisely scoped)
rules:
  - apiGroups: [""]
    resources: ["pods", "configmaps"]   # explicit, no wildcard
    verbs: ["get", "list", "watch"]
```

### Under-the-Hood Explanation
Kubernetes RBAC evaluates rules exactly as declared, with no implicit narrowing based on "probable intent" — a `resources: ["*"]` wildcard in the core API group (`apiGroups: [""]`) genuinely matches every resource type in that group, `secrets` included, and the API server's authorization check for any `secrets` request will find this rule matches and permits it, exactly as written, regardless of whether that was the role author's actual intention.

### Common Weak Answer
"The wildcard is more convenient and future-proof if we need more resource types later."

### Why the Weak Answer Fails
"Convenient and future-proof" is exactly the reasoning that produces an unintended, immediately-consequential over-grant — least privilege means expressing exactly the current, intended scope and explicitly widening it later if genuinely needed, not defaulting to broad access for hypothetical future convenience.

### Follow-Up Questions
1. How would you audit every existing `ClusterRole` in the cluster for similarly over-broad wildcard usage?
2. What's the difference in risk between a `resources: ["*"]` wildcard and an `apiGroups: ["*"]` wildcard?
3. How would you design a CI-level check catching this pattern before merge, specifically?

### Key Interview Signals
Recognizes RBAC wildcards as immediately, actively consequential (not a silent gap needing separate discovery) and pursues precise, explicit least-privilege scoping over convenient broad grants.

### Hands-On Connection
[Lab 3 — IRSA and IAM](../labs/lab-03-irsa-and-iam/) and [Lab 13 — Policy as Code](../labs/lab-13-policy-as-code-opa/).

---

## Question 32: The break-glass path that only existed on paper

### Scenario
During a genuine production incident, the on-call engineer discovers that the documented "break-glass" cluster-admin access procedure references an IAM role that was deleted eight months ago during an unrelated cleanup, with no one having verified the break-glass path still worked since.

### Interview Question
Design a break-glass access process for EKS that won't silently rot like this.

### Strong Senior-Level Answer
**Initial assessment:** an untested break-glass procedure is not meaningfully different from having no break-glass procedure at all — exactly the "recovery tool can't share fate with what it's recovering, and also can't just be assumed to still work" lesson threaded through this repository series, here manifesting as a documented-but-silently-broken emergency path.

**Technical reasoning:** break-glass access for EKS typically means a pre-provisioned, tightly-controlled IAM role or credential with cluster-admin-equivalent access (via a dedicated Access Entry), reserved specifically for emergency use and normally unused — but "normally unused" is exactly the condition under which unrelated cleanup work (deleting an apparently-unused IAM role) can silently break it without anyone noticing, since nothing exercises it during normal operations.

**Investigation process:** for the immediate incident, identify what alternative access path (if any) remains available, and separately, once the incident is resolved, conduct a full audit of every component the break-glass procedure depends on (the IAM role/credential, its Access Entry mapping, any required MFA/approval workflow) to confirm what else might have silently rotted.

**Recommended solution:** re-provision the break-glass IAM role/Access Entry, and — critically — establish a **periodic, scheduled test** of the entire break-glass path (e.g., quarterly, in a controlled, non-emergency context) as a standing operational requirement, exactly like a disaster-recovery drill for any other critical-but-rarely-used recovery mechanism.

**Risk controls:** tag/document the break-glass role clearly enough that future unrelated cleanup work recognizes it as a deliberately-provisioned, load-bearing emergency resource rather than an apparently-unused, safe-to-delete artifact — the exact miscategorization that caused this incident.

**Validation steps:** the scheduled test itself is the validation — actually assume the break-glass role/credential and confirm cluster-admin access works end-to-end, not just checking that the IAM role object still exists (existence isn't the same as functional correctness for its intended purpose).

**Rollback or recovery strategy:** not applicable — this is establishing a resilience process, not a change requiring its own rollback.

**Long-term prevention:** add the break-glass path's periodic test to the same operational calendar as other standing reliability practices (DR drills, backup-restore tests), and require any infrastructure cleanup process to explicitly check a resource-tagging convention (or similar) marking deliberately-provisioned emergency-access resources as excluded from "unused resource" cleanup sweeps.

### Step-by-Step Implementation
```hcl
resource "aws_iam_role" "break_glass" {
  name = "eks-break-glass-cluster-admin"
  tags = {
    Purpose  = "break-glass-emergency-access"
    DoNotDelete = "true"   # explicit signal for any automated/manual cleanup process
  }
  # ... assume-role policy requiring MFA and restricted to specific, named on-call identities
}

resource "aws_eks_access_entry" "break_glass" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_iam_role.break_glass.arn
}
```
```bash
# Scheduled quarterly test (run in a controlled window, not a real incident)
aws sts assume-role --role-arn arn:aws:iam::ACCOUNT:role/eks-break-glass-cluster-admin --role-session-name quarterly-test
kubectl get pods -A   # confirm actual cluster-admin access works end-to-end
```

### Under-the-Hood Explanation
A break-glass role that's never exercised has no built-in mechanism forcing anyone to notice if a dependency (the role itself, its Access Entry, an MFA configuration) silently breaks — only an actual, periodic assume-and-verify test surfaces this class of rot before a real incident does, since IAM/EKS provide no automatic notification when a rarely-used credential's supporting infrastructure is removed by unrelated cleanup elsewhere in the account.

### Common Weak Answer
"Document the break-glass procedure clearly so people know what to do."

### Why the Weak Answer Fails
Documentation describes an intended process but does nothing to verify the process still actually works — this incident occurred despite (presumably) having documentation; only an actual, periodic functional test catches silent rot in an emergency-only path before a real emergency does.

### Follow-Up Questions
1. How would you balance the security risk of a standing, always-provisioned break-glass credential against the availability risk of not having one ready?
2. What approval/MFA workflow would you require for break-glass use, balancing speed-of-access during a real incident against misuse prevention?
9. How would you extend this "periodically test what you assume works" discipline to other rarely-exercised recovery mechanisms in this platform (e.g., DR failover, Velero restore)?

### Key Interview Signals
Recognizes that an untested emergency path is functionally equivalent to no emergency path, and designs a periodic, scheduled functional test rather than relying on documentation or infrequent incidental exercise.

### Hands-On Connection
[Lab 3 — IRSA and IAM](../labs/lab-03-irsa-and-iam/) and [Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).

---

## Question 33: The webhook that needed a secret it couldn't reach

### Scenario
A custom validating admission webhook's own pod needs to fetch a signing key from AWS Secrets Manager at startup (to verify signed image references, per the supply-chain guidance in `docs/security.md`). During a cluster upgrade, the webhook's ServiceAccount's IRSA role is accidentally left un-migrated to a new naming convention adopted for all other roles, and the webhook pod crash-loops on startup, unable to fetch its signing key — and because it's a `failurePolicy: Fail` webhook, this blocks all admission-controlled resource creation cluster-wide.

### Interview Question
Diagnose the cascading failure and design the fix, including how you'd prevent this exact blast radius in the future.

### Strong Senior-Level Answer
**Initial assessment:** this combines two issues from earlier in this category — an IRSA misconfiguration (Question 24's fallback-or-failure risk, here manifesting as outright failure rather than a silent fallback, since the webhook explicitly requires the Secrets Manager fetch to succeed) with the admission-webhook availability dependency named in [`docs/security.md`](../docs/security.md) §4 and [`docs/governance-policy.md`](../docs/governance-policy.md) §2 — a `failurePolicy: Fail` webhook's own health (including its IRSA-dependent startup sequence) becomes a cluster-wide availability dependency.

**Technical reasoning:** the webhook's crash-loop, caused by its IRSA role misconfiguration preventing its Secrets Manager fetch from succeeding, means the webhook is never actually ready to serve admission requests — and with `failurePolicy: Fail`, the API server blocks (rather than permits through) any admission-controlled resource operation it can't reach the webhook to evaluate, cascading a single pod's IRSA misconfiguration into a cluster-wide inability to create or update any matched resource.

**Investigation process:** confirm via the webhook pod's own logs the specific IRSA-related failure (an `AccessDenied` or credential-resolution error fetching from Secrets Manager), and confirm via the ServiceAccount's annotation that it indeed references the old, un-migrated role ARN.

**Recommended solution:** immediately fix the ServiceAccount's IRSA annotation to reference the correct, migrated role ARN, restoring the webhook to a healthy state and unblocking cluster-wide admission; separately, evaluate whether this specific webhook's criticality genuinely warrants `failurePolicy: Fail` (protecting against a bypassed image-signature check) against the demonstrated availability risk (a mundane IRSA misconfiguration now cascades cluster-wide) — a deliberate, reasoned choice rather than a default.

**Risk controls:** for any `failurePolicy: Fail` webhook, ensure its own health (and every dependency in its startup path, including IRSA) is monitored with the same or greater rigor as any other cluster-critical component, precisely because its own availability is now everyone else's availability too.

**Validation steps:** after the fix, confirm the webhook pod starts healthy and successfully fetches its signing key, and confirm previously-blocked resource operations now succeed normally cluster-wide.

**Rollback or recovery strategy:** if the IRSA fix isn't immediately available, consider temporarily switching this specific webhook to `failurePolicy: Ignore` as an emergency mitigation to restore cluster-wide availability (accepting the temporary risk of unverified image signatures) while the underlying IRSA issue is properly fixed — a deliberate, temporary, and explicitly reasoned trade-off, not a permanent silent downgrade.

**Long-term prevention:** whenever adopting a new IRSA role-naming convention (or any IRSA role migration), include every existing IRSA-dependent component — especially any `failurePolicy: Fail` admission webhook — in the migration's explicit checklist, verified individually, rather than assuming a global rename sweep caught every reference; and add monitoring/alerting specifically on admission-webhook health as a standing, high-priority signal given its outsized blast radius.

### Step-by-Step Implementation
```bash
# Diagnose - webhook pod logs show the IRSA/Secrets Manager fetch failure
kubectl logs -n admission-system deployment/image-signature-webhook

# Fix - correct the ServiceAccount's IRSA annotation to the migrated role ARN
kubectl annotate serviceaccount image-signature-webhook -n admission-system \
  eks.amazonaws.com/role-arn=arn:aws:iam::ACCOUNT:role/new-naming-convention-webhook-role --overwrite

# Restart to pick up the corrected credential path
kubectl rollout restart deployment/image-signature-webhook -n admission-system
```

### Under-the-Hood Explanation
The webhook pod's own startup sequence depends on successfully assuming its IRSA role to fetch a required secret — if that assumption fails (due to a stale/incorrect role ARN annotation), the pod never reaches a ready state, and the `ValidatingWebhookConfiguration`'s `failurePolicy: Fail` setting means the API server treats an unreachable/not-ready webhook as a reason to reject (not permit) any matched admission request, directly propagating this one pod's credential misconfiguration into a cluster-wide admission-blocking incident.

### Common Weak Answer
"Just switch failurePolicy to Ignore permanently so this can't happen again."

### Why the Weak Answer Fails
This "fixes" the availability risk by permanently discarding the security guarantee the webhook exists to provide (verified image signatures) — the better answer treats `Fail` vs. `Ignore` as a genuine, ongoing trade-off decision per policy criticality (per [`docs/governance-policy.md`](../docs/governance-policy.md) §2), using `Ignore` only as a deliberate, temporary emergency measure, not a permanent workaround for an IRSA configuration mistake that should simply be fixed and prevented from recurring.

### Follow-Up Questions
1. How would you monitor admission-webhook health specifically, given its outsized cluster-wide blast radius compared to a typical workload's health?
2. What would a safer IRSA role-migration checklist look like to catch every dependent component, not just this one webhook?
3. How would you design a canary/staged rollout for any change to a `failurePolicy: Fail` webhook's own configuration or dependencies?

### Key Interview Signals
Connects an IRSA misconfiguration to its outsized cascading effect via the admission-webhook failure-policy mechanism, and reasons explicitly about the `Fail`-vs-`Ignore` trade-off rather than defaulting to either extreme.

### Hands-On Connection
[Lab 3 — IRSA and IAM](../labs/lab-03-irsa-and-iam/) and [Lab 13 — Policy as Code](../labs/lab-13-policy-as-code-opa/).

---

## Question 34: Auditing IRSA at fleet scale

### Scenario
A platform team responsible for thirty EKS clusters across the organization is asked: "prove that every IRSA role across our entire fleet follows least-privilege and correct trust-policy scoping" ahead of a compliance audit.

### Interview Question
Design a scalable approach to this — not a manual, cluster-by-cluster review.

### Strong Senior-Level Answer
**Initial assessment:** manually reviewing IRSA configuration across thirty clusters is neither scalable nor reliable — this needs a systematic, automated auditing approach checking every IRSA role against the specific known-failure patterns already established in this category (Questions 23, 24, 31): trust-policy subject-scoping, unused-but-still-broad node-role fallback exposure, and RBAC wildcard over-grants.

**Technical reasoning:** every IRSA role's trust policy and every ServiceAccount's IRSA annotation (or its absence) is programmatically inspectable via the IAM and Kubernetes APIs respectively — a fleet-wide audit script can systematically enumerate every cluster's ServiceAccounts, cross-reference against their associated IAM roles' trust policies and permission policies, and flag every instance of the known-risky patterns automatically, rather than relying on a human reviewer's attention across thirty separate clusters.

**Investigation process:** define the concrete, checkable criteria first (does this role's trust policy include a `sub` condition scoped to a specific namespace/ServiceAccount; does this ServiceAccount lack an IRSA annotation entirely, implying node-role fallback; does this role's permission policy include any overly-broad wildcard) — turning "prove least privilege" into a set of specific, automatable checks rather than a vague, unfalsifiable claim.

**Recommended solution:** build (or adopt an existing tool for) a fleet-wide scanning script: for each of the thirty clusters, enumerate all ServiceAccounts and their IRSA annotations, cross-reference each associated IAM role's trust policy for proper subject-scoping and its permission policy for wildcard usage via IAM Access Analyzer's policy-analysis capability, and produce a consolidated report flagging every finding, categorized by severity (missing IRSA entirely > missing trust-policy subject condition > overly-broad permission policy).

**Risk controls:** run this as a read-only audit first (no automated remediation) given the compliance-driven, review-focused nature of the request — any remediation of findings should go through the same careful process (CloudTrail-informed least-privilege derivation, from Question 47/companion-repo guidance) as any other IAM tightening, not an automated blanket fix that risks breaking legitimate functionality.

**Validation steps:** spot-check the automated scan's findings against a manual review of a sample of flagged (and unflagged) roles to confirm the scan's accuracy before trusting its full fleet-wide output for the compliance submission.

**Rollback or recovery strategy:** not applicable — this is an audit/reporting exercise; any subsequent remediation would follow its own separate, carefully-validated rollout process.

**Long-term prevention:** operationalize this scan as a recurring (not one-time) scheduled job, feeding results into a dashboard/ticketing system so IRSA configuration drift across the fleet is caught continuously going forward, not just once for this specific compliance audit — and incorporate the same checks into pre-merge CI policy tests (per [`docs/governance-policy.md`](../docs/governance-policy.md) §4) so new misconfigurations are caught before they're ever deployed to any of the thirty clusters.

### Step-by-Step Implementation
```bash
# Fleet-wide IRSA audit (conceptual sketch)
for cluster in $(cat clusters.txt); do
  aws eks update-kubeconfig --name "$cluster"
  kubectl get serviceaccounts -A -o json | jq -r '
    .items[] |
    {ns: .metadata.namespace, name: .metadata.name,
     role: .metadata.annotations["eks.amazonaws.com/role-arn"]}' \
    >> "fleet-irsa-inventory-${cluster}.json"
done
# Cross-reference each role ARN's trust policy (subject condition present?)
# and permission policy (wildcards present?) via aws iam get-role / get-role-policy
```

### Under-the-Hood Explanation
Every relevant piece of state here — ServiceAccount annotations, IAM role trust policies, IAM role permission policies — is fully queryable via standard AWS and Kubernetes APIs, meaning a systematic audit is a data-aggregation and pattern-matching exercise, not something requiring manual, cluster-by-cluster human judgment for each individual role; the judgment is front-loaded into defining the correct criteria once, then applied mechanically and consistently across the entire fleet.

### Common Weak Answer
"Have each cluster's team self-attest that their IRSA roles follow least privilege."

### Why the Weak Answer Fails
Self-attestation without independent verification is exactly the kind of unenforceable, trust-based process a compliance audit is meant to move beyond — it provides no actual evidence and is trivially inconsistent across thirty independently-operating teams with varying levels of rigor; a systematic, automated, independently-run audit produces real, defensible evidence instead.

### Follow-Up Questions
1. How would you prioritize remediation across thirty clusters' worth of findings, given limited engineering time?
2. How would you present this audit's findings to the compliance team in a way that's both accurate and actionable?
3. How would you extend this fleet-wide audit approach to Kubernetes RBAC bindings, not just IRSA specifically?

### Key Interview Signals
Converts a vague compliance ask into concrete, automatable checks, and designs a systematic, fleet-scale audit rather than a manual or self-attested process that wouldn't actually hold up as real evidence.

### Hands-On Connection
[Lab 3 — IRSA and IAM](../labs/lab-03-irsa-and-iam/) and [Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).
