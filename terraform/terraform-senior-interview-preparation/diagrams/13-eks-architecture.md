# Diagram 13: EKS Infrastructure Architecture

Referenced from [`docs/`](../docs/) (Phase 3 AWS/EKS documentation) and [Lab 9](../labs/lab-09-eks-infrastructure/).

```mermaid
flowchart TD
    subgraph VPC["VPC"]
        subgraph Public["Public subnets (multi-AZ)"]
            ALB[Application Load Balancer]
            NAT[NAT Gateway]
        end
        subgraph Private["Private subnets (multi-AZ)"]
            NodeGroup[Managed node group]
            Pods[Pods]
        end
    end

    subgraph ControlPlane["EKS control plane (AWS-managed)"]
        API[Kubernetes API server]
        OIDC[OIDC issuer]
    end

    IAMClusterRole[EKS cluster IAM role] --> API
    IAMNodeRole[Node instance IAM role] --> NodeGroup
    OIDC -->|IRSA / Pod Identity\ntrust relationship| IAMPodRole[Pod-level IAM role]
    IAMPodRole --> Pods

    ALB --> Pods
    NodeGroup --> NAT
    NAT --> Internet[Internet]
    API -.->|cluster endpoint access| Admins[Terraform / kubectl / CI]

    Pods --> Pods
    Provider1["Terraform AWS provider"] --> ControlPlane
    Provider1 --> VPC
    Provider2["Terraform Kubernetes/Helm provider\n(depends on cluster existing)"] -.->|explicit dependency| ControlPlane
```

**Key points:**
- Nodes and pods live in private subnets; only the load balancer sits in public subnets — outbound-only internet access for nodes goes through NAT.
- IRSA (IAM Roles for Service Accounts) or the newer EKS Pod Identity mechanism lets individual pods assume narrowly-scoped IAM roles via the cluster's OIDC issuer, instead of nodes sharing one broad instance role.
- The Kubernetes/Helm Terraform provider configuration depends on the cluster existing first — a common source of "provider configuration depends on a resource" ordering problems, addressed explicitly in [Lab 9](../labs/lab-09-eks-infrastructure/).
