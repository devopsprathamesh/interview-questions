# Cheat Sheet: GitOps and CI/CD

## GitOps self-healing — the #1 confusion
A `kubectl scale`/`edit` against a GitOps-managed resource **will be reverted** on the next reconciliation pass if `selfHeal: true`. This is intended behavior, not a bug. The correct emergency action is committing to Git, not fighting the controller.
```bash
git commit -am "Emergency: scale to N replicas" && git push   # correct
kubectl scale deployment X --replicas=N                          # gets reverted
```
[Question 87](../interview-questions/10-cicd-gitops.md#question-87-the-kubectl-apply-that-fought-the-gitops-controller)

## Mutable tags break GitOps's core guarantee
```yaml
image: myapp:latest        # BAD - "Synced" proves nothing about which actual content is running
image: myapp@sha256:abc... # GOOD - immutable, provably consistent
```
[Question 93](../interview-questions/10-cicd-gitops.md#question-93-the-image-tag-that-meant-something-different-every-time)

## Canary analysis must be scoped to the canary
```promql
# BAD - diluted by 90%+ healthy stable traffic
sum(rate(errors{service="x"}[2m])) / sum(rate(requests{service="x"}[2m]))

# GOOD - scoped to the canary's own pod-template-hash
sum(rate(errors{service="x",rollouts_pod_template_hash="{{args.canary-hash}}"}[2m]))
  / sum(rate(requests{service="x",rollouts_pod_template_hash="{{args.canary-hash}}"}[2m]))
```
[Question 89](../interview-questions/10-cicd-gitops.md#question-89-the-analysistemplate-that-measured-the-wrong-thing)

## Manual pause vs. duration-based pause
```yaml
- pause: {}              # indefinite - waits for kubectl argo rollouts promote
- pause: { duration: 30s } # automatic after 30s
```
A rollout stuck at a `pause: {}` step is **stalled by design**, not broken. [Question 88](../interview-questions/10-cicd-gitops.md#question-88-the-canary-that-never-got-promoted)

## CI's role in a GitOps world
Build → test → scan → sign → **commit digest to Git** (never `kubectl apply`/`helm upgrade` directly from CI). The GitOps controller owns the actual deployment step.

## Preventing the artifact-identity race
```yaml
concurrency:
  group: deploy-production
  cancel-in-progress: false   # queue, never interleave concurrent runs
```
Compute the image digest and commit it **within the same CI run** — never a separate, later step that could race with another run. [Question 95](../interview-questions/10-cicd-gitops.md#question-95-the-pipeline-that-tested-the-wrong-artifact)

## Multi-cluster ApplicationSet
A cluster provisioned but never `argocd cluster add`-registered is **invisible** to the `ApplicationSet` cluster generator — silently, with no error. Integrate registration into the same automated pipeline that provisions the cluster. [Question 96](../interview-questions/10-cicd-gitops.md#question-96-the-multi-cluster-app-of-apps-that-only-remembered-one-cluster)

## Rollback: `git revert` isn't always clean
If intervening commits touched the same files, `git revert`'s mechanical diff-reversal can produce an ambiguous result. More reliable: explicitly restore the exact known-good manifest content as a new commit. [Question 97](../interview-questions/10-cicd-gitops.md#question-97-the-rollback-that-wasnt-actually-a-rollback)

## Repo write access = infrastructure control
A GitOps-reconciled repo's write access is functionally equivalent to direct cluster control. Require branch protection (PR review + passing CI) as non-negotiable, and audit for stale access grants the same as any other credential. [Question 98](../interview-questions/10-cicd-gitops.md#question-98-the-gitops-repo-access-that-outlived-its-purpose)
