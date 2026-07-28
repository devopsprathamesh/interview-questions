# Add-ons, Helm, and Cluster/Version Upgrades

Deep-dive reference for [`interview-questions/08-addons-upgrades.md`](../interview-questions/08-addons-upgrades.md) and [Lab 4 — Managed Node Groups](../labs/lab-04-managed-node-groups/).

## 1. EKS-managed vs. self-managed add-ons — see also `docs/eks-architecture.md` §4

EKS-managed add-ons (`vpc-cni`, `coredns`, `kube-proxy`, `aws-ebs-csi-driver`, `aws-efs-csi-driver`, `eks-pod-identity-agent`) have AWS-tracked version compatibility with your cluster's Kubernetes version, installable/updatable via the EKS API (`aws eks update-addon`, or Terraform's `aws_eks_addon`). Self-managed components (AWS Load Balancer Controller, Karpenter, Cluster Autoscaler, ArgoCD, most observability agents) have no such AWS-tracked compatibility guarantee — you own tracking their compatibility with your cluster's Kubernetes API version yourself, typically via each project's own compatibility matrix.

## 2. The correct upgrade order — control plane, then add-ons, then nodes

Upgrading an EKS cluster's Kubernetes version safely follows a specific sequence, and doing it out of order is the single most common cause of an upgrade-induced incident:

1. **Review the target version's deprecated/removed API list** — anything using a removed API (e.g., an old Ingress `apiVersion`) will break on upgrade regardless of order; catch this first via `kubectl deprecations` or `pluto`/`kube-no-trouble`.
2. **Upgrade the control plane** (one minor version at a time — EKS does not support skipping minor versions) — this is generally non-disruptive to already-running workloads, since existing pods keep running under the old kubelet version until nodes are separately upgraded.
3. **Upgrade EKS-managed add-ons** to versions compatible with the new control-plane version.
4. **Upgrade self-managed add-ons** (Load Balancer Controller, Karpenter, etc.) to versions compatible with the new API version — check each project's compatibility matrix explicitly, don't assume the previous version still works.
5. **Upgrade node groups last** (new launch template/AMI referencing the new Kubernetes version, via managed node group version update or Karpenter's own node replacement) — this is the actually disruptive step (pods get rescheduled as old nodes drain), and should be done with the same conservative, health-checked pacing as any rolling infrastructure change (see the companion Terraform repository's ASG instance-refresh guidance, directly analogous here).

Skipping straight to a node upgrade before the control plane is upgraded (or upgrading self-managed add-ons before confirming their new-version compatibility) is the most common way this sequence goes wrong.

## 3. Helm as the primary packaging mechanism for self-managed add-ons

Most self-managed add-ons are installed/upgraded via Helm charts (`helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller ...`). Helm's own versioning (chart version vs. app version) and `values.yaml` overrides are the primary interface for configuring these components — the senior-level discipline here mirrors the companion Ansible repository's Galaxy/collection-versioning guidance: pin exact chart versions (never a floating `latest` or unpinned major version) in any environment where reproducibility matters, and review a chart's own changelog/breaking-changes notes before any version bump, exactly as you would a Terraform provider or an Ansible collection.

## 4. Add-on conflicts and ownership boundaries

A subtle failure mode: installing a self-managed version of something also available as an EKS-managed add-on (e.g., manually Helm-installing the VPC CNI or CoreDNS alongside the EKS-managed version) creates two competing owners of the same resource, exactly the dual-tool-ownership conflict discussed in the companion Ansible repository's Terraform/Ansible boundary guidance, applied here to EKS-managed vs. self-managed add-on ownership. Always confirm whether a given component already has an EKS-managed add-on before installing it independently via Helm.

## 5. Deprecated API migration — a genuine, recurring engineering task

Kubernetes regularly deprecates and eventually removes API versions (e.g., `extensions/v1beta1` Ingress, removed well before most EKS-supported versions). A manifest or Helm chart referencing a removed API simply fails to apply after the relevant control-plane upgrade — with the error often surfacing at the worst possible time (mid-upgrade) rather than being caught proactively. Tools like `pluto` or `kubent` (kube-no-trouble) scan manifests/cluster state for soon-to-be-removed API usage ahead of time — treat this as a standing pre-upgrade check, not a reactive fire drill.

## 6. Add-on health as an ongoing operational signal, not a one-time install-and-forget

Add-ons (especially the AWS Load Balancer Controller, CSI drivers, and Karpenter) are themselves workloads that can fail, crash, or fall behind on their own version relative to what the cluster now requires — monitor their own health (pod status, logs, relevant CloudWatch metrics) as part of standing cluster observability, not just at install time.

## Common weak vs. senior answers

| Weak answer | Senior answer |
|---|---|
| "Just upgrade everything to the latest version" | Follows the specific control-plane-then-add-ons-then-nodes sequence, one minor version at a time |
| "Helm chart versions don't matter much" | Pins exact chart versions and reviews changelogs before bumping, exactly like a Terraform provider or Ansible collection |
| "We installed our own CoreDNS/VPC CNI via Helm for more control" | Checks first whether this conflicts with the EKS-managed add-on of the same component |
| "We'll deal with deprecated APIs when the upgrade breaks" | Proactively scans for deprecated/removed API usage before every upgrade via `pluto`/`kubent` |

## Related material

- [`docs/eks-architecture.md`](eks-architecture.md), [`docs/ha-dr.md`](ha-dr.md)
- [Lab 4 — Managed Node Groups](../labs/lab-04-managed-node-groups/)
- Companion: [Terraform ASG instance-refresh guidance](../../../terraform/terraform-senior-interview-preparation/), [Ansible collection-versioning guidance](../../../ansible/ansible-senior-interview-preparation/docs/role-design.md)
