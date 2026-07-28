# CI/CD and GitOps on EKS

Deep-dive reference for [`interview-questions/10-cicd-gitops.md`](../interview-questions/10-cicd-gitops.md), [Lab 10 — GitOps with ArgoCD](../labs/lab-10-gitops-argocd/), and [Lab 11 — Progressive Delivery](../labs/lab-11-progressive-delivery/).

## 1. GitOps: pull-based reconciliation, not push-based deployment

The defining architectural difference from a traditional CI/CD pipeline: a GitOps controller (ArgoCD or Flux) runs **inside** the cluster and continuously reconciles live cluster state toward what's declared in a Git repository — it *pulls* the desired state and applies it, rather than a CI pipeline *pushing* changes via `kubectl apply`/`helm upgrade` from outside the cluster. This is the direct Kubernetes-native analog of Terraform's plan/apply reconciliation loop, but continuous and automatic rather than triggered per-CI-run — and, notably, it also means Git is a genuine source of truth: any manual, out-of-band `kubectl edit` against a GitOps-managed resource gets silently reverted on the controller's next reconciliation pass, exactly like Terraform's drift-correction on the next `apply`.

## 2. Self-healing and drift detection are built into the model

Because reconciliation runs continuously (not just at deploy time), GitOps controllers detect and correct drift automatically — if something (a manual change, a competing controller, an incident-response emergency `kubectl patch`) diverges live state from Git, the controller either flags it (if configured for detection-only) or actively reverts it (if configured for auto-sync/self-heal) on its next reconciliation cycle. This is a meaningfully stronger drift-handling guarantee than either the companion Terraform repository (drift detected only when someone runs `plan`) or the companion Ansible repository (drift detected only when a playbook happens to re-run) — genuinely continuous, not periodic.

## 3. Progressive delivery: canary and blue-green via Argo Rollouts

Standard Kubernetes `Deployment` rolling updates have no traffic-weighted canary capability and no automated rollback-on-metric-regression — **Argo Rollouts** (or Flagger) replaces the `Deployment` resource with a `Rollout` custom resource supporting:

- **Canary:** gradually shift traffic percentage to the new version, pausing at defined steps for automated analysis (querying Prometheus/CloudWatch for error-rate/latency regression) before proceeding or automatically rolling back.
- **Blue-green:** run the new version fully alongside the old, cut traffic over atomically once verified, keeping the old version standing by for instant rollback.

This is the Kubernetes-native equivalent of the deployment-strategy trade-offs discussed in the companion repositories' immutable-infrastructure guidance, but with automated, metric-driven promotion/rollback decisions rather than a human watching a dashboard.

## 4. Secrets in a GitOps workflow — never plaintext in Git

Since GitOps means the Git repo is the actual source of truth applied to the cluster, a plaintext Secret manifest committed to that repo is now a permanent, versioned credential leak in your source control history. The standard patterns:

- **Sealed Secrets** (Bitnami) — encrypts a Secret's contents with a cluster-specific public key before committing; only the in-cluster Sealed Secrets controller (holding the private key) can decrypt it, so the committed, encrypted `SealedSecret` object is safe to store in Git even in a public repo.
- **External Secrets Operator** — the committed Git object is a reference (e.g., "this Secret's value lives at this AWS Secrets Manager ARN"), not the value itself; the operator fetches the real value live from AWS Secrets Manager/Parameter Store and materializes it as a Kubernetes Secret in-cluster, never storing the actual value in Git at all.

The senior-level preference is generally External Secrets Operator (the value's source of truth remains AWS Secrets Manager, with its own rotation/audit capabilities — see the companion Ansible repository's [Question 48](../../../ansible/ansible-senior-interview-preparation/interview-questions/05-aws-cloud-integration.md#question-48-who-rotates-the-password) credential-rotation-ownership guidance, directly applicable here) over Sealed Secrets, which still requires manual re-sealing on rotation.

## 5. Multi-environment promotion via Kustomize overlays

A GitOps repo typically structures environment differences via Kustomize overlays (`manifests/base/` + `manifests/overlays/{dev,staging,production}/`) — the same base manifests patched per-environment (replica counts, resource limits, environment-specific ConfigMap values), promoted by merging/tagging a change from a lower environment's overlay into a higher one, directly analogous to the companion Ansible repository's `environments/{dev,staging,production}` inventory-per-environment structure and the companion Terraform repository's workspace/environment-directory patterns.

## 6. CI's role in a GitOps world — what's left for a traditional pipeline

With deployment itself handled by the GitOps controller's pull-based reconciliation, the CI pipeline's job narrows to: build and test the application, build and scan/sign the container image, and update the Git repository's manifest/Helm-values with the new image tag (a Git commit, not a cluster deployment) — the actual deployment step is the GitOps controller picking up that commit, not the CI pipeline calling `kubectl` or `helm upgrade` directly. This split (CI updates Git; the GitOps controller applies it) is itself a form of the "review/apply separation" discipline the companion Terraform repository's CI/CD guidance establishes for plan artifacts.

## 7. Drift between the "desired state notion" and what's actually deployed

A subtle multi-layer trap: with progressive delivery (§3), the Rollout resource's *current, in-progress* traffic-split state during a canary is not fully described by Git alone (Git declares the target end-state and rollout strategy; the controller's own live status tracks exactly how far along a specific rollout currently is) — meaning "what's actually serving production traffic right now" during an active canary requires checking the Rollout's live status, not just reading the Git-declared manifest, an important distinction for anyone diagnosing an in-progress deployment issue.

## Common weak vs. senior answers

| Weak answer | Senior answer |
|---|---|
| "GitOps just means we use Git for our YAML files" | Explains the pull-based, continuously-reconciling controller architecture and its self-healing drift correction |
| "We `kubectl apply` from our CI pipeline, that's basically GitOps" | Distinguishes push-based CI-driven deployment from a genuine pull-based, in-cluster reconciling controller |
| "Just base64-encode the secret and commit it, it's fine" | Uses Sealed Secrets or External Secrets Operator; never commits a raw Secret manifest |
| "Canary deployments just mean deploying to a few pods first" | Describes automated, metric-driven traffic-weighted promotion/rollback via Argo Rollouts/Flagger |

## Related material

- [`docs/eks-architecture.md`](eks-architecture.md), [`docs/security.md`](security.md)
- [Lab 10 — GitOps with ArgoCD](../labs/lab-10-gitops-argocd/), [Lab 11 — Progressive Delivery](../labs/lab-11-progressive-delivery/), [Lab 12 — CI/CD Pipeline](../labs/lab-12-cicd-pipeline/)
- Companion: [Ansible Question 48](../../../ansible/ansible-senior-interview-preparation/interview-questions/05-aws-cloud-integration.md), [Terraform CI/CD guidance](../../../terraform/terraform-senior-interview-preparation/)
