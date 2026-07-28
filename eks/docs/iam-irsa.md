# IAM, IRSA, and Kubernetes RBAC

Deep-dive reference for [`interview-questions/03-iam-irsa.md`](../interview-questions/03-iam-irsa.md) and [Lab 3 — IRSA and IAM](../labs/lab-03-irsa-and-iam/).

## 1. The problem IRSA solves

Before IRSA, a pod's only way to get AWS credentials was inheriting the **node's** IAM instance-profile role — meaning every pod on a node had the same AWS permissions as every other pod on that node, regardless of what each individual workload actually needed. This is the Kubernetes-native version of the "one shared credential for everything" anti-pattern discussed throughout the companion Terraform and Ansible repositories' least-privilege guidance — a compromised or misbehaving pod could use the node role's full permission set, not just what its own workload needed.

## 2. The IRSA trust chain

IAM Roles for Service Accounts works via a specific, layered trust chain:

1. The EKS cluster has an **OIDC identity provider** registered in IAM (a one-time setup per cluster), which issues signed tokens the cluster's API server can verify.
2. A **Kubernetes ServiceAccount** is annotated with `eks.amazonaws.com/role-arn: <iam-role-arn>`.
3. Any **pod** using that ServiceAccount gets a projected, short-lived, audience-scoped OIDC token automatically mounted into its filesystem by the API server (via the `TokenRequest` API/kubelet, not a static secret).
4. The AWS SDK inside the pod (via the Pod Identity webhook injecting environment variables/volume mounts) exchanges that token for temporary AWS credentials via `sts:AssumeRoleWithWebIdentity`, subject to the IAM role's **trust policy** — which must specifically condition on the OIDC provider, namespace, and ServiceAccount name to actually restrict which pods can assume it.

The trust policy's `Condition` block is the actual enforcement point — a trust policy that only checks the OIDC provider without also conditioning on the specific namespace/ServiceAccount subject effectively allows *any* ServiceAccount in the cluster to assume that role, a common, dangerous misconfiguration:
```json
{
  "Effect": "Allow",
  "Principal": { "Federated": "arn:aws:iam::ACCOUNT:oidc-provider/oidc.eks.REGION.amazonaws.com/id/CLUSTER_ID" },
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Condition": {
    "StringEquals": {
      "oidc.eks.REGION.amazonaws.com/id/CLUSTER_ID:sub": "system:serviceaccount:my-namespace:my-serviceaccount",
      "oidc.eks.REGION.amazonaws.com/id/CLUSTER_ID:aud": "sts.amazonaws.com"
    }
  }
}
```

## 3. IRSA vs. EKS Pod Identity (the newer mechanism)

**EKS Pod Identity** (a newer, simpler alternative to IRSA) removes the need for per-cluster OIDC-provider trust-policy plumbing entirely — instead, a Pod Identity association is created directly (ServiceAccount + namespace + IAM role, via the EKS API/`aws eks create-pod-identity-association`), and the EKS Pod Identity Agent (a DaemonSet) handles credential vending without requiring the trust policy to reference cluster-specific OIDC details at all. The trade-off: Pod Identity is newer and requires the Pod Identity Agent add-on; IRSA remains extremely widely deployed and is not being deprecated. The senior-level answer distinguishes these as two valid, evolving approaches to the same underlying problem (least-privilege, pod-scoped AWS credentials) rather than treating IRSA as the only option or as legacy.

## 4. RBAC and cluster access — the aws-auth ConfigMap vs. Access Entries

Historically, mapping an IAM principal (user/role) to Kubernetes RBAC permissions required editing the `aws-auth` ConfigMap in `kube-system` — a notoriously easy-to-misconfigure, YAML-in-a-ConfigMap mechanism with no built-in audit trail of *who* changed *what* mapping, and a real risk of a syntax error locking out cluster access entirely. **EKS Access Entries** (a newer, EKS-API-native mechanism) replace this with a proper API-managed access-control layer (`aws eks create-access-entry`, associable with AWS-managed or custom access policies), giving IAM-native audit trail (CloudTrail) for access-mapping changes — a direct improvement on the `aws-auth` ConfigMap's opacity. Clusters can still use `aws-auth` for backward compatibility, but new clusters/access mappings should prefer Access Entries.

## 5. Kubernetes RBAC itself — a separate authorization layer

Even once an IAM principal is mapped to a Kubernetes identity (via `aws-auth` or Access Entries), what that identity can actually *do* inside the cluster is governed by standard Kubernetes RBAC (`Role`/`ClusterRole` + `RoleBinding`/`ClusterRoleBinding`) — a completely separate authorization layer from IAM. A common senior-level distinction: IAM controls "can this principal talk to the EKS API/cluster at all," while Kubernetes RBAC controls "what can this principal do once it's talking to the cluster" — conflating the two (assuming a broad IAM permission automatically grants broad in-cluster permission, or vice versa) is a common junior mistake.

## 6. Service account token projection — short-lived, audience-bound, not a static secret

Modern Kubernetes ServiceAccount tokens (via the `TokenRequest` API, the default since Kubernetes 1.24 removed auto-generated long-lived Secret-based tokens) are short-lived, audience-scoped, and automatically rotated by the kubelet — a materially stronger security posture than the old long-lived, unbounded ServiceAccount token Secrets that used to be auto-created for every ServiceAccount and could be extracted and reused indefinitely if leaked.

## 7. Node IAM role least privilege — the same problem, one layer down

The **node's own IAM instance-profile role** (distinct from any pod's IRSA role) still needs enough permissions for kubelet/CNI/CSI-driver operation (e.g., `ec2:DescribeInstances`, ENI attachment permissions, EBS volume attach/detach for the CSI driver) — but should never be broader than that, since every pod on the node inherits it as a fallback if IRSA isn't configured for a given ServiceAccount. A pod without an IRSA-annotated ServiceAccount silently falls back to the node role's permissions — an easy-to-miss gap where "we use IRSA" is true for *some* workloads but not verified for *all* of them.

## 8. Cross-account access for pods

A pod's IRSA role can itself assume a role in a different AWS account (a second-hop `sts:AssumeRole`, chained after the first `AssumeRoleWithWebIdentity`), the Kubernetes-native equivalent of the companion Terraform repository's multi-account provider-aliasing pattern and the companion Ansible repository's [Question 42](../../ansible/interview-questions/04-modules-plugins.md#question-42-one-playbook-five-aws-accounts) cross-account automation-identity pattern — the same "central identity, scoped per-target-account role" architecture, expressed via IRSA's trust chain instead of an assumed CI role.

## Common weak vs. senior answers

| Weak answer | Senior answer |
|---|---|
| "Give the node role broad permissions so any pod can do what it needs" | Uses IRSA (or Pod Identity) for pod-scoped least privilege, keeps the node role minimal |
| "IRSA trust policy just needs to reference the OIDC provider" | Also conditions on the specific namespace/ServiceAccount subject, or the role is assumable by any pod in the cluster |
| "IAM access to the cluster means the user can do anything in it" | Distinguishes IAM (cluster access) from Kubernetes RBAC (in-cluster authorization) as separate layers |
| "We use IRSA everywhere" (unverified) | Actually audits which ServiceAccounts lack an IRSA annotation and would silently fall back to the node role |

## Related material

- [`docs/eks-architecture.md`](eks-architecture.md), [`docs/security.md`](security.md)
- [Lab 3 — IRSA and IAM](../labs/lab-03-irsa-and-iam/)
- Companion: [Terraform multi-account patterns](../../terraform/), [Ansible Question 42](../../ansible/interview-questions/04-modules-plugins.md)
