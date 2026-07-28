# Pointing the EKS repo at Floci

This covers what running [`eks/`](../../../eks/) against Floci can and cannot realistically give you. Read this before assuming the whole repo "just works" locally — EKS is the one companion repo where the gap between the real service and any local emulation is largest, and overstating it would violate this whole collection's documented commitment to honest capability claims (see the root [README's Validation and honesty section](../../../README.md#validation-and-honesty)).

## The one claim worth taking seriously

Floci's own quickstart page states, for EKS specifically, that it "spins up a real k3s node" rather than mocking the Kubernetes API. If true, that's a materially stronger claim than most local AWS emulators make for EKS — LocalStack's own EKS support, for comparison, is typically a thin API stub. A real k3s node means `kubectl` is talking to an actual, CNCF-conformant Kubernetes API server and kubelet, not a fake response generator. That's the part of this repo most likely to genuinely function.

## What that plausibly means works

Anything in the EKS repo that is pure Kubernetes — no AWS-specific control plane integration involved:

- Core object lifecycle: Deployments, Services, ConfigMaps, Secrets, Namespaces, Ingress objects (as API objects, not necessarily wired to a real load balancer — see below).
- Scheduling and workload behavior: most of [Lab 14: Troubleshooting and Recovery](../../../eks/labs/lab-14-troubleshooting-and-recovery/)'s scenarios (zero-endpoint Services, OOMKilled recurrence, unschedulable pods) are pure `kubectl`/scheduler mechanics that don't touch AWS at all.
- GitOps tooling itself: ArgoCD/Argo Rollouts talk to the Kubernetes API, not to AWS — the controllers themselves should run fine against a real k3s node.
- Kyverno/OPA policy enforcement: also pure Kubernetes admission-control mechanics.
- Helm chart installs and Kustomize overlays: these just produce Kubernetes manifests either way.

## What will not match real EKS, and why

| Feature | Why it breaks down locally |
|---|---|
| **IRSA (IAM Roles for Service Accounts)** | Real IRSA depends on a real OIDC identity provider registered with real AWS IAM, and a real `sts:AssumeRoleWithWebIdentity` call validated against that provider. A local emulator would need to fully reimplement OIDC federation semantics to make this work identically — not something to assume without direct verification. |
| **AWS Load Balancer Controller** | Provisions real ALBs/NLBs by calling the real ELB API. Against Floci, it will either fail, no-op, or create fake API objects with no real routable endpoint behind them. |
| **EBS/EFS CSI drivers** | Dynamic `PersistentVolumeClaim` provisioning depends on real EBS/EFS volumes being created and attached. Whether Floci's storage emulation goes that deep is unconfirmed. |
| **Karpenter** | Calls the real EC2 Fleet/`RunInstances` APIs to launch nodes sized to pending pod demand. Against an emulator, this is either a no-op or launches fake node objects — genuine capacity-driven autoscaling behavior is unlikely to be reproduced faithfully. |
| **Multi-AZ control-plane HA, real version upgrade rollout behavior** | These are properties of AWS's own managed control plane, which a single local k3s node fundamentally isn't. |
| **Real node group lifecycle (managed node groups, launch templates)** | Same underlying issue as Karpenter — node provisioning is an EC2-API-driven process that a single local k3s node doesn't reproduce. |

## Practical recommendation

Split the EKS repo's labs into two groups when working locally:

1. **Run against Floci**: [Lab 14 (Troubleshooting)](../../../eks/labs/lab-14-troubleshooting-and-recovery/), most manifest/Helm/Kustomize-only labs, GitOps/ArgoCD labs, policy-as-code labs — anything where the interesting behavior lives entirely inside Kubernetes.
2. **Treat as read-through/whiteboard exercises, or run against a real (cost-controlled, single-AZ) cluster**: the IRSA lab, the Karpenter lab, the ALB/ingress lab, and anything in the enterprise capstone that depends on those — the value of these labs is specifically in the AWS-EKS integration behavior that a local k3s node can't reproduce.

## Connecting kubectl to Floci's k3s node

The exact mechanism (kubeconfig extraction, port, TLS) is not documented on Floci's quickstart page — expect to run `floci logs --follow` or `floci status` after `floci start` and an EKS `CreateCluster` call to find how it exposes the resulting kubeconfig, and update this doc with the exact steps once verified. Do not assume a specific command here without having actually run it — that's exactly the kind of unverified claim this repo avoids.

## Where this picks up

The EKS repo's own README already documents that it "picks up from a cluster already provisioned by the Terraform repo's EKS module" — see [`modules/eks`](../../../terraform/modules/eks/) and [terraform-integration.md](terraform-integration.md#module-by-module-expectations) for the Terraform side of getting a Floci-backed cluster stood up in the first place.
