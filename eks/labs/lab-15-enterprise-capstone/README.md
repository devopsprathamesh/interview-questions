# Lab 15: Enterprise Capstone

## Objective
Integrate every pattern built across this repository into one complete, layered platform — networking, IRSA, autoscaling, storage, ingress, security, observability, GitOps, progressive delivery, and policy — composed as a single, coherent system with genuine operational documentation, rather than fifteen separate exercises.

## Scenario
You're the platform engineer responsible for standing up a genuinely production-shaped application platform on EKS. This capstone composes Labs 1–13 into one working system: a GitOps-managed application, deployed via progressive delivery, secured by Pod Security Admission and Kyverno policy, observable via Prometheus/Grafana, with IRSA-scoped AWS access and correctly-provisioned storage — and a documented, tested recovery process for the platform itself.

## Skills Practised
- Composing every prior lab's components into one working, multi-layer platform
- The "App of Apps" GitOps bootstrap pattern applying a full security/observability baseline automatically to any new cluster
- Multi-tenant namespace isolation (RBAC, ResourceQuota, NetworkPolicy, dedicated node pools)
- Writing genuine operational documentation (`OPERATIONS.md`), not just manifests

## Architecture
See [`OPERATIONS.md`](OPERATIONS.md) for the full architecture diagram and operational reference. Summary: a bootstrap `ApplicationSet` (App of Apps) applies the security/observability baseline (Labs 8–9, 13) to any cluster automatically; a GitOps-managed application (Lab 10) deploys via progressive delivery (Lab 11) behind an ALB (Lab 7); IRSA (Lab 3) scopes its AWS access; Karpenter (Lab 5) and the CSI drivers (Lab 6) provide compute and storage; a CI/CD pipeline (Lab 12) builds/signs/deploys it.

## Prerequisites
- Labs 1, 3, 5, 6, 7, 8, 9, 10, 11, and 13 completed (or at least reviewed) — this capstone assumes their components are available
- **Cost warning**: this capstone runs the fullest stack in the repository simultaneously (Karpenter-provisioned nodes, Prometheus/Grafana, ArgoCD, an ALB). Budget accordingly and tear down promptly when done.

## Directory Structure
```text
lab-15-enterprise-capstone/
├── README.md
├── OPERATIONS.md
├── bootstrap/
│   ├── app-of-apps.yaml
│   └── baseline-applications/
│       ├── security-baseline-app.yaml
│       └── observability-app.yaml
├── manifests/    (references the repo-root manifests/base + overlays structure)
└── gitops-repo-capstone-app/
    ├── base/deployment.yaml
    └── overlays/production/kustomization.yaml
```

## Step-by-Step Tasks
1. Review `bootstrap/app-of-apps.yaml` — the single ArgoCD `Application` that, applied once to any new cluster, automatically bootstraps the security baseline (Pod Security Admission defaults, Kyverno policies from Lab 13) and observability stack (Lab 9), per [Question 68](../../interview-questions/07-security-hardening.md#question-68-the-security-baseline-that-only-existed-in-one-cluster)'s automated-bootstrap fix.
2. Apply it and confirm both baseline applications sync automatically, with no manual per-cluster setup.
3. Deploy `gitops-repo-capstone-app/` via a new ArgoCD `Application`, using the Rollout-based progressive-delivery pattern from [Lab 11](../lab-11-progressive-delivery/).
4. Confirm the deployed application: runs under `restricted` Pod Security Admission (Lab 8), uses an IRSA-scoped ServiceAccount (Lab 3), is reachable via an ALB with `target-type: ip` (Lab 7), and is visible in Grafana (Lab 9).
5. Read [`OPERATIONS.md`](OPERATIONS.md) in full and confirm you understand every cross-component dependency before considering the capstone complete.

## Kubernetes Configuration
See [`bootstrap/`](bootstrap/) and [`gitops-repo-capstone-app/`](gitops-repo-capstone-app/).

## Commands to Execute
```bash
kubectl apply -f bootstrap/app-of-apps.yaml
argocd app list   # confirm security-baseline and observability apps both synced automatically
# Push gitops-repo-capstone-app/ to your fork, then:
kubectl apply -f gitops-repo-capstone-app/argocd-application.yaml
kubectl argo rollouts get rollout capstone-app --watch
```

## Expected Output
- The App of Apps bootstraps the full baseline with zero manual, per-component setup.
- The capstone application deploys via a canary rollout, passes its scoped `AnalysisTemplate`, and reaches 100% traffic.
- The application is reachable via its ALB, visible in Grafana, and its pods pass Pod Security Admission's `restricted` checks.

## Validation
```bash
kubectl get pods -n capstone -o jsonpath='{.items[*].spec.securityContext}'
kubectl get polr -A   # policy reports - confirm no violations
argocd app get capstone-app
```

## Failure Injection
Deliberately break the IRSA trust policy for the capstone app's ServiceAccount (remove the `sub` condition, per [Lab 3](../lab-03-irsa-and-iam/)'s exercise) and confirm the application's AWS-dependent functionality fails predictably, then fix it.

## Troubleshooting Exercise
Simulate a primary-region-equivalent outage by deleting the ArgoCD instance entirely (`kubectl delete namespace argocd`) and confirm the capstone application's **already-running** pods continue serving traffic unaffected (Kubernetes' own reconciliation doesn't depend on GitOps controller uptime for already-scheduled workloads) — but any *new* change can no longer be reconciled until ArgoCD is restored. This is the hands-on version of [Question 106](../../interview-questions/12-ha-dr.md#question-106-the-dr-cluster-that-was-ready-except-for-the-part-that-mattered)'s GitOps-controller-availability lesson.

## Cleanup
```bash
kubectl delete -f gitops-repo-capstone-app/argocd-application.yaml
kubectl delete -f bootstrap/app-of-apps.yaml
```
Then tear down the underlying cluster via the companion Terraform repository's `terraform destroy` if you're done with the full lab series.
**Chargeable resources:** every Karpenter-provisioned node, the ALB, and Prometheus's EBS-backed storage — verify all are cleaned up.

## Interview Questions Connected to This Lab
This capstone integrates concepts from every category — see in particular:
- [Question 110: The capstone question — designing HA/DR from a blank page](../../interview-questions/12-ha-dr.md#question-110-the-capstone-question--designing-hadr-from-a-blank-page)
- [Question 68: The security baseline that only existed in one cluster](../../interview-questions/07-security-hardening.md#question-68-the-security-baseline-that-only-existed-in-one-cluster)
- [Question 119: The architecture decision nobody wanted to own](../../interview-questions/15-migration-leadership.md#question-119-the-architecture-decision-nobody-wanted-to-own)

## Production Considerations
See [`OPERATIONS.md`](OPERATIONS.md) in full — it covers cost, security, scaling, and DR considerations for taking this pattern to a genuinely production-scale, multi-team platform.

## Advanced Challenge
Extend this capstone with a second, DR-region cluster reconciled by the same `ApplicationSet`-based bootstrap and the same GitOps application source, and design the explicit, separate data-replication mechanism this platform's stateful dependencies would need — per [Question 106](../../interview-questions/12-ha-dr.md#question-106-the-dr-cluster-that-was-ready-except-for-the-part-that-mattered)'s exact lesson.
