# Cheat Sheet: IRSA and IAM

## The trust chain (all four links must be correct)
1. Cluster OIDC provider registered in IAM
2. IAM role trust policy conditions on `sub` (namespace + ServiceAccount) **and** `aud` (`sts.amazonaws.com`)
3. Kubernetes ServiceAccount annotated with `eks.amazonaws.com/role-arn`
4. Pod's projected OIDC token (short-lived, automatically rotated)

## The #1 trust-policy mistake
```json
// BROKEN - only checks the OIDC provider, not WHICH pod
"Condition": {} // missing entirely, or missing the :sub key

// FIXED
"Condition": {
  "StringEquals": {
    "OIDC_PROVIDER:sub": "system:serviceaccount:NAMESPACE:SERVICEACCOUNT",
    "OIDC_PROVIDER:aud": "sts.amazonaws.com"
  }
}
```
Without the `sub` condition, **any pod in the cluster** can assume the role. [Question 23](../interview-questions/03-iam-irsa.md#question-23-the-trust-policy-that-trusted-everyone)

## IRSA vs. Pod Identity
| | IRSA | EKS Pod Identity |
|---|---|---|
| Trust policy | Needs per-cluster OIDC condition boilerplate | No OIDC-provider-specific conditions needed |
| Association | Implicit via annotation + trust policy | Explicit `aws eks create-pod-identity-association` |
| Maturity | Widely deployed, not deprecated | Newer, simpler, reduces misconfiguration surface |
| Migration | — | Both are valid; don't force fleet-wide migration without a plan |

## The silent fallback
A ServiceAccount with **no** IRSA annotation doesn't error — it silently falls back to the **node's own IAM role**. Audit for this:
```bash
kubectl get serviceaccounts -A -o json | \
  jq -r '.items[] | select(.metadata.annotations["eks.amazonaws.com/role-arn"] == null) | "\(.metadata.namespace)/\(.metadata.name)"'
```
[Question 24](../interview-questions/03-iam-irsa.md#question-24-the-pod-that-fell-back-to-the-node)

## IAM vs. Kubernetes RBAC — two separate layers
- **IAM / Access Entries**: can this principal reach the cluster's API at all?
- **Kubernetes RBAC**: what can this principal do once it's talking to the cluster?
`AdministratorAccess` in IAM does **not** imply `cluster-admin` in RBAC — they're independent authorization systems. [Question 27](../interview-questions/03-iam-irsa.md#question-27-but-i-have-administratoraccess-in-iam)

## aws-auth ConfigMap → Access Entries
- `aws-auth`: a single YAML ConfigMap — one malformed entry can break **every** principal's access simultaneously.
- **Access Entries** (modern): each principal is an independent, individually-validated API object. Prefer this for new clusters. [Question 26](../interview-questions/03-iam-irsa.md#question-26-the-aws-auth-typo-that-locked-everyone-out)

## Cross-account pattern
Hub role's own permissions scoped to `sts:AssumeRole` against an **explicit allowlist** of target-account role ARNs — never a wildcard. Each target account's role trusts only that specific hub role ARN. [Question 29](../interview-questions/03-iam-irsa.md#question-29-one-role-five-accounts-one-pod)

## Fleet-scale auditing
Never rely on manual, per-cluster review or self-attestation. Automate: trust-policy subject-scoping check, node-role-fallback detection, RBAC wildcard scan — across every cluster, one script. [Question 34](../interview-questions/03-iam-irsa.md#question-34-auditing-irsa-at-fleet-scale)
