# Category 6: Kubernetes and EKS Integration

Questions 53–60 of 120. Category weight: 8 questions. Hands-on reference: [Lab 9 — Amazon EKS Infrastructure](../labs/lab-09-eks-infrastructure/).

---

## Question 53: The provider that needed a cluster that didn't exist yet

### Scenario
A single Terraform configuration provisions an EKS cluster and, in the same apply, uses the Kubernetes and Helm providers (configured with the cluster's endpoint/CA/token, derived from the `aws_eks_cluster` resource's attributes) to install cluster add-ons. On the very first apply against a brand-new cluster, the plan succeeds, but the apply intermittently fails with connection errors from the Kubernetes/Helm providers.

### Interview Question
Diagnose this and design a reliable pattern.

### Strong Senior-Level Answer
**Initial assessment:** provider *configuration* blocks are evaluated early, largely independent of the resource graph's create/destroy ordering — if the Kubernetes/Helm provider configuration references the EKS cluster's attributes, there's a real risk the provider attempts to establish its connection before the cluster is actually ready to accept API calls, or even before the `aws_eks_cluster` resource has finished creating, depending on how the configuration is structured.

**Technical reasoning:** provider configurations are conceptually part of Terraform's setup phase, not the same dependency-ordered resource graph that governs individual resource create/update/destroy — a provider block referencing a not-yet-created resource's attributes is a known fragile pattern, since Terraform's ability to sequence "finish creating the cluster, then configure the Kubernetes provider, then create Kubernetes resources" correctly depends on how explicitly that dependency is expressed.

**Investigation process:** confirm from the error timing/details whether the failure is a genuine "endpoint not reachable yet" (cluster still initializing) or an authentication failure (token/CA mismatch) — the fix differs slightly, but both stem from the same underlying provider-configuration-timing fragility.

**Recommended solution:** the most robust pattern is splitting this into two applies/configurations: one that creates the EKS cluster (and nothing Kubernetes-provider-dependent), and a second, separate configuration/state that configures the Kubernetes/Helm providers against the now-fully-created cluster's outputs (via `terraform_remote_state` or, preferably, data sources reading the cluster directly by name). If keeping it in one configuration is a hard requirement, ensure the Kubernetes/Helm provider blocks reference the cluster via a `data "aws_eks_cluster"` data source (not the resource directly) with an explicit `depends_on` forcing the data source to wait for cluster creation, and add `depends_on` on every Kubernetes/Helm resource pointing at the node group (so add-ons aren't attempted before nodes exist to schedule onto).

**Risk controls:** treat the cluster-creation and cluster-configuration phases as genuinely separate concerns with separate blast radii — a Helm chart failure shouldn't have any ability to affect the underlying EKS cluster resource itself.

**Validation steps:** test this pattern against a from-scratch cluster creation (not just an already-existing cluster being updated) since the timing fragility is specifically a first-apply/cold-start problem.

**Rollback or recovery strategy:** if an apply fails partway with the cluster created but add-ons not yet installed, a subsequent `terraform apply` (now that the cluster genuinely exists and is ready) should complete cleanly — this isn't a destructive failure, just an ordering one.

**Long-term prevention:** adopt the two-configuration split as your standard EKS module pattern going forward, documented clearly so future team members don't reintroduce the single-configuration coupling.

### Step-by-Step Implementation
```hcl
# Configuration A: cluster-infrastructure/main.tf — creates only the cluster and node groups
resource "aws_eks_cluster" "main" { /* ... */ }
resource "aws_eks_node_group" "main" { /* ... */ }
output "cluster_name" { value = aws_eks_cluster.main.name }
```
```hcl
# Configuration B: cluster-addons/main.tf — separate state, applied after A
data "aws_eks_cluster" "main" {
  name = var.cluster_name   # from Configuration A's output, via remote state or a parameter
}
data "aws_eks_cluster_auth" "main" {
  name = var.cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.main.token
}

resource "helm_release" "cluster_autoscaler" {
  # ...
  depends_on = [] # node group already exists by construction, since this is a separate, later apply
}
```

### Under-the-Hood Explanation
Terraform evaluates provider `configuration` blocks as part of preparing the graph, and while it can defer evaluation of arguments that depend on resources not yet created (producing unknown values, see [`terraform-internals.md` §6](../docs/terraform-internals.md#6-unknown-values-and-plan-construction)), a provider whose connection parameters remain unknown at the point it's first needed for a resource operation cannot proceed — the practical effect is that mixing "create the thing a provider connects to" and "use that provider" in the same apply is fragile specifically on the *first* apply, before any state establishing the cluster's settled, ready attributes exists. Splitting into two applies/states sidesteps this entirely, since Configuration B's provider configuration reads already-settled, real values from a completed Configuration A.

### Common Weak Answer
"Just add a `time_sleep` resource to wait for the cluster to be ready before installing add-ons."

### Why the Weak Answer Fails
A fixed sleep is a guess at how long cluster initialization takes, which can vary, and doesn't address the more fundamental provider-configuration-timing fragility — it might mask the symptom in most runs while still failing occasionally under different conditions, rather than fixing the actual architectural coupling.

### Follow-Up Questions
1. What are the trade-offs of the two-configuration split versus using `depends_on` more aggressively within one configuration?
2. How would you handle Helm releases that themselves depend on other Helm releases (e.g., cert-manager before an ingress controller that uses it)?
3. How does this problem manifest differently for a self-managed Kubernetes cluster (not EKS) where the control plane itself is Terraform-managed?

### Key Interview Signals
Confirms the candidate has hit this exact real-world EKS + Terraform provider-coupling issue and knows the split-configuration pattern, not just a band-aid sleep.

### Hands-On Connection
[Lab 9 — Amazon EKS Infrastructure](../labs/lab-09-eks-infrastructure/).

---

## Question 54: IRSA or Pod Identity?

### Scenario
You're designing IAM access for pods in a new EKS cluster (a green-field build, no legacy constraints). One engineer advocates for IAM Roles for Service Accounts (IRSA), citing its maturity and widespread documentation; another advocates for the newer EKS Pod Identity mechanism, citing simpler configuration.

### Interview Question
Which would you choose for a new cluster, and what factors would change your answer?

### Strong Senior-Level Answer
**Initial assessment:** for a genuinely green-field cluster with no legacy constraint, the newer EKS Pod Identity mechanism is generally the simpler choice going forward — it removes the need to manage an OIDC identity provider and the associated trust-policy `sub`/`aud` condition matching per service account that IRSA requires, replacing it with a more straightforward Pod Identity association resource. However, the actual decision depends on factors beyond "which is newer."

**Technical reasoning:** IRSA works by federating pod service account tokens through the cluster's OIDC issuer, requiring a trust policy per IAM role conditioned on the specific namespace/service-account-name combination (easy to get wrong — an overly broad condition grants more pods access than intended); Pod Identity uses a simpler, EKS-native association mechanism (an `aws_eks_pod_identity_association` resource mapping a namespace/service-account to a role) without needing to manage OIDC trust-policy conditions by hand.

**Investigation process:** check whether every tool/add-on this cluster will use (cluster autoscaler, external-dns, any third-party Helm charts) has documented Pod Identity support yet — since IRSA has been the standard for years, some third-party tooling's documentation/examples may still be IRSA-only, even if Pod Identity works underneath; also confirm the installed EKS/add-on versions actually support Pod Identity (it requires a minimum EKS platform version and the Pod Identity Agent add-on installed on the cluster).

**Recommended solution:** default to Pod Identity for this green-field cluster given the simpler, less-error-prone trust configuration, but verify compatibility for every planned add-on before committing, and be prepared to use IRSA for any specific workload/tool that doesn't yet support Pod Identity — the two mechanisms can coexist on the same cluster, so this isn't an all-or-nothing choice.

**Risk controls:** whichever mechanism is used for a given role, apply least-privilege scoping to the IAM policy itself regardless — the choice between IRSA and Pod Identity affects how the *trust* is established, not how tightly the *permissions* should be scoped, which matters equally either way.

**Validation steps:** for any Pod Identity association, confirm via a real pod that the expected IAM role's credentials are actually assumed (`aws sts get-caller-identity` from within the pod) and that a pod in a different namespace/service-account cannot assume the same role.

**Rollback or recovery strategy:** migrating a specific workload from IRSA to Pod Identity (or vice versa) later is a per-workload change (new association, updated trust policy or removed OIDC condition) — not a cluster-wide, all-or-nothing migration, so this decision doesn't lock you in permanently.

**Long-term prevention:** document the org's default choice (Pod Identity, per this green-field decision) and the specific conditions under which IRSA is still the right call (third-party tool lacking Pod Identity support), so future cluster builds don't re-litigate this from scratch each time.

### Step-by-Step Implementation
```hcl
# Pod Identity (preferred default for this green-field cluster)
resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "eks-pod-identity-agent"
}

resource "aws_eks_pod_identity_association" "app" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "production"
  service_account = "app-service-account"
  role_arn        = aws_iam_role.app_pod_role.arn
}

resource "aws_iam_role" "app_pod_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}
```
```hcl
# IRSA (for a specific add-on that doesn't yet support Pod Identity)
data "aws_iam_policy_document" "irsa_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:legacy-addon-sa"]
    }
  }
}
```

### Under-the-Hood Explanation
IRSA relies on the EKS cluster acting as an OIDC identity provider — pods receive a projected service account token signed by the cluster, which AWS STS validates against the cluster's registered OIDC provider and the role's trust policy conditions (matching the token's `sub` claim, which encodes namespace and service account name). EKS Pod Identity instead uses a dedicated Pod Identity Agent (a `DaemonSet` add-on) that intercepts credential requests from pods and exchanges them for role credentials via a direct EKS-to-STS association (`aws_eks_pod_identity_association`), without requiring the cluster to manage its own OIDC provider/trust-policy condition matching for this purpose at all — a materially simpler trust model with fewer places to misconfigure a condition.

### Common Weak Answer
"Use whichever one Terraform supports better."

### Why the Weak Answer Fails
The Terraform AWS provider supports both mechanisms — the actual decision criteria are about add-on/tooling compatibility, trust-configuration simplicity/error-proneness, and organizational default, not Terraform support, which isn't the differentiator here.

### Follow-Up Questions
1. How would you audit an existing IRSA-based cluster to identify migration candidates for Pod Identity?
2. What happens to existing IRSA-based pod roles if you later disable the cluster's OIDC provider — is that safe to do once fully migrated to Pod Identity?
3. How do you handle a workload needing cross-account IAM role access — does the choice between IRSA and Pod Identity affect that?

### Key Interview Signals
Tests whether the candidate can make and justify a concrete platform decision with real trade-off awareness (compatibility, trust-configuration complexity) rather than a reflexive "newer is always better" or "whatever's more common" answer.

### Hands-On Connection
[Lab 9 — Amazon EKS Infrastructure](../labs/lab-09-eks-infrastructure/).

---

## Question 55: The node group upgrade that evicted everything at once

### Scenario
An EKS managed node group is updated (new AMI release version) via Terraform. The apply triggers AWS's managed node group update process, which replaces all nodes. Several stateless services experience a brief full outage during the update because all their pods were scheduled on the nodes being cycled simultaneously, with no pod disruption budget in place.

### Interview Question
How would you redesign the node upgrade strategy to avoid this?

### Strong Senior-Level Answer
**Initial assessment:** two compounding gaps — the node group's update configuration wasn't controlling the pace/concurrency of node replacement, and no `PodDisruptionBudget` existed at the Kubernetes level to prevent the scheduler/eviction process from taking down every replica of a service simultaneously.

**Technical reasoning:** EKS managed node group updates support an `update_config` block controlling `max_unavailable`/`max_unavailable_percentage`, governing how many nodes are cycled concurrently — left at an aggressive default or misconfigured, this can replace nodes faster than the cluster can safely drain and reschedule pods elsewhere, especially if there isn't sufficient spare capacity.

**Investigation process:** check the node group's current `update_config` value and the actual pod distribution across nodes at the time of the incident (were all replicas of the affected services concentrated on a small number of nodes, making even a modest `max_unavailable` still take down every replica?).

**Recommended solution:** set a conservative `max_unavailable` (e.g., 1 node or 25%, tuned to cluster size) so node replacement happens gradually with time for pods to reschedule; add `PodDisruptionBudget` resources for every service with more than one replica, ensuring the Kubernetes scheduler/eviction controller won't voluntarily evict pods in a way that would violate minimum availability; and add pod anti-affinity rules so replicas of the same service are spread across nodes/AZs, reducing the chance that a single node's replacement affects every replica of any one service.

**Risk controls:** ensure the cluster has sufficient spare capacity (via cluster autoscaler or a slightly over-provisioned node group) so draining a node doesn't require pods to wait for new capacity to become available before rescheduling — capacity-constrained draining is a common cause of longer-than-expected disruption during node replacement.

**Validation steps:** test the corrected `update_config` plus `PodDisruptionBudget` combination against a non-production cluster's node group update, confirming zero-downtime for a representative multi-replica service during the update.

**Rollback or recovery strategy:** if a node group update is already underway and causing disruption, AWS's managed node group update can typically be monitored/cancelled via the EKS API — know this escape hatch exists, though prevention (correct `update_config` and PDBs) is far preferable to needing it.

**Long-term prevention:** make `update_config` tuning and `PodDisruptionBudget` presence a required part of the EKS module's/cluster's standard checklist for every new service deployed, not an afterthought discovered after an incident.

### Step-by-Step Implementation
```hcl
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = var.subnet_ids

  update_config {
    max_unavailable_percentage = 25
  }

  scaling_config {
    desired_size = 6
    min_size     = 4
    max_size     = 10
  }
}
```
```yaml
# Kubernetes: PodDisruptionBudget per service (applied via Kubernetes provider or GitOps)
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: app-pdb
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: web-app
```
```yaml
# Pod anti-affinity to spread replicas across nodes
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        labelSelector:
          matchLabels: { app: web-app }
        topologyKey: kubernetes.io/hostname
```

### Under-the-Hood Explanation
EKS managed node group updates work by cordoning and draining old nodes according to the `update_config`'s concurrency limit, launching replacement nodes, and waiting for pods to reschedule before proceeding to the next batch — the *drain* step respects `PodDisruptionBudget`s (the eviction API refuses an eviction that would violate a PDB's `minAvailable`), which is precisely why a PDB's absence allows the drain to proceed and evict every replica of a service concurrently if they happen to be co-located on the nodes being cycled in the same batch.

### Common Weak Answer
"Just do the node group update during a maintenance window."

### Why the Weak Answer Fails
A maintenance window reduces the *visibility/impact timing* of an outage but doesn't fix the actual cause — the same all-at-once eviction would still happen during the maintenance window; the real fix is `update_config` pacing plus PDBs, which prevent the disruption from happening at all, at any time.

### Follow-Up Questions
1. How would you handle a stateful service (not stateless) during the same kind of node group update?
2. What's the interaction between `max_unavailable` and cluster autoscaler if the cluster doesn't have spare capacity to begin with?
3. How would you validate PDB configuration is actually correct and effective before relying on it during a real node group update?

### Key Interview Signals
Confirms the candidate understands node group update mechanics at the Kubernetes-eviction level (not just "there's a Terraform setting for this") and connects the Terraform-level configuration (`update_config`) to the Kubernetes-level control (`PodDisruptionBudget`) that together prevent this class of incident.

### Hands-On Connection
[Lab 9 — Amazon EKS Infrastructure](../labs/lab-09-eks-infrastructure/).

---

## Question 56: The `aws-auth` change that locked everyone out

### Scenario
An engineer updates the cluster's access configuration (aws-auth ConfigMap or the newer EKS access entries API) to remove what they believe is an unused IAM role mapping. After apply, the entire platform team — including the engineer who made the change — can no longer authenticate to the cluster via `kubectl` at all.

### Interview Question
How did this happen, what's your immediate recovery path, and how do you prevent it going forward?

### Strong Senior-Level Answer
**Initial assessment:** the removed role mapping was, in fact, the one every platform team member's assumed-role session actually maps to for cluster authentication — a classic "the thing that looked unused was actually load-bearing for everyone's own access" mistake, compounded by the fact that losing cluster access this way is a genuine, if usually recoverable, lockout.

**Technical reasoning:** EKS cluster authentication maps IAM principals to Kubernetes RBAC identities either via the legacy `aws-auth` ConfigMap or the newer, Terraform-manageable EKS access entries API — removing a mapping that every engineer's actual IAM role/session resolves to removes their ability to authenticate to the Kubernetes API at all, regardless of how much Kubernetes RBAC permission their (now-unmapped) identity would otherwise have.

**Investigation process:** confirm exactly which IAM principal(s) the removed mapping represented, and whether it matches what `aws sts get-caller-identity` shows for the affected engineers' actual sessions — this confirms the root cause precisely rather than assuming.

**Recommended solution:** recovery depends on what access remains: if the cluster creator's IAM principal (which EKS grants implicit cluster-admin access to by default, separate from the access-entries/aws-auth configuration) is still available to at least one team member, use that identity to restore the correct mapping via `kubectl`/Terraform directly. If genuinely nobody has any remaining path in, the recovery requires AWS-side intervention — a break-glass IAM role or, in newer EKS versions, using the EKS API/cluster creator credentials directly bypasses the access-entry configuration for emergency recovery, since the cluster creator identity's access doesn't depend on aws-auth/access-entries at all. Once access is restored, fix the actual Terraform configuration (not a manual `kubectl` patch) so the correct mapping is restored declaratively and won't be silently removed again on the next apply.

**Risk controls:** before removing *any* access mapping, cross-reference it against actual usage (CloudTrail `AssumeRole` activity for that role, or cluster audit logs showing recent API server authentication from that principal) rather than assuming "unused" from static inspection alone.

**Validation steps:** after restoring, have every affected team member independently confirm they can authenticate, not just the engineer who made the original change — a partial fix (restoring access for some but not all previously-mapped principals) is easy to miss if only one person tests.

**Rollback or recovery strategy:** maintain a documented, tested break-glass access path (a specific IAM role always granted cluster-admin via access entries, used only for exactly this recovery scenario) so a lockout never requires guessing which identity might still work.

**Long-term prevention:** treat cluster access-entry/aws-auth changes with the same "verify actual usage before removing" discipline as IAM policy changes generally, require a second reviewer specifically for this class of change, and maintain the documented break-glass path as standing infrastructure, tested periodically (not just assumed to work when actually needed).

### Step-by-Step Implementation
```hcl
# Modern approach: EKS access entries (Terraform-manageable, auditable)
resource "aws_eks_access_entry" "platform_team" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_iam_role.platform_team.arn
}

resource "aws_eks_access_policy_association" "platform_team_admin" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_iam_role.platform_team.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }
}

# Standing break-glass access entry, always present, tested periodically
resource "aws_eks_access_entry" "break_glass" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_iam_role.break_glass.arn
}
```
```bash
# Recovery, if cluster-creator identity still available
aws eks update-kubeconfig --name main --role-arn arn:aws:iam::...:role/cluster-creator
kubectl get configmap aws-auth -n kube-system -o yaml   # or: aws eks list-access-entries
# Restore the correct mapping, then fix Terraform to match declaratively
```

### Under-the-Hood Explanation
EKS access entries (the modern replacement for hand-editing the `aws-auth` ConfigMap) are themselves stored as EKS-native API objects, associating an IAM principal ARN with Kubernetes RBAC permissions via access policies — critically, the IAM principal that originally created the cluster retains implicit administrative access to the Kubernetes API independent of the access-entries configuration, specifically as a safety net against exactly this kind of lockout; this is why checking whether the cluster-creator identity is still available is the first, most important recovery step, since it doesn't depend on whatever access-entry mapping was just broken.

### Common Weak Answer
"Just redeploy the cluster from scratch since access is broken."

### Why the Weak Answer Fails
Recreating an entire EKS cluster (and every workload running on it) is a drastically disproportionate response to an access-configuration mistake — the cluster-creator identity escape hatch (or, if that's also unavailable, a properly-provisioned break-glass role) almost always provides a much less disruptive recovery path that doesn't touch the running workloads at all.

### Follow-Up Questions
1. How would you verify your break-glass access role actually works, without waiting for a real lockout to discover it doesn't?
2. What's the difference in recovery options between a cluster created by an IAM user versus one created by an assumed role — does the "cluster creator" escape hatch behave the same way?
3. How would you extend this access-entry management to support a large platform team with different scopes (some cluster-admin, some namespace-scoped) without repeating this mistake at a larger scale?

### Key Interview Signals
Confirms the candidate knows the specific EKS cluster-creator-identity escape hatch (not obvious unless you've actually operated EKS access configuration) and treats access-removal changes with real "verify before removing" discipline.

### Hands-On Connection
[Lab 9 — Amazon EKS Infrastructure](../labs/lab-09-eks-infrastructure/) and [Lab 14 — Drift, Failure, and Recovery](../labs/lab-14-drift-and-recovery/).

---

## Question 57: Three security groups, one cluster, one incident waiting to happen

### Scenario
A new EKS cluster design is being reviewed. It currently has one single security group shared across the cluster control plane, all worker nodes, and (via a security-group-per-pod configuration) every pod — meaning any change intended for one layer (e.g., opening a port for the control plane's communication with nodes) risks inadvertently affecting pod-to-pod or pod-to-internet traffic rules too.

### Interview Question
Redesign the security group architecture for this cluster.

### Strong Senior-Level Answer
**Initial assessment:** collapsing cluster, node, and pod security concerns into one shared security group means every change's blast radius spans all three layers, and makes reasoning about "what traffic is actually allowed at the pod level" impossible without mentally subtracting out cluster/node-specific rules that don't apply there.

**Technical reasoning:** EKS's recommended architecture separates concerns into (at minimum) a **cluster security group** (control-plane-to-node communication, managed largely by EKS itself), a **node security group** (node-to-node and node-to-control-plane traffic, plus any node-level requirements like SSM access), and, if using security-groups-for-pods, **pod-specific security groups** applied via `SecurityGroupPolicy` for workloads needing genuinely distinct network access (e.g., a pod needing access to an on-prem network via a specific security group rule that shouldn't apply to every other pod on the same node).

**Investigation process:** audit the current shared security group's rule set and classify each rule by which layer it's actually needed for — cluster-control-plane communication, general node requirements, or pod-specific requirements — this classification is the basis for the split.

**Recommended solution:** split into the standard EKS three-tier security group model: the cluster security group (EKS-managed, minimal changes needed), a node security group scoped to genuine node-level needs (SSH/SSM access if used, node-to-node communication for CNI), and pod-specific security groups only for the specific workloads that need traffic rules distinct from the general node baseline (most pods don't need their own security group at all and can rely on Kubernetes NetworkPolicies for pod-to-pod segmentation instead, reserving AWS security-groups-for-pods for cases needing AWS-resource-level scoping, like RDS access restricted to specific pods).

**Risk controls:** avoid defaulting every workload to its own dedicated security group "just in case" — this reintroduces sprawl in the opposite direction; reserve pod-specific security groups for workloads with genuine AWS-resource-level network requirements, and rely on Kubernetes-native NetworkPolicies for general pod-to-pod segmentation.

**Validation steps:** after the split, confirm each layer's rule set only contains what's actually needed for that layer, and confirm no cross-layer traffic is unintentionally broken (e.g., control-plane-to-node communication, which EKS depends on functioning correctly, remains intact).

**Rollback or recovery strategy:** perform the split incrementally — add the new node/pod security groups alongside the existing shared one first, verify traffic still flows correctly, then remove rules from the shared group only after confirming the new, scoped groups cover the actual needs.

**Long-term prevention:** document the three-tier model as the standard EKS security group pattern for all future clusters, so new clusters don't default back to a single shared group out of convenience.

### Step-by-Step Implementation
```hcl
# Node security group: scoped to genuine node-level needs only
resource "aws_security_group" "eks_nodes" {
  vpc_id = var.vpc_id
  ingress {
    description     = "Node to node CNI communication"
    from_port       = 0
    to_port         = 65535
    protocol        = "-1"
    self            = true
  }
  ingress {
    description     = "Control plane to node"
    from_port       = 1025
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_eks_cluster.main.vpc_config[0].cluster_security_group_id]
  }
}

# Pod-specific security group only for workloads with genuine AWS-resource-level needs
resource "kubernetes_manifest" "app_pod_sg_policy" {
  manifest = {
    apiVersion = "vpcresources.k8s.aws/v1beta1"
    kind       = "SecurityGroupPolicy"
    metadata   = { name = "app-db-access", namespace = "production" }
    spec = {
      podSelector = { matchLabels = { app = "billing-service" } }
      securityGroups = { groupIds = [aws_security_group.billing_db_access.id] }
    }
  }
}
```

### Under-the-Hood Explanation
EKS automatically manages a cluster security group governing control-plane-to-node communication as part of `aws_eks_cluster`'s own `vpc_config` — this is largely hands-off and shouldn't be where custom rules are added. Security-groups-for-pods works by the VPC CNI attaching the specified security group directly to the pod's own ENI (branch ENI, for the trunk/branch networking mode EKS uses), meaning that specific pod's traffic is subject to that security group's rules *in addition to* the node's, which is precisely why conflating all three layers into one group makes it impossible to reason about which rule applies at which level — with genuinely separate groups, each layer's rule set is independently auditable.

### Common Weak Answer
"Just open all necessary ports on the one security group so everything works."

### Why the Weak Answer Fails
This is the exact anti-pattern the scenario describes — a single shared group forces overly broad rules to satisfy the union of every layer's needs, and makes any future change's blast radius span cluster, node, and pod traffic simultaneously, which is precisely the risk being asked to redesign away.

### Follow-Up Questions
1. When would you choose Kubernetes NetworkPolicies over AWS security-groups-for-pods for pod-level segmentation, and when would you need both?
2. How does this security group architecture change for Fargate-based pods instead of EC2-based node groups?
3. How would you validate that your three-tier split hasn't accidentally broken control-plane-to-node communication, which could otherwise manifest as a subtle, hard-to-diagnose cluster health issue?

### Key Interview Signals
Confirms the candidate knows the standard EKS multi-tier security group model specifically (not just general security-group best practice) and can reason about which traffic belongs at which layer.

### Hands-On Connection
[Lab 9 — Amazon EKS Infrastructure](../labs/lab-09-eks-infrastructure/).

---

## Question 58: One state or two for cluster and workloads?

### Scenario
A team is deciding whether to manage the EKS cluster infrastructure (VPC, cluster, node groups, IAM) and the Kubernetes-level workloads deployed onto it (namespaces, deployments, Helm releases) in the same Terraform state/configuration, or split them into two.

### Interview Question
Which would you recommend, and why?

### Strong Senior-Level Answer
**Initial assessment:** split them — this mirrors the general state-boundary reasoning from [`state-management.md` §12](../docs/state-management.md#12-state-splitting-for-blast-radius-reduction-the-5000-resource-problem): cluster infrastructure changes infrequently and is high-blast-radius if wrong; workload deployments change frequently (potentially many times a day) and should have their own fast, independent, frequently-run plan/apply cycle, ideally owned by application teams rather than the platform team that owns cluster infrastructure.

**Technical reasoning:** beyond the general state-boundary argument, there's a specific EKS-related reason: keeping workloads in a separate configuration avoids the provider-configuration-timing fragility from [Question 53](#question-53-the-provider-that-needed-a-cluster-that-didnt-exist-yet) entirely, since the workload configuration's Kubernetes/Helm providers always reference an already-existing, already-settled cluster (from a completed, separate cluster-infrastructure apply) rather than one being created in the same run.

**Investigation process:** if the team's actual workflow already deploys application workloads via a separate CI/CD/GitOps pipeline (common — e.g., ArgoCD, Flux, or application-team-owned Helm/kubectl pipelines) rather than through Terraform's own Kubernetes/Helm providers at all, this question may partially resolve itself — Terraform manages the cluster infrastructure, and a GitOps tool manages workloads, which is itself a valid and common variant of "split them."

**Recommended solution:** separate cluster-infrastructure state (owned by platform team, changes infrequently) from workload state (owned by application teams or managed via GitOps, changes frequently), with the workload layer consuming the cluster's identity (name, endpoint) via a stable output/parameter, not a same-state reference.

**Risk controls:** whichever workload-management approach is chosen (Terraform-Kubernetes-provider-based or GitOps-based), ensure the platform team's cluster-infrastructure changes (e.g., an EKS version upgrade) go through their own change process independent of and not blocked by workload deployment activity, and vice versa.

**Validation steps:** confirm the cluster-infrastructure state's plan never shows unrelated workload-level changes, and confirm workload deployments can proceed without needing to touch or even have access to the cluster-infrastructure state.

**Rollback or recovery strategy:** with separated concerns, a bad workload deployment's rollback (revert the workload configuration/Helm release) is completely independent of and cannot affect cluster infrastructure, and vice versa — this isolation is itself the primary benefit being validated.

**Long-term prevention:** document this split as the standard pattern for all future clusters, and if adopting GitOps for workloads, ensure the boundary between "what Terraform manages" (cluster infra, possibly cluster-wide add-ons) and "what GitOps manages" (application workloads) is clearly defined and doesn't overlap ambiguously.

### Step-by-Step Implementation
```text
cluster-infrastructure/ (separate state, platform team owned)
  - VPC, EKS cluster, node groups, IAM, core add-ons (VPC CNI, CoreDNS, kube-proxy)
  - outputs: cluster_name, cluster_endpoint, cluster_ca

workload-deployments/ (separate state per application, or GitOps-managed)
  - namespaces, Helm releases, application-specific IAM (Pod Identity associations)
  - consumes cluster_name via SSM parameter or data source, not same-state reference
```
```hcl
# workload-deployments/main.tf
data "aws_ssm_parameter" "cluster_name" {
  name = "/platform/eks/cluster_name"
}
data "aws_eks_cluster" "main" {
  name = data.aws_ssm_parameter.cluster_name.value
}
```

### Under-the-Hood Explanation
This is the same state-boundary/blast-radius reasoning applied specifically to the cluster-infrastructure/workload split — the only EKS-specific technical wrinkle is the provider-configuration-timing benefit from [Question 53](#question-53-the-provider-that-needed-a-cluster-that-didnt-exist-yet): a workload configuration's Kubernetes/Helm provider blocks read from an already-complete cluster-infrastructure state's outputs, so they never reference an in-progress-of-being-created cluster, eliminating that entire class of first-apply fragility as a side benefit of the split.

### Common Weak Answer
"Keep it all in one configuration, it's simpler to manage."

### Why the Weak Answer Fails
"Simpler" here trades away independent change cadence, independent blast radius, and the provider-timing robustness benefit, for the convenience of one `terraform apply` doing everything — a false simplicity that reintroduces exactly the coupling problems covered in [Question 53](#question-53-the-provider-that-needed-a-cluster-that-didnt-exist-yet) and the general state-boundary guidance.

### Follow-Up Questions
1. How would you decide whether core cluster add-ons (VPC CNI, CoreDNS) belong in the cluster-infrastructure state or the workload state?
2. If adopting GitOps for workloads, what's Terraform's remaining role, and how do you avoid the two systems fighting over the same resources?
3. How does this split affect your incident response when a workload issue turns out to actually be a cluster-infrastructure problem (e.g., insufficient node capacity)?

### Key Interview Signals
Confirms the candidate applies the general state-boundary principle specifically and correctly to the EKS cluster/workload split, and is aware of the provider-timing benefit as a bonus reason beyond generic blast-radius reasoning.

### Hands-On Connection
[Lab 9 — Amazon EKS Infrastructure](../labs/lab-09-eks-infrastructure/).

---

## Question 59: One cluster, ten tenants, zero cross-tenant blast radius

### Scenario
A shared EKS cluster hosts ten different internal teams' applications, each in its own namespace. Leadership wants assurance that a mistake by one team (an overly permissive Kubernetes RBAC role, a misconfigured pod trying to access another team's AWS resources) cannot affect another team's workloads or AWS access.

### Interview Question
Design the multi-tenancy isolation for this cluster.

### Strong Senior-Level Answer
**Initial assessment:** cluster-level sharing is fine for compute efficiency, but every isolation boundary (RBAC, network, IAM) needs to be enforced per-namespace/per-tenant, since a single shared cluster provides no isolation by default beyond basic namespace-scoping of Kubernetes objects.

**Technical reasoning:** three independent isolation layers are needed: Kubernetes RBAC (each team's role bindings scoped to only their own namespace, via `RoleBinding` not `ClusterRoleBinding`), network policy (Kubernetes `NetworkPolicy` resources denying cross-namespace pod traffic by default, allowing only explicitly-needed exceptions), and IAM (each team's pods getting their own Pod Identity/IRSA associations scoped to only their own namespace/service-account, so one team's pod cannot assume another team's AWS role even if it somehow gained network access to attempt it).

**Investigation process:** audit current RBAC bindings for any `ClusterRoleBinding` granting broad, cluster-wide permissions to a single team's service account (a common gap when clusters grow organically) and audit current Pod Identity/IRSA trust conditions for any role trusted by a namespace/service-account pattern broader than intended.

**Recommended solution:** enforce namespace-scoped `RoleBinding`s exclusively for tenant teams (no `ClusterRoleBinding`s except for genuinely cluster-wide platform-team roles), default-deny `NetworkPolicy` per namespace with explicit allow rules only for legitimate cross-namespace traffic (e.g., a shared ingress controller), and Pod Identity/IRSA associations scoped precisely to each team's own namespace/service-account pairing, never a broader pattern.

**Risk controls:** add a policy-as-code check (via an admission controller like Kyverno/OPA Gatekeeper, or Conftest against the Terraform-managed Kubernetes manifests) that rejects any `ClusterRoleBinding` or overly-broad Pod Identity trust condition from being created by anyone other than the platform team.

**Validation steps:** test isolation concretely — attempt (in a controlled test) to have a pod in one team's namespace access another team's Kubernetes resources (should be denied by RBAC), another team's pod network endpoint (should be denied by NetworkPolicy), and another team's AWS role (should be denied by IAM trust conditions) — three independent negative tests proving each layer.

**Rollback or recovery strategy:** since these are additive guardrails (default-deny plus explicit allows), tightening them shouldn't break legitimate existing traffic if the "explicit allow" exceptions were correctly identified during the audit — if something breaks, it reveals an undocumented legitimate cross-namespace dependency that needs an explicit allow rule added, not a reason to abandon the default-deny posture.

**Long-term prevention:** make this three-layer isolation (RBAC, NetworkPolicy, IAM scoping) a mandatory, tested part of onboarding any new tenant team onto the shared cluster, rather than a retrofit exercise done once under leadership pressure.

### Step-by-Step Implementation
```hcl
resource "kubernetes_role_binding" "team_a" {
  metadata {
    name      = "team-a-admin"
    namespace = "team-a"       # namespace-scoped, never cluster-wide
  }
  role_ref {
    kind      = "ClusterRole"
    name      = "admin"
    api_group = "rbac.authorization.k8s.io"
  }
  subject {
    kind      = "Group"
    name      = "team-a-engineers"
    api_group = "rbac.authorization.k8s.io"
  }
}
```
```yaml
# Default-deny NetworkPolicy per tenant namespace
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: team-a
spec:
  podSelector: {}
  policyTypes: ["Ingress"]
  # no ingress rules = deny all by default; explicit allow rules added separately
```
```hcl
resource "aws_eks_pod_identity_association" "team_a" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "team-a"                  # scoped exactly, not a wildcard/broad pattern
  service_account = "team-a-service-account"
  role_arn        = aws_iam_role.team_a.arn
}
```

### Under-the-Hood Explanation
Kubernetes RBAC `RoleBinding`s (namespace-scoped) versus `ClusterRoleBinding`s (cluster-wide) determine the scope of a granted permission at the API-server authorization layer; `NetworkPolicy` resources are enforced by the CNI plugin (the AWS VPC CNI supports NetworkPolicy enforcement) at the packet-filtering level between pods; and Pod Identity/IRSA trust scoping is enforced by AWS STS at role-assumption time — these are three genuinely independent enforcement points (Kubernetes API server, CNI networking layer, AWS STS), which is exactly why all three need to be configured correctly for full isolation; a gap in any one layer alone doesn't compromise the others, but also doesn't provide isolation on its own.

### Common Weak Answer
"Namespaces already provide isolation between teams."

### Why the Weak Answer Fails
Namespaces are an organizational/scoping boundary for Kubernetes objects, not an enforced security isolation boundary by default — without explicit RBAC scoping, NetworkPolicies, and IAM trust scoping, pods in different namespaces can, depending on configuration, still reach each other over the network, and overly broad RBAC/IAM configurations can grant cross-namespace access regardless of namespace boundaries existing.

### Follow-Up Questions
1. How would you handle a legitimate need for cross-namespace communication (e.g., a shared logging sidecar or ingress controller) without weakening the default-deny posture generally?
2. How would you extend this isolation model to also cover node-level isolation (would you ever need dedicated node groups per tenant)?
3. How would you audit this multi-tenancy design continuously, not just at initial setup, as new teams/workloads are added over time?

### Key Interview Signals
Confirms the candidate identifies all three necessary isolation layers (RBAC, NetworkPolicy, IAM) rather than treating namespaces alone as sufficient, and designs concrete, testable negative-case validation for each.

### Hands-On Connection
[Lab 9 — Amazon EKS Infrastructure](../labs/lab-09-eks-infrastructure/) and [Lab 13 — Policy as Code](../labs/lab-13-policy-as-code/).

---

## Question 60: The Kubernetes upgrade that broke half the ingress rules

### Scenario
A Terraform-managed EKS cluster is upgraded from Kubernetes 1.28 to 1.29 (a routine `aws_eks_cluster.version` bump). Immediately after, several Helm-managed ingress resources fail to reconcile, because they use a Kubernetes API version that was deprecated in an earlier release and finally removed in 1.29.

### Interview Question
Whose responsibility was this to catch, and how do you prevent it for the next version upgrade?

### Strong Senior-Level Answer
**Initial assessment:** this is a Kubernetes API deprecation issue, not a Terraform-specific bug — Kubernetes has a well-documented API deprecation policy, and upgrading the control plane version without first confirming every workload's manifests use currently-supported API versions is the actual gap, regardless of the fact that the *trigger* was a Terraform-managed version bump.

**Technical reasoning:** the `aws_eks_cluster` resource's `version` argument controls the control plane version; Terraform has no visibility into or responsibility for whether the *workloads* running on that cluster use API versions the new control plane still supports — that's a Kubernetes-manifest-level concern, separate from the infrastructure-level version bump.

**Investigation process:** identify exactly which API versions were removed between 1.28 and 1.29 (Kubernetes publishes this per release) and cross-reference against every Helm chart/manifest actually deployed on this cluster to find every affected resource, not just the ones that failed loudly.

**Recommended solution:** before any future control-plane version bump, run `kubectl` (or a dedicated tool like `pluto` or `kube-no-trouble`) against the cluster to detect any deployed resources using API versions deprecated in or removed by the target version, fixing/upgrading those manifests *before* the control plane upgrade, not after. For the current incident, upgrade the affected Helm charts to versions using the current API version, and reapply.

**Risk controls:** treat "run a deprecated-API-version scan against the target Kubernetes version" as a mandatory pre-upgrade gate in the pipeline that manages Terraform's `aws_eks_cluster.version`, not a manual step someone might remember.

**Validation steps:** after fixing the affected ingress resources, confirm they reconcile successfully, and run the deprecated-API-version scanner again post-upgrade to confirm no other resources are silently in a similarly broken state that hasn't yet surfaced as a visible failure.

**Rollback or recovery strategy:** EKS control-plane version downgrades are not supported by AWS — once upgraded, you cannot revert the control plane itself; the only path forward is fixing the workloads' API versions, which reinforces why catching this *before* the upgrade (not after) is the only real prevention, not a "roll back if it breaks" safety net.

**Long-term prevention:** integrate a deprecated-API scan into the standard EKS version-upgrade pipeline as a hard gate before the `aws_eks_cluster.version` change is ever allowed to proceed, and track Kubernetes's published deprecation timeline proactively (upgrading deprecated manifests well before they're actually removed, not reactively after a removal breaks something).

### Step-by-Step Implementation
```bash
# Pre-upgrade gate: scan for deprecated/removed API usage against the target version
pluto detect-helm --target-versions k8s=v1.29.0
kubectl-neat  # or kube-no-trouble (kubent) as an alternative scanner
```
```hcl
# Only proceed with the version bump after the scan is clean
resource "aws_eks_cluster" "main" {
  version = "1.29"   # bumped only after pre-upgrade scan confirms no deprecated API usage
  # ...
}
```
```bash
# Fix affected charts before or immediately after, then verify
helm upgrade ingress-nginx ingress-nginx/ingress-nginx --version <version-using-current-api>
kubectl get ingress -A   # confirm reconciliation succeeds cluster-wide
```

### Under-the-Hood Explanation
Kubernetes API versions go through a formal deprecation lifecycle (alpha → beta → stable, with deprecation and eventual removal announced well in advance per Kubernetes's own versioning policy) — when a control plane version that has fully removed a given API version is deployed, any manifest still referencing that removed `apiVersion` field is rejected by the API server entirely, which is why previously-working Helm-managed resources suddenly fail to reconcile: it's not that Terraform did anything wrong to them, it's that the control plane they depend on no longer understands the API shape they were written against.

### Common Weak Answer
"Roll back the EKS version bump to fix it."

### Why the Weak Answer Fails
EKS control-plane version downgrades are not supported by AWS — this isn't an option at all, making "roll back" not just suboptimal but actually unavailable; the only real path is fixing the workloads, which also means the *prevention* (scanning before upgrading) is the only thing that actually avoids this class of incident, since there's no safety net after the fact.

### Follow-Up Questions
1. How would you handle a third-party Helm chart that hasn't yet been updated by its maintainers to use the current API version?
2. What's your process for tracking Kubernetes's deprecation timeline proactively across dozens of clusters, rather than discovering issues reactively?
3. How does this deprecated-API risk differ for custom resources (CRDs) managed by your own team's controllers, versus standard Kubernetes API resources?

### Key Interview Signals
Confirms the candidate correctly attributes this to a Kubernetes API lifecycle issue (not a Terraform defect), knows EKS control-plane downgrades aren't supported (a specific, important operational fact), and designs a genuine pre-upgrade gate rather than a reactive fix.

### Hands-On Connection
[Lab 9 — Amazon EKS Infrastructure](../labs/lab-09-eks-infrastructure/).
