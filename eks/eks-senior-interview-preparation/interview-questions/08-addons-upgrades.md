# Category 8: Add-ons, Helm, and Cluster/Version Upgrades

Questions 69–78 of 120. Category weight: 10 questions. Deep-dive reference: [`docs/addons-and-upgrades.md`](../docs/addons-and-upgrades.md).

---

## Question 69: The Helm upgrade that silently reverted custom values

### Scenario
A team runs `helm upgrade aws-load-balancer-controller eks/aws-load-balancer-controller --version 1.7.0` to pick up a bug fix, without passing their previously-customized `values.yaml`. After the upgrade, several custom-configured Ingress behaviors (a non-default health-check path, a custom target-group attribute) silently revert to the chart's defaults.

### Interview Question
Explain why this happened and design the correct upgrade process.

### Strong Senior-Level Answer
**Initial assessment:** `helm upgrade` without re-specifying previously-used `--values`/`--set` overrides reverts every unspecified parameter to the chart's own defaults — Helm has no memory of "what custom values were used last time" unless explicitly told again (via `-f values.yaml` or Helm's own stored release values, if using `helm upgrade` correctly against the existing release rather than a fresh values-less invocation).

**Technical reasoning:** each `helm upgrade` invocation computes the new release's manifest from the chart's default `values.yaml` merged with whatever values are explicitly passed *in that specific invocation* — if the custom values aren't passed again, Helm doesn't "remember" and continue applying them from the previous release; it correctly (from its own perspective) applies just the chart defaults for everything not explicitly overridden this time.

**Investigation process:** confirm via `helm get values aws-load-balancer-controller` (checking the *previous* release's recorded values, if still queryable, or via the team's own version-controlled values file if one exists) exactly what custom values were previously in effect, and confirm they weren't included in the upgrade command that was actually run.

**Recommended solution:** always maintain the team's custom values in a version-controlled `values.yaml` file (never only as ad hoc `--set` flags typed at the command line and never recorded anywhere) and always pass it explicitly on every `helm upgrade` invocation (`helm upgrade ... -f values.yaml`) — or, better, manage the Helm release itself via GitOps (an ArgoCD `Application` referencing the chart and a values file in Git), so the values are always applied consistently and automatically, never dependent on a human remembering to pass the right flags on a given command-line invocation.

**Risk controls:** immediately restore the reverted custom configuration (re-running the upgrade with the correct values file) and audit for any other components managed via ad hoc `helm upgrade` commands without a persisted, version-controlled values file, since this exact gap likely isn't unique to this one component.

**Validation steps:** after restoring, confirm the previously-custom-configured behaviors (health-check path, target-group attribute) are indeed back to their intended, non-default state, and confirm future upgrades (tested via a dry-run) correctly preserve them.

**Rollback or recovery strategy:** `helm rollback aws-load-balancer-controller <previous-revision>` can restore the prior release's exact configuration quickly if immediate reversion is needed, buying time to establish the correct, values-file-based process properly.

**Long-term prevention:** migrate every Helm-managed component to GitOps-managed installation (ArgoCD/Flux applying the chart with its values file from Git) so there's no possibility of an ad hoc, values-less `helm upgrade` command ever being run directly against a live cluster again — the same discipline that eliminates manual `kubectl apply` drift risk (per [`docs/cicd-gitops.md`](../docs/cicd-gitops.md) §1) applied specifically to Helm-based components.

### Step-by-Step Implementation
```bash
# Correct: always pass the values file explicitly
helm upgrade aws-load-balancer-controller eks/aws-load-balancer-controller \
  --version 1.7.0 -f values.yaml -n kube-system

# Better: GitOps-managed via ArgoCD, values always applied automatically from Git
```
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: aws-load-balancer-controller
spec:
  source:
    repoURL: https://aws.github.io/eks-charts
    chart: aws-load-balancer-controller
    targetRevision: "1.7.0"
    helm:
      valueFiles: ["values.yaml"]   # from the same Git repo, always applied
```

### Under-the-Hood Explanation
Helm computes each release's rendered manifest fresh at upgrade time from the chart's default values merged with whatever is passed in that specific command — it stores a record of the previous release's *computed* values (queryable via `helm get values`), but this is a historical record, not something automatically reapplied on a subsequent upgrade unless the operator explicitly references it again; Helm's design assumes the operator supplies the complete, correct values on every invocation.

### Common Weak Answer
"Just re-run the upgrade with the old values, Helm should have remembered them."

### Why the Weak Answer Fails
This reflects a mistaken assumption about how Helm actually behaves — it does not persist and automatically reapply previous custom values on a subsequent upgrade unless they're explicitly passed again; understanding this correctly is precisely what prevents the mistake from recurring.

### Follow-Up Questions
1. How would you audit the entire cluster for other Helm releases managed via ad hoc commands without a persisted values file?
2. What's the benefit of GitOps-managed Helm releases specifically for this class of mistake, beyond just "remembering to pass the file"?
3. How would you use `helm diff upgrade` (a plugin) to catch this kind of unintended reversion before it happens, as a pre-upgrade check?

### Key Interview Signals
Correctly explains Helm's actual values-computation model (no automatic persistence/reapplication of previous custom values) and moves toward GitOps-managed Helm releases as the durable fix rather than just "being more careful" with future commands.

### Hands-On Connection
[Lab 4 — Managed Node Groups](../labs/lab-04-managed-node-groups/) and [Lab 10 — GitOps with ArgoCD](../labs/lab-10-gitops-argocd/).

---

## Question 70: The add-on version matrix nobody checked

### Scenario
A team upgrades their EKS cluster's control plane from 1.28 to 1.29, following the correct sequencing. They then upgrade the EKS-managed `vpc-cni` add-on. The self-managed AWS Load Balancer Controller, however, is left at its existing version "since it was working fine before." Two weeks later, newly-created Ingress resources stop provisioning ALBs correctly, with the controller logging API errors.

### Interview Question
Diagnose the delayed failure and connect it to the correct upgrade discipline.

### Strong Senior-Level Answer
**Initial assessment:** per [`docs/addons-and-upgrades.md`](../docs/addons-and-upgrades.md) §2, "it was working fine before the control-plane upgrade" doesn't mean a self-managed add-on remains compatible *after* the control plane's API surface has changed — the Load Balancer Controller's own compatibility matrix against the new 1.29 API version was never checked, and the delayed failure (not immediate) suggests it broke specifically for a new code path (creating new Ingress resources) rather than every function immediately, which is a common, confusing pattern for version-mismatch issues that don't affect every operation uniformly.

**Technical reasoning:** a self-managed controller's compatibility with a given Kubernetes API version isn't guaranteed merely because it continued running without crashing immediately after the control-plane upgrade — some code paths (e.g., watching/reconciling already-existing resources) may continue working fine, while others (e.g., a new API interaction only triggered when creating genuinely new resources) can break specifically due to an API version incompatibility that only manifests when that particular path is exercised.

**Investigation process:** check the AWS Load Balancer Controller's own documented compatibility matrix against Kubernetes 1.29, and compare it to the currently-deployed controller version — this will very likely reveal the controller's currently-running version predates official 1.29 support.

**Recommended solution:** upgrade the AWS Load Balancer Controller to a version confirmed compatible with 1.29 (per its own documented compatibility matrix), following the same reviewed-version-bump discipline as any other Helm-managed component (Question 69), testing in non-production first if at all feasible.

**Risk controls:** treat "the component didn't crash immediately after a control-plane upgrade" as insufficient evidence of genuine compatibility — the correct verification is checking the documented compatibility matrix explicitly, not waiting to see whether something eventually breaks.

**Validation steps:** after upgrading the controller, confirm new Ingress resources provision ALBs correctly, and confirm existing, already-provisioned ALBs continue functioning without disruption from the controller upgrade itself.

**Rollback or recovery strategy:** if the controller upgrade itself introduces an unexpected issue, `helm rollback` to the previous controller version while investigating further — though remaining on an incompatible version isn't a viable long-term option regardless.

**Long-term prevention:** institutionalize the full upgrade-sequencing checklist (per [`docs/addons-and-upgrades.md`](../docs/addons-and-upgrades.md) §2 and [`diagrams/09-cluster-upgrade-sequencing.md`](../diagrams/09-cluster-upgrade-sequencing.md)) as a mandatory, checked step for every control-plane version bump — explicitly verifying every self-managed add-on's compatibility matrix, not just the EKS-managed ones, before considering the upgrade complete.

### Step-by-Step Implementation
```bash
# Check the currently-deployed controller version
kubectl get deployment aws-load-balancer-controller -n kube-system -o jsonpath='{.spec.template.spec.containers[0].image}'

# Cross-reference against the project's documented Kubernetes-version compatibility matrix
# then upgrade to a confirmed-compatible version
helm upgrade aws-load-balancer-controller eks/aws-load-balancer-controller --version 1.8.0 -f values.yaml -n kube-system
```

### Under-the-Hood Explanation
A control-plane API version bump can change or deprecate specific API fields/behaviors a self-managed controller depends on for particular operations — a controller built against an older API's assumptions might continue functioning for code paths that don't touch the changed surface, while failing specifically on paths that do, producing exactly this delayed-and-partial rather than immediate-and-total failure pattern, which makes it easy to mistakenly conclude "the upgrade didn't affect this component" based on initial, incomplete observation.

### Common Weak Answer
"It was still running without errors right after the upgrade, so it must be compatible."

### Why the Weak Answer Fails
Absence of an immediate crash doesn't confirm genuine compatibility — as this scenario demonstrates, a version mismatch can manifest only for specific, less-frequently-exercised code paths, meaning "no immediate error" is not equivalent to "confirmed compatible," and the only reliable check is the documented compatibility matrix itself.

### Follow-Up Questions
1. How would you build automated tooling checking every self-managed add-on's compatibility against a planned control-plane version bump before executing it?
2. What's the risk of leaving a component on an unsupported-for-current-cluster-version state even if it appears to be "working"?
3. How would you design canary testing (in a non-production cluster) to catch this exact delayed-failure pattern before it reaches production?

### Key Interview Signals
Understands that "no immediate crash" doesn't confirm compatibility, and traces a delayed, partial failure back to an unchecked self-managed add-on compatibility matrix rather than treating it as a mysterious, unrelated new issue.

### Hands-On Connection
[Lab 4 — Managed Node Groups](../labs/lab-04-managed-node-groups/) and [Lab 7 — Ingress and Load Balancing](../labs/lab-07-ingress-and-load-balancing/).

---

## Question 71: The deprecated API that hid in a Helm chart, not your own manifests

### Scenario
A team runs `pluto detect-files` against their own Git repository ahead of a planned Kubernetes upgrade and finds zero deprecated API usage — giving them confidence to proceed. The upgrade nonetheless breaks a third-party Helm chart (an observability agent) they didn't author, which internally templates a now-removed API version.

### Interview Question
Explain the gap in their pre-upgrade validation process and fix it.

### Strong Senior-Level Answer
**Initial assessment:** scanning only the team's own authored manifests misses deprecated/removed API usage inside any third-party Helm chart's own templates — a chart's rendered output can reference a removed API version even if none of the team's own YAML does, and `pluto detect-files` against a source repository that doesn't include the chart's actual templates (only, perhaps, the team's own `values.yaml` overrides) won't catch this.

**Technical reasoning:** deprecated-API scanning needs to run against the *actual rendered manifests* that will be applied to the cluster — for Helm-based components, that means running the scan against `helm template`'s output (the fully rendered YAML, incorporating the chart's own internal templates plus the team's values overrides), not just the team's own hand-authored source files, which is a meaningfully different and larger surface.

**Investigation process:** confirm exactly what `pluto detect-files` was pointed at in the original scan — very likely just the team's own Git repository containing values files and their own manifests, not the third-party chart's actual template output, which explains the false confidence.

**Recommended solution:** extend the pre-upgrade validation process to run `pluto detect-helm` (or an equivalent tool specifically designed to scan rendered Helm output) against every installed Helm release in the cluster, in addition to scanning the team's own authored manifests — covering the full actual set of resources that will be applied, not just what the team directly wrote.

**Risk controls:** for any flagged third-party chart, check whether a newer chart version resolves the deprecated API usage before the planned upgrade, and if not, engage with the chart's maintainers/community or plan a temporary workaround (e.g., pinning the control-plane upgrade until a compatible chart version is available, if the affected component is critical).

**Validation steps:** after extending the scan to cover rendered Helm output and (if needed) upgrading the affected chart, re-run the full pre-upgrade validation and confirm zero deprecated API usage across the *complete* actual manifest set, not just the team's own portion.

**Rollback or recovery strategy:** if the upgrade already proceeded and broke the observability agent, the immediate fix is upgrading that specific chart to a compatible version (following the standard Helm upgrade discipline from Question 69) rather than attempting to roll back the control-plane version.

**Long-term prevention:** institutionalize scanning *rendered* manifests (via `helm template` output or `pluto detect-helm`, covering every installed release, self-managed or third-party) as a standard part of every pre-upgrade validation checklist — treating "our own manifests are clean" as necessary but explicitly insufficient for a complete pre-upgrade check.

### Step-by-Step Implementation
```bash
# Insufficient: only scans the team's own authored files
pluto detect-files -d ./our-manifests

# Correct: scan against every installed Helm release's ACTUAL rendered output
pluto detect-helm --helm3 -n kube-system   # covers third-party chart templates too
```

### Under-the-Hood Explanation
A Helm chart's templates can reference any API version the chart author chose, entirely independently of what the consuming team's own `values.yaml` overrides express — scanning only the team's own repository never sees this internal chart content at all; only scanning the actual rendered output (post-templating) reveals the complete, real set of API versions that will be submitted to the cluster during the upgrade.

### Common Weak Answer
"We scanned our repo and found nothing, so we should be safe to proceed."

### Why the Weak Answer Fails
This assumes the team's own authored files represent the complete set of manifests being applied to the cluster — for any Helm-managed (or Kustomize-generated, or otherwise templated) component, the actual applied output can differ substantially from what's visible in the team's own source repository, exactly as this incident demonstrates.

### Follow-Up Questions
1. How would you extend this rendered-manifest-scanning discipline to Kustomize-based overlays as well, not just Helm charts?
2. What's your process for engaging with a third-party chart maintainer when their chart itself needs updating for compatibility?
9. How would you build this rendered-output scanning into a standing CI check, not just a one-time pre-upgrade manual step?

### Key Interview Signals
Recognizes that deprecated-API scanning must cover the actual rendered manifest output (including third-party chart internals), not just the team's own authored source files, closing a real and easy-to-miss pre-upgrade validation gap.

### Hands-On Connection
[Lab 4 — Managed Node Groups](../labs/lab-04-managed-node-groups/) and [Lab 9 — Observability Stack](../labs/lab-09-observability-stack/).

---

## Question 72: The CRD that the upgrade left behind

### Scenario
A team fully uninstalls an old observability agent (via `helm uninstall`) as part of migrating to a new one. Months later, `kubectl get events` shows repeated failed reconciliation attempts referencing a CRD (`ServiceMonitor`) that seemingly still exists, even though nothing appears to use it anymore, and a cluster upgrade later fails validation due to a stale, incompatible version of this same CRD.

### Interview Question
Explain why the CRD persisted after `helm uninstall`, and design the correct cleanup process.

### Strong Senior-Level Answer
**Initial assessment:** Helm, by design, does **not** delete CustomResourceDefinitions on `helm uninstall` by default — this is a deliberate safety choice (deleting a CRD cascades to deleting every custom resource instance of that type across the entire cluster, including ones potentially owned by a completely different, unrelated release), meaning the CRD (and any leftover custom resources of that type) persist indefinitely unless explicitly, separately cleaned up.

**Technical reasoning:** if a different tool/release (e.g., a separate Prometheus Operator installation, or the new observability agent itself) still expects to own and manage this CRD, an old, stale, incompatible version left behind by the previous tool's uninstall can conflict with what the new tool expects, exactly producing the described reconciliation failures and later upgrade-validation issues.

**Investigation process:** confirm via `kubectl get crd servicemonitors.monitoring.coreos.com -o yaml` the CRD's current version/schema, and confirm whether any current, actively-used component (the new observability agent, or anything else) depends on this CRD existing in a specific, different version/schema than what's currently present.

**Recommended solution:** if genuinely no current component needs this CRD (confirmed, not assumed), manually delete it (`kubectl delete crd servicemonitors.monitoring.coreos.com`) — being aware this cascades to deleting any remaining custom resources of that type, which should also be confirmed as safe/expected first; if a current component *does* need this CRD but expects a different version, ensure that component's own installation process manages the CRD's version correctly (many Helm charts now include CRD management as an explicit, separate step specifically because of this exact default-uninstall behavior).

**Risk controls:** before deleting any CRD, exhaustively check for any resource instances of that type still present across the *entire* cluster (`kubectl get servicemonitors -A`), and confirm with every team that might plausibly still depend on it — a CRD deletion's cascading effect can silently break an entirely unrelated team's monitoring configuration if not carefully checked first.

**Validation steps:** after cleanup, confirm the previously-failing reconciliation errors stop occurring, and confirm the cluster upgrade's CRD-validation check now passes.

**Rollback or recovery strategy:** if a CRD deletion turns out to have removed custom resources still needed by an active, previously-unnoticed dependent, those resources would need to be recreated from their original source (a GitOps repository, if managed that way, or manually reconstructed) — another reason for exhaustive pre-deletion verification rather than an optimistic assumption.

**Long-term prevention:** treat CRD lifecycle as a distinct, explicit consideration whenever uninstalling or migrating any Helm-managed component that includes CRDs — never assume `helm uninstall` fully removes everything a chart installed, and build CRD-cleanup verification into the standard decommissioning checklist for any such migration.

### Step-by-Step Implementation
```bash
# Check for any remaining resources of this type across the entire cluster before any deletion
kubectl get servicemonitors -A

# If confirmed safe, delete the stale CRD explicitly (helm uninstall does not do this)
kubectl delete crd servicemonitors.monitoring.coreos.com
```

### Under-the-Hood Explanation
Helm's uninstall process removes the resources it tracks as part of the release's own manifest set, but CRDs installed via a chart's `crds/` directory (the standard convention) are explicitly excluded from Helm's automatic delete-on-uninstall behavior — a deliberate design decision documented in Helm's own docs, specifically to avoid the catastrophic, cluster-wide cascading deletion risk that automatic CRD removal would otherwise create for any other release depending on the same CRD.

### Common Weak Answer
"helm uninstall should have removed everything the chart installed, this must be a bug."

### Why the Weak Answer Fails
This is documented, intentional Helm behavior, not a bug — CRDs are deliberately excluded from automatic uninstall cleanup specifically because of their cluster-wide, cross-release blast radius if deleted automatically and unconditionally; understanding this correctly is what leads to the appropriately careful, explicit cleanup process rather than assuming a defect.

### Follow-Up Questions
1. How would you build a standing audit catching CRDs left behind by past uninstalls across the cluster's full history?
2. What's the specific risk of deleting a CRD that's still depended on by a completely unrelated team's workloads?
3. How do modern Helm charts increasingly handle CRD versioning/management differently to avoid this exact class of issue?

### Key Interview Signals
Correctly identifies Helm's deliberate CRD-exclusion-from-uninstall behavior (not a bug) and designs a careful, exhaustively-verified cleanup process respecting the cascading-deletion risk CRDs carry.

### Hands-On Connection
[Lab 9 — Observability Stack](../labs/lab-09-observability-stack/).

---

## Question 73: The add-on that needed a node it couldn't get

### Scenario
The `aws-efs-csi-driver` EKS-managed add-on is enabled on a cluster whose node groups are all tainted for specific workload dedication (per Question 55's pattern), with no toleration for the EFS CSI driver's own DaemonSet. EFS-backed PVCs across the cluster fail to mount, with no immediately obvious connection to the taint configuration.

### Interview Question
Diagnose this interaction between add-on deployment and custom taint configuration.

### Strong Senior-Level Answer
**Initial assessment:** the EFS CSI driver deploys its own controller and node-level DaemonSet components — if every node group in the cluster is tainted (for legitimate workload-dedication reasons) without a corresponding toleration for the CSI driver's own DaemonSet, that DaemonSet simply can't schedule onto *any* node, meaning no node actually has the CSI driver's node component running to handle mount operations, causing every EFS-backed PVC mount to fail cluster-wide.

**Technical reasoning:** EKS-managed add-ons don't automatically override or account for cluster-specific taint configurations applied after the fact — the add-on's DaemonSet is subject to the exact same scheduling rules as any other DaemonSet, meaning it needs an explicit toleration for every taint present in the cluster if it's expected to run on every node (which the CSI driver's node component generally needs to, to handle mounts on whichever node a pod happens to land on).

**Investigation process:** confirm via `kubectl get pods -n kube-system -l app=efs-csi-node` that the DaemonSet's pods show zero or partial scheduling across the fleet, and cross-reference against the actual taints present on the cluster's node groups — settling that this is a taint/toleration scheduling gap, not a genuine CSI driver malfunction.

**Recommended solution:** add tolerations to the EFS CSI driver's DaemonSet (via the EKS add-on's configuration values, which typically expose a tolerations override) matching every taint present across the cluster's node groups, ensuring the driver's node component can schedule onto every node that might need to mount an EFS volume.

**Risk controls:** whenever introducing a new cluster-wide taint (for any future workload-dedication purpose), explicitly check whether any existing DaemonSet-based add-on (CNI, CSI drivers, log shippers, security agents) needs a corresponding toleration added — this exact class of interaction is easy to miss when taint changes and add-on configuration are managed by different teams/processes.

**Validation steps:** after adding the toleration, confirm the EFS CSI driver's DaemonSet pods now run on every relevant node, and confirm previously-failing EFS-backed PVC mounts now succeed.

**Rollback or recovery strategy:** removing the taint (if it wasn't genuinely necessary) is an alternative fix direction, but generally the correct approach is adding the toleration to the add-on rather than removing a taint that serves its own legitimate purpose.

**Long-term prevention:** maintain a standing checklist item — "does every cluster-wide-necessary DaemonSet-based add-on have tolerations for every current taint" — reviewed whenever either taints or add-on configuration change, since this interaction spans two areas of configuration that are easy to manage in isolation without considering their combined effect.

### Step-by-Step Implementation
```bash
aws eks update-addon --cluster-name my-cluster --addon-name aws-efs-csi-driver \
  --configuration-values '{"node":{"tolerations":[{"operator":"Exists"}]}}'
```

### Under-the-Hood Explanation
The EFS CSI driver's node-level component runs as a DaemonSet, subject to the exact same scheduler filtering as any other pod — a taint without a matching toleration on this DaemonSet's pod spec means the scheduler correctly refuses to place it on the tainted nodes, exactly as the taint mechanism is designed to do, with no special-case exception for add-on-provided DaemonSets unless explicitly configured with the necessary tolerations.

### Common Weak Answer
"The EFS CSI driver must just be broken, reinstall the add-on."

### Why the Weak Answer Fails
Reinstalling the add-on doesn't change its DaemonSet's scheduling eligibility against the cluster's existing taints — the same scheduling gap would immediately recur post-reinstall, since the actual cause (missing tolerations relative to the cluster's taint configuration) is unaffected by simply reinstalling the same, unmodified add-on configuration.

### Follow-Up Questions
1. How would you design a standing check catching this class of taint/add-on-toleration mismatch automatically, across any future taint changes?
2. What's the difference in this interaction for a Karpenter-managed fleet versus a static managed-node-group fleet?
3. How would you extend this same toleration check to other DaemonSet-based components (Fluent Bit, Falco, VPC CNI itself)?

### Key Interview Signals
Correctly diagnoses the taint/toleration scheduling interaction between a cluster-wide configuration change and an add-on's own DaemonSet, rather than assuming the add-on itself is malfunctioning.

### Hands-On Connection
[Lab 4 — Managed Node Groups](../labs/lab-04-managed-node-groups/) and [Lab 6 — Storage: EBS/EFS CSI](../labs/lab-06-storage-ebs-efs-csi/).

---

## Question 74: Canarying a cluster upgrade

### Scenario
An organization operates 20 production EKS clusters running the same general workload types (a standardized platform, per Question 7's shared-platform pattern from Category 1, applied at larger scale). They ask how to safely roll out a Kubernetes minor-version upgrade across all 20 without risking a simultaneous, fleet-wide incident if the upgrade reveals an unexpected issue.

### Interview Question
Design a staged, canary-based upgrade rollout process across this fleet.

### Strong Senior-Level Answer
**Initial assessment:** upgrading all 20 clusters simultaneously (or even in immediate rapid succession) risks exactly the same blast-radius problem as any other unstaged, fleet-wide change — the correct approach mirrors the companion Terraform/Ansible repositories' canary-and-stage discipline, applied to Kubernetes version upgrades specifically across a cluster fleet rather than a single cluster's node group.

**Technical reasoning:** even after thorough non-production testing (per earlier questions in this category — deprecated-API scanning, add-on compatibility checks), a genuinely novel issue can still surface only under real, full production traffic/workload diversity across many different teams' actual usage patterns — staging the rollout across the fleet, not just across environments, catches this category of "only shows up at real production scale/diversity" issue before it's fleet-wide.

**Investigation process:** categorize the 20 clusters by risk tolerance/criticality (which clusters, if briefly disrupted by an unexpected upgrade issue, would have the least severe business impact) — this determines a sensible canary ordering, upgrading lowest-risk-tolerance-impact clusters first.

**Recommended solution:** stage the rollout in cohorts: first, a single lowest-impact production cluster (canary), monitored closely for a defined bake period (e.g., 3-5 days of full, real traffic) before proceeding; then a small second cohort of moderate-impact clusters; only once both stages show no unexpected issues, proceed to the remaining, higher-impact clusters, still not all simultaneously but in a final, larger but still-paced cohort.

**Risk controls:** define clear, objective criteria for "the canary stage succeeded, proceed to the next cohort" (specific metrics/error-rate thresholds, not just "nothing was reported as broken") before starting the rollout, so the decision to proceed at each stage is consistent and evidence-based rather than subjective.

**Validation steps:** at each cohort stage, monitor the same upgrade-relevant signals (add-on health, application error rates, node-group health) established throughout this category, comparing against each cluster's own pre-upgrade baseline.

**Rollback or recovery strategy:** if the canary stage reveals an issue, halt the rollout entirely across all remaining clusters, diagnose and fix the issue (informed by everything covered in this category — sequencing, add-on compatibility, deprecated APIs), and only resume the staged rollout once resolved and re-validated on the canary cluster.

**Long-term prevention:** institutionalize this staged, cohort-based rollout process as the standard for *any* fleet-wide change (not just Kubernetes version upgrades) — the same discipline applies to add-on version bumps, security-policy baseline updates (per Question 68), and any other change with fleet-wide reach.

### Step-by-Step Implementation
```text
Cohort 1 (canary): 1 lowest-business-impact production cluster
  -> bake period: 3-5 days full production traffic, monitored against defined thresholds

Cohort 2: 4-5 moderate-impact clusters
  -> bake period: 3-5 days

Cohort 3: remaining ~14 clusters, still paced (not simultaneous)
  -> completed once Cohort 2 shows no issues
```

### Under-the-Hood Explanation
This staged approach treats the cluster fleet itself as the unit of canary deployment, directly analogous to how a canary/blue-green deployment (per [`docs/cicd-gitops.md`](../docs/cicd-gitops.md) §3) stages a *workload* rollout across a traffic percentage — here, the "traffic percentage" is expressed as a subset of the fleet, with the same underlying principle: real production conditions (which non-production testing can't fully replicate) are the actual final validation, so exposure to that validation should be staged and reversible, not all-at-once.

### Common Weak Answer
"Since we tested thoroughly in non-production, it's safe to upgrade all 20 clusters together to save time."

### Why the Weak Answer Fails
Non-production testing, however thorough, cannot fully replicate the diversity and scale of real production traffic across 20 different teams' actual usage patterns — the entire point of a staged, fleet-level canary rollout is catching exactly the class of issue that only manifests under genuine production conditions, which simultaneous fleet-wide upgrade forgoes entirely in exchange for time savings.

### Follow-Up Questions
1. How would you define objective, automated go/no-go criteria for advancing from one cohort to the next, rather than relying on subjective judgment?
2. How would you communicate this staged timeline to the 20 different teams whose clusters are affected, especially those in later cohorts waiting longer?
3. How would you apply this same staged-fleet-rollout thinking to a security-policy baseline update (Question 68) across the same 20 clusters?

### Key Interview Signals
Applies the canary/staged-rollout principle established elsewhere in this repository series at the fleet level (clusters as the unit of staging), with objective, evidence-based criteria for advancing between cohorts.

### Hands-On Connection
[Lab 4 — Managed Node Groups](../labs/lab-04-managed-node-groups/) and [Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).

---

## Question 75: The chart dependency graph nobody drew

### Scenario
A platform team maintains an umbrella Helm chart bundling five sub-charts (each a different internal platform component) as dependencies. Upgrading one sub-chart's version to fix a bug breaks a different sub-chart, which turns out to depend on an undocumented, implicit assumption about the first sub-chart's previous behavior.

### Interview Question
Diagnose this coupling and design a process preventing this class of surprise.

### Strong Senior-Level Answer
**Initial assessment:** an undocumented, implicit dependency between two supposedly-independent sub-charts is a hidden coupling that only surfaces when one side changes — exactly the kind of "nobody knew this dependency existed until it broke" gap the companion Ansible repository's role-dependency guidance ([Question 27](../../../ansible/ansible-senior-interview-preparation/interview-questions/03-roles-collections.md#question-27-the-role-that-only-told-you-the-port)) addresses for role outputs, applied here to Helm sub-chart interdependencies.

**Technical reasoning:** Helm's own dependency mechanism (`Chart.yaml`'s `dependencies` list) tracks *chart-level* dependencies (which sub-charts are bundled), but has no built-in mechanism to express or enforce *behavioral* dependencies between sub-charts (e.g., "sub-chart B's controller assumes sub-chart A's CRD is present with a specific schema/field") — this class of implicit coupling exists entirely outside what Helm itself tracks or validates.

**Investigation process:** trace exactly what specific behavior/assumption the second sub-chart depended on from the first, and confirm this was genuinely undocumented (not just overlooked in a change review) — informing both the immediate fix and the broader question of what other undocumented couplings might exist among the remaining sub-charts.

**Recommended solution:** immediately, either revert the breaking sub-chart version bump or fix the now-incompatible assumption in the dependent sub-chart; going forward, document every actual behavioral dependency between sub-charts explicitly (in the umbrella chart's own README/architecture docs) and, more robustly, add integration tests (via a Molecule-equivalent test harness, or a dedicated CI job deploying the full umbrella chart and verifying cross-component behavior) that would have caught this exact breakage before release.

**Risk controls:** treat any sub-chart version bump within an umbrella chart with interdependent components as requiring the full umbrella chart's integration test suite to pass, not just the individually-bumped sub-chart's own isolated tests — isolated testing is exactly what missed this cross-component coupling.

**Validation steps:** after the fix, add a specific regression test covering this exact cross-component behavior, and confirm the full umbrella chart's integration tests pass before considering the incident resolved.

**Rollback or recovery strategy:** `helm rollback` the umbrella chart release to the previous, known-working version combination while the fix/integration-test-addition is properly completed.

**Long-term prevention:** maintain an explicit, documented dependency map among the umbrella chart's sub-charts (which components have runtime/behavioral dependencies on others, not just Helm's own chart-bundling dependency list) and require this map to be updated and integration tests to pass as part of any sub-chart version bump's review process — never allowing a sub-chart to be bumped in isolation without considering its actual behavioral coupling to siblings.

### Step-by-Step Implementation
```yaml
# Umbrella chart's own integration test - deploys the FULL bundle and verifies cross-component behavior
# (conceptual CI step, not just per-sub-chart isolated testing)
helm install platform-umbrella ./umbrella-chart -f test-values.yaml
kubectl wait --for=condition=ready pod -l app=sub-chart-b --timeout=120s
# then assert the specific cross-component behavior that previously broke
```

### Under-the-Hood Explanation
Helm's dependency graph is purely about chart *composition* (which sub-charts are templated together into one release) — it has no concept of, and performs no validation against, runtime behavioral assumptions one sub-chart's controller might make about another's CRDs, APIs, or conventions; this entire class of coupling is invisible to Helm itself and only discoverable through either explicit documentation/review or actual integration testing exercising the real cross-component interaction.

### Common Weak Answer
"Just pin every sub-chart's version and never upgrade any of them."

### Why the Weak Answer Fails
This avoids the immediate risk by avoiding all future upgrades entirely, forgoing legitimate bug fixes and security patches indefinitely — the sustainable fix is making the hidden coupling visible and tested (documentation plus integration tests), not freezing the entire umbrella chart in place forever.

### Follow-Up Questions
1. How would you systematically discover other undocumented behavioral couplings among the remaining sub-charts before they cause a similar surprise?
2. What's the right cadence/trigger for running the full umbrella chart's integration test suite — every sub-chart bump, or only some?
3. How does this scenario relate to the companion Ansible repository's role-dependency and "role that only told you the port" guidance?

### Key Interview Signals
Identifies undocumented behavioral coupling (distinct from Helm's own tracked chart-composition dependencies) as the actual root cause, and designs both documentation and integration testing as the durable fix.

### Hands-On Connection
[Lab 9 — Observability Stack](../labs/lab-09-observability-stack/) and [Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).

---

## Question 76: The extended support clock nobody was watching

### Scenario
A cluster remains on a Kubernetes minor version that reached its end of standard support eight months ago, now running under AWS's paid extended support pricing, discovered only when a finance team flags an unexpected new line item on the AWS bill.

### Interview Question
Design a process ensuring this doesn't happen silently again.

### Strong Senior-Level Answer
**Initial assessment:** this is a monitoring/process gap, not a technical failure — EKS's extended support mechanism worked exactly as designed (keeping the cluster running rather than forcing a disruptive, unplanned upgrade at the standard-support cutoff), but nobody was tracking the approaching end-of-standard-support date proactively, so the cost consequence arrived as a surprise rather than a planned, budgeted decision.

**Technical reasoning:** AWS publishes each Kubernetes version's end-of-standard-support date well in advance, and EKS itself doesn't force an immediate upgrade at that boundary — it simply begins billing at the extended-support rate, meaning the *only* signal something changed is the cost itself, unless a team is actively tracking version lifecycle dates independent of billing.

**Investigation process:** confirm exactly which clusters (likely not just this one) are currently on versions approaching or past their standard-support end date — a fleet-wide audit, not just addressing this one flagged cluster.

**Recommended solution:** upgrade this cluster (and any others in the same situation) to a currently-supported version, following the full sequencing discipline established throughout this category, and establish a standing, automated tracking mechanism (alerting a defined number of months before each running cluster's version reaches end-of-standard-support) so future upgrades are planned and executed proactively, never discovered reactively via a billing surprise.

**Risk controls:** treat "on extended support" as itself a signal warranting priority remediation, not just cost awareness — extended support often means fewer patch/security updates for that version going forward, a security posture consideration beyond just the cost angle.

**Validation steps:** after the upgrade, confirm the cluster is on a currently-supported version and confirm the new tracking/alerting mechanism correctly identifies the cluster's updated status.

**Rollback or recovery strategy:** not directly applicable — this is a remediation and process-improvement exercise, not something requiring its own rollback consideration.

**Long-term prevention:** implement automated, proactive alerting (e.g., a scheduled script checking every cluster's current version against AWS's published end-of-standard-support calendar, alerting several months ahead) as a standing platform-operations practice, ensuring version-lifecycle awareness is never solely dependent on someone happening to notice a bill anomaly.

### Step-by-Step Implementation
```bash
# Fleet-wide check against AWS's published EKS version support calendar
for cluster in $(cat clusters.txt); do
  version=$(aws eks describe-cluster --name "$cluster" --query 'cluster.version' --output text)
  echo "$cluster: $version"
done
# Cross-reference against https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html
# and alert for any cluster within, say, 3 months of its version's end-of-standard-support date
```

### Under-the-Hood Explanation
EKS's extended support model is a deliberate design choice giving customers flexibility to delay a disruptive upgrade past the standard support window, at a cost premium — it's not a failure mode or an error condition, and nothing about the cluster's own operation signals this transition happened except the billing change itself, meaning proactive, calendar-based tracking (external to the cluster's own operational signals) is the only way to avoid discovering this reactively.

### Common Weak Answer
"Just upgrade the cluster now that we noticed, and move on."

### Why the Weak Answer Fails
Fixing this one cluster doesn't address whether other clusters in the fleet are in the same situation, nor does it establish any mechanism preventing the same reactive-discovery-via-billing-surprise pattern from recurring for this or any other cluster in the future.

### Follow-Up Questions
1. How would you prioritize which clusters to upgrade first if a fleet-wide audit reveals several are on extended support simultaneously?
2. What's the security-posture argument (beyond cost) for staying current versus relying on extended support?
3. How would you integrate this version-lifecycle tracking into the same platform observability/alerting stack covered in `docs/observability.md`?

### Key Interview Signals
Recognizes this as a proactive-monitoring gap rather than a one-off technical issue, and designs a standing, calendar-based tracking mechanism rather than just remediating the single flagged cluster.

### Hands-On Connection
[Lab 4 — Managed Node Groups](../labs/lab-04-managed-node-groups/) and [Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).

---

## Question 77: The add-on config that drifted from Terraform's idea of it

### Scenario
A team manages the `vpc-cni` EKS-managed add-on's configuration both via Terraform (`aws_eks_addon` with `configuration_values`) and, separately, via a well-meaning engineer's direct `kubectl edit` on the underlying `aws-node` DaemonSet during an incident, to quickly test a fix. The `kubectl edit` change works and is never reverted. The next `terraform apply` shows no diff at all, yet the cluster's actual behavior no longer matches what the Terraform configuration describes.

### Interview Question
Explain why Terraform shows no drift despite the actual configuration having changed, and fix the gap.

### Strong Senior-Level Answer
**Initial assessment:** this is a scope-of-management-visibility gap — Terraform's `aws_eks_addon` resource tracks the add-on's configuration *as expressed through the EKS API* (`configuration_values`), but a direct `kubectl edit` on the underlying Kubernetes DaemonSet object modifies the *actual running Kubernetes resource* through a completely different path (the Kubernetes API directly, bypassing the EKS add-on API entirely) — Terraform's state has no visibility into this second path at all, so it correctly sees no diff in what *it* manages, while the cluster's real behavior has diverged.

**Technical reasoning:** EKS-managed add-ons expose a *subset* of their full configuration surface through the `configuration_values` JSON schema Terraform interacts with — a direct edit to the underlying DaemonSet can change settings entirely outside that exposed subset (or even override something within it, depending on the add-on's own reconciliation behavior), and Terraform's plan/diff logic only ever compares against what it itself is tracking, with zero awareness of changes made through an entirely separate API path.

**Investigation process:** confirm via `kubectl get daemonset aws-node -n kube-system -o yaml` exactly what was changed via the direct edit, and compare against what the `aws_eks_addon` Terraform resource's `configuration_values` currently expresses — this confirms the specific out-of-band change and its scope.

**Recommended solution:** revert the ad hoc `kubectl edit` change (restoring the DaemonSet to match what the add-on's actual, Terraform-managed configuration should produce) — or, if the change genuinely represents a needed, permanent fix, properly incorporate it into the Terraform-managed `configuration_values` (if the add-on's configuration schema supports expressing it that way) so it's captured in version-controlled, reviewed configuration rather than an untracked, out-of-band edit.

**Risk controls:** treat any direct `kubectl edit`/`kubectl patch` against a resource that's also managed by Terraform (or any other declarative tool) as inherently risky and, during an incident, explicitly temporary — document it clearly as a stopgap and track its reversion as an explicit follow-up task, never leaving it in place indefinitely without deliberately incorporating it into the proper managed configuration.

**Validation steps:** after reconciling (either reverting the manual edit or properly incorporating it into Terraform), confirm the DaemonSet's actual configuration now genuinely matches both Terraform's state and the intended, reviewed configuration — not just that `terraform plan` shows no diff (which, as this incident demonstrates, can be misleadingly clean even when real drift exists outside Terraform's tracked scope).

**Rollback or recovery strategy:** if the manual change's removal causes the original incident's symptom to recur, that's a signal the fix genuinely needs to be permanent — properly incorporate it into Terraform-managed configuration rather than leaving it as an untracked manual edit indefinitely.

**Long-term prevention:** establish a strict policy that any incident-driven manual change to a Terraform-managed (or GitOps-managed) resource is explicitly tracked as temporary, with a required follow-up ticket to either revert or properly incorporate it into the managed configuration within a defined window — never allowing an "it worked, leave it" outcome to persist silently, exactly the gap that caused Terraform's plan to appear clean while reality had diverged.

### Step-by-Step Implementation
```bash
# Confirm the actual drift outside Terraform's visibility
kubectl get daemonset aws-node -n kube-system -o yaml > actual-state.yaml
terraform show -json | jq '.values.root_module.resources[] | select(.address=="aws_eks_addon.vpc_cni")' > terraform-tracked-state.json
# Compare manually - Terraform's clean "no diff" doesn't mean no real-world drift exists
```

### Under-the-Hood Explanation
Terraform's drift detection works by comparing its own state file against the *current value of the specific attributes it manages*, retrieved via the same API path it uses to manage the resource (the EKS add-on API, in this case) — it has no mechanism to detect changes made through an entirely different API path (direct Kubernetes API edits to the underlying DaemonSet) that fall outside what the `aws_eks_addon` resource's own attribute set represents, which is exactly why `terraform plan` can show a deceptively clean "no changes" result even when the actual, real-world configuration has genuinely diverged.

### Common Weak Answer
"If Terraform shows no diff, the configuration must be exactly what we expect."

### Why the Weak Answer Fails
This trusts Terraform's diff as a complete picture of the resource's actual state, when Terraform can only ever compare against the specific attributes it directly manages through its own API path — a change made through a different path entirely (direct `kubectl edit` on the underlying Kubernetes object) is invisible to this comparison, exactly as this incident demonstrates.

### Follow-Up Questions
1. How would you build a monitoring/audit process that catches drift outside Terraform's own tracked scope, specifically for Kubernetes resources also managed by EKS add-ons?
2. What's the broader lesson here about trusting a management tool's own drift-detection as a complete signal of real-world state?
3. How would you have handled the original incident differently to avoid needing this direct `kubectl edit` in the first place?

### Key Interview Signals
Correctly explains why Terraform's clean diff doesn't guarantee no real-world drift exists, tracing the gap to two separate API paths managing overlapping but not identical scope, and designs process controls preventing untracked manual changes from persisting silently.

### Hands-On Connection
[Lab 1 — Cluster Bootstrap](../labs/lab-01-cluster-bootstrap/) and [Lab 4 — Managed Node Groups](../labs/lab-04-managed-node-groups/).

---

## Question 78: One upgrade calendar, twenty teams

### Scenario
Twenty independent application teams share the 20-cluster platform from Question 74. Each has different release schedules, freeze windows, and risk tolerances. The platform team is designing the annual Kubernetes-upgrade communication/scheduling process and asks how to balance platform-wide upgrade needs against each team's own autonomy and constraints.

### Interview Question
Design this cross-team upgrade coordination process.

### Strong Senior-Level Answer
**Initial assessment:** this is fundamentally a communication and scheduling-coordination challenge layered on top of the technical staged-rollout process from Question 74 — the platform team needs enough lead time and clear enough communication that each application team can plan around their own constraints, while the platform team still maintains enough control to avoid indefinite delay (since every version eventually reaches its end-of-standard-support date, per Question 76).

**Technical reasoning:** a purely platform-team-driven, non-negotiable schedule risks colliding with a team's own critical release window or freeze period; a purely opt-in, whenever-each-team-is-ready approach risks the same "extended support cost surprise" (Question 76) at fleet scale, with some teams perpetually delaying — the correct balance provides a firm overall timeline (driven by the actual end-of-standard-support deadline, working backward with appropriate margin) while giving each team meaningful input into their *specific* slot within that timeline.

**Investigation process:** gather each of the 20 teams' own constraints (known freeze windows, major release dates, risk tolerance) well in advance of the planned upgrade window, feeding into the cohort assignment from Question 74's staged rollout (teams with tighter constraints can be placed in whichever cohort best avoids their freeze windows, while the overall cohort *order* still follows the risk-based canary-first logic).

**Recommended solution:** publish an annual upgrade calendar significantly in advance (informed by AWS's own published version-release/support-lifecycle calendar), soliciting each team's constraint input for cohort placement within a defined overall window, but with a firm final deadline for every cluster to be upgraded before reaching end-of-standard-support — balancing flexibility in *when within the window* against a non-negotiable *by when* the whole fleet must be current.

**Risk controls:** for any team requesting an exception pushing them uncomfortably close to (or past) the hard deadline, require explicit escalation/sign-off acknowledging the extended-support cost and reduced security-patch cadence they're accepting — making the trade-off visible and deliberately chosen, not a silent default.

**Validation steps:** confirm, well before the hard deadline, that every one of the 20 clusters has either completed its upgrade or has a firm, committed date within the remaining window — treating "no clear commitment yet" from any team as itself a signal requiring proactive platform-team follow-up, not passive waiting.

**Rollback or recovery strategy:** if a specific team's cohort upgrade reveals an issue specific to their workloads (distinct from the general canary validation in Question 74), that team's slot can be pushed to a later cohort for remediation, without necessarily delaying the rest of the fleet's timeline.

**Long-term prevention:** make this annual upgrade-calendar coordination a standing, repeatable platform-operations process (not reinvented each year), informed by the always-in-advance-published AWS version lifecycle calendar, so every future year's upgrade cycle starts with ample lead time built in by default.

### Step-by-Step Implementation
```text
T-minus 6 months: publish overall upgrade window, informed by AWS's published
  end-of-standard-support date for the current version.
T-minus 5 months: solicit each of the 20 teams' constraint input for cohort placement.
T-minus 4 months: publish final cohort assignments and specific dates.
T-minus 3 months to T-0: execute the staged, cohort-based rollout (per Question 74),
  with a firm final deadline before end-of-standard-support.
```

### Under-the-Hood Explanation
This process layers organizational/communication coordination on top of the same technical staged-rollout mechanics from Question 74 — the cohort *assignment* now additionally optimizes for each team's own scheduling constraints (not just risk-based canary ordering alone), while the *overall* timeline remains anchored to the immovable, externally-set constraint of the version's actual end-of-standard-support date, giving the process both flexibility (within the window) and a firm forcing function (the deadline itself) that prevents indefinite drift.

### Common Weak Answer
"Let each team upgrade whenever they're ready, on their own schedule."

### Why the Weak Answer Fails
Without a firm overall deadline anchored to the actual end-of-standard-support date, this approach risks exactly the reactive, surprise-cost scenario from Question 76 recurring at fleet scale, with some teams perpetually deferring — flexibility within a defined window is valuable, but an entirely open-ended, no-deadline approach abandons the forcing function needed to actually complete the fleet-wide upgrade before real cost/security consequences accrue.

### Follow-Up Questions
1. How would you handle a team that consistently pushes back against every proposed upgrade window, citing ongoing constraints?
2. What escalation path would you establish for a team approaching the hard deadline without a committed upgrade date?
3. How would you incorporate lessons from each year's upgrade cycle into improving the next year's process?

### Key Interview Signals
Balances team autonomy/scheduling flexibility against a firm, externally-anchored deadline, designing a coordination process that avoids both an inflexible top-down mandate and an indefinitely-delayable free-for-all.

### Hands-On Connection
[Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).
