# EKS Architecture and Internals

Foundational reference for how EKS actually works under the hood. Read this first — most interview questions in [`interview-questions/01-eks-cluster-architecture.md`](../interview-questions/01-eks-cluster-architecture.md) assume this material.

## 1. Control plane vs. data plane — who manages what

EKS splits ownership sharply:

- **Control plane (AWS-managed):** the API server, etcd, scheduler, and controller-manager run in an AWS-owned account, across multiple AZs, with AWS handling patching, scaling, and etcd backup/durability. You never SSH into it, never see its underlying EC2 instances, and cannot directly access etcd.
- **Data plane (customer-managed, to varying degrees):** worker nodes — whether EC2 via managed node groups, self-managed EC2, or Fargate — run in *your* account, in *your* VPC, and you (or your automation) own their patching, scaling, and lifecycle, subject to whatever AWS-managed abstraction you choose.

This split is the single most important fact for reasoning about blast radius: a control-plane issue (API server latency, etcd degradation) is an AWS-managed incident you can escalate to AWS Support but cannot directly remediate; a data-plane issue (a node out of disk, a pod stuck in `CrashLoopBackOff`) is entirely yours to diagnose and fix.

## 2. The API server as the only interface that matters

Every interaction with a Kubernetes cluster — `kubectl`, a controller's reconciliation loop, the scheduler placing a pod, a CNI plugin wiring up networking — happens *through* the API server, which persists all cluster state to etcd. There is no side channel: if the API server is unreachable, the cluster's actual workloads keep running (kubelets continue operating pods they already know about), but nothing new can be scheduled, no config can be read fresh, and no state can be observed or changed until connectivity is restored. This is why "is the API server reachable" is always the first diagnostic step, not an afterthought.

## 3. Cluster endpoint access modes

EKS clusters have configurable API server endpoint access:

- **Public only:** API server reachable from the internet (subject to your own IP allowlisting via the public access CIDR list).
- **Public and private:** reachable both from the internet (allowlisted) and from within the VPC (via a set of ENIs EKS provisions into your subnets).
- **Private only:** reachable only from within the VPC (or anything peered/connected to it) — no internet path at all, requiring a bastion, VPN, or Transit Gateway connection for any human/CI access from outside the VPC.

The senior-level judgment call here mirrors the companion Terraform repository's private-endpoint discipline for sensitive infrastructure: production clusters generally warrant private (or public-with-tight-CIDR-allowlisting) endpoint access, with CI/CD access routed through the VPC (a self-hosted runner, or a runner with VPC connectivity) rather than a broad public allowlist.

## 4. Add-ons: EKS-managed vs. self-managed

EKS distinguishes between:

- **EKS-managed add-ons** (`vpc-cni`, `coredns`, `kube-proxy`, `aws-ebs-csi-driver`, etc.) — AWS manages the add-on's lifecycle (version compatibility with your cluster version, and optionally automatic updates), configured via the EKS API (or Terraform's `aws_eks_addon` resource) rather than a raw Helm install.
- **Self-managed add-ons** (anything installed via Helm/manifests directly, e.g., the AWS Load Balancer Controller, Cluster Autoscaler, Karpenter, ArgoCD) — you own the entire lifecycle: version compatibility, upgrade sequencing, and configuration drift detection.

The senior-level distinction to draw in an interview: EKS-managed add-ons reduce operational burden for a narrower set of foundational components, but the majority of what makes a cluster actually useful (ingress controllers, autoscalers, GitOps tooling, observability agents) remains self-managed, and their version compatibility with both the cluster's Kubernetes version and each other is an ongoing operational responsibility — see [`docs/addons-and-upgrades.md`](addons-and-upgrades.md) for the upgrade-sequencing details.

## 5. Where Terraform's responsibility ends and this repo's begins

Per the companion Terraform repository's EKS module: Terraform provisions the cluster itself (control plane, associated IAM roles, the VPC and subnets, node group launch templates and their IAM roles/security groups, and EKS-managed add-ons via `aws_eks_addon`). This repository's labs assume that provisioning is already done and pick up from there — installing and configuring self-managed add-ons (Load Balancer Controller, Karpenter, ArgoCD, observability agents), designing workloads, IRSA bindings, network policies, and GitOps pipelines.

The boundary in practice: if a change requires modifying the cluster's own existence, its node groups' launch template, or its VPC/subnet layout, that's a Terraform change (see the companion repo's [Lab 7](../../terraform/labs/lab-09-eks-infrastructure/) and related AWS architecture labs). If a change is about what runs *inside* the cluster or how it's configured at the Kubernetes API level, that's this repository's concern.

## 6. Where Ansible still has a role, and where it doesn't

Kubernetes-native workloads make most of Ansible's traditional configuration-management role redundant for *what runs inside the cluster*: a Deployment's rolling update replaces a push-based playbook's `serial` rollout; a DaemonSet replaces a per-host role; a ConfigMap/Secret replaces a templated config file deployed by a role. Ansible retains a role for:

- Bootstrapping infrastructure *adjacent* to the cluster that isn't itself Kubernetes-native (a bastion host, a self-hosted CI runner's underlying EC2 instance, a legacy non-containerized system the cluster's workloads still depend on).
- One-time or infrequent cluster-adjacent operational tasks that don't warrant a full GitOps/controller pattern (though even these are increasingly handled via a Kubernetes Job or a GitOps-triggered workflow instead).

The senior-level answer to "should we use Ansible to configure our EKS workloads" is almost always no — that's what the Kubernetes API, GitOps controllers, and Helm/Kustomize are for; see [Question 1](../interview-questions/01-eks-cluster-architecture.md#question-1) for the full scenario-based treatment of this exact question.

## 7. Multi-AZ by default, but not automatically resilient

EKS control planes span multiple AZs automatically (AWS-managed, no configuration needed). Your **data plane** does not get this for free — node groups must be explicitly spread across multiple AZs (via subnet configuration), and even then, a Pod's actual resilience to an AZ failure depends on whether its replicas are scheduled across those AZs (via topology spread constraints or pod anti-affinity) rather than accidentally concentrated in one. This is a recurring senior-level distinction: AWS-managed multi-AZ resilience for the control plane does not automatically extend to your workloads' actual placement — see [`docs/ha-dr.md`](ha-dr.md) §2.

## 8. Cluster version lifecycle and its operational weight

EKS supports a rolling window of Kubernetes minor versions, each with a defined end-of-standard-support date, after which extended support (at additional cost) or forced upgrade applies. Upgrading a cluster's control plane is generally non-disruptive to running workloads by itself, but upgrading node groups (replacing nodes running an older kubelet version) is a genuine operational event requiring careful sequencing — see [`docs/addons-and-upgrades.md`](addons-and-upgrades.md) for the full upgrade-order discipline (control plane, then add-ons, then node groups, in that specific order, with compatibility checked at every step).

## Common weak vs. senior answers

| Weak answer | Senior answer |
|---|---|
| "EKS is just managed Kubernetes, AWS handles everything" | Names the exact control-plane/data-plane split and what remains customer-owned |
| "Just use the default VPC CNI settings" | Understands IP-per-pod allocation, ENI limits, and prefix delegation trade-offs |
| "Ansible can configure our pods" | Recognizes Kubernetes-native mechanisms (Deployments, DaemonSets, ConfigMaps) supersede push-based configuration management inside the cluster |
| "Multi-AZ is automatic" | Distinguishes AWS-managed control-plane multi-AZ from data-plane/workload placement, which requires explicit design |

## Related material

- [`docs/networking.md`](networking.md), [`docs/iam-irsa.md`](iam-irsa.md), [`docs/addons-and-upgrades.md`](addons-and-upgrades.md), [`docs/ha-dr.md`](ha-dr.md)
- [Lab 1 — Cluster Bootstrap](../labs/lab-01-cluster-bootstrap/)
- Companion: [Terraform repository's EKS provisioning material](../../terraform/)
