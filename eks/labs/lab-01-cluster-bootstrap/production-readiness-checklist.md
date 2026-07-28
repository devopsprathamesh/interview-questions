# Production-Readiness Checklist

## What a bare, Terraform-provisioned cluster already has
- [x] Control plane (`ACTIVE`, multi-AZ, AWS-managed)
- [x] Node groups (per the Terraform module's configuration)
- [x] `vpc-cni` (`aws-node`), `coredns`, `kube-proxy` — EKS-managed add-ons

## What it does NOT have yet — mapped to the lab that adds it
- [ ] Prefix delegation / custom networking (if needed for pod density) — [Lab 2](../lab-02-networking-vpc-cni/)
- [ ] IRSA/Pod Identity for workload AWS access — [Lab 3](../lab-03-irsa-and-iam/)
- [ ] Karpenter (or tuned Cluster Autoscaler) — [Lab 5](../lab-05-karpenter-autoscaling/)
- [ ] EBS/EFS CSI drivers configured with correct StorageClasses — [Lab 6](../lab-06-storage-ebs-efs-csi/)
- [ ] AWS Load Balancer Controller — [Lab 7](../lab-07-ingress-and-load-balancing/)
- [ ] Pod Security Standards, NetworkPolicy enforcement, image verification — [Lab 8](../lab-08-security-hardening/)
- [ ] Observability stack (Prometheus/Grafana or Container Insights, Fluent Bit) — [Lab 9](../lab-09-observability-stack/)
- [ ] GitOps controller (ArgoCD) — [Lab 10](../lab-10-gitops-argocd/)
- [ ] Progressive delivery (Argo Rollouts) — [Lab 11](../lab-11-progressive-delivery/)
- [ ] CI/CD pipeline — [Lab 12](../lab-12-cicd-pipeline/)
- [ ] Policy as code (Kyverno/Gatekeeper) — [Lab 13](../lab-13-policy-as-code-opa/)

## Standing questions to answer before declaring this cluster production-ready
- Is the API server endpoint access appropriately restricted for this cluster's use case? (private, or public-with-tight-CIDR)
- Does every EKS-managed add-on's update policy (automatic vs. manual) match this cluster's risk tolerance?
- Is there a documented, tested break-glass access path independent of normal cluster access?
