# Category 6: Kubernetes and Container Integration

Questions 53–60 of 120. Category weight: 8 questions.

---

## Question 53: The playbook that wanted to run the whole platform

### Scenario
A team migrating workloads to a new EKS cluster proposes writing an Ansible role that continuously reconciles application Deployments on the cluster — running on a schedule, checking whether the desired replica count/image version matches what's running, and correcting drift if not.

### Interview Question
Is this a good use of Ansible? Where does Ansible's role actually end once Kubernetes is in the picture?

### Strong Senior-Level Answer
**Initial assessment:** no — a scheduled, drift-correcting playbook for in-cluster application state is reinventing, poorly, what a GitOps controller (ArgoCD/Flux) already does natively and continuously, not on a schedule but via an event-driven reconciliation loop with far better observability, self-healing, and audit trail than a cron-triggered playbook could match.

**Technical reasoning:** Ansible has no persistent controller process watching cluster state continuously — a scheduled playbook only checks and corrects drift at whatever interval it's triggered, leaving a window (up to the full interval) where drift goes uncorrected, and it provides none of GitOps's built-in sync-status visibility, automatic rollback-on-failed-health-check, or progressive-delivery integration.

**Investigation process:** clarify what specifically is motivating this proposal — if it's "we already know Ansible, we don't want to learn ArgoCD," that's a team-capability concern worth addressing via training, not a reason to build an inferior, custom reconciliation mechanism from scratch using the wrong tool for this specific job.

**Recommended solution:** Ansible's legitimate role ends at getting the cluster and its foundational add-ons into a working state (via `kubernetes.core.helm`/`k8s` modules, typically as part of initial cluster bootstrap — see Question 55) — ongoing application deployment and drift correction should be handed off to a GitOps controller, which is purpose-built for exactly this continuous-reconciliation problem.

**Risk controls:** if the team insists on an interim, Ansible-based approach while ramping up GitOps expertise, treat it explicitly as temporary scaffolding with a committed migration date to GitOps, not a permanent architecture — an indefinite "temporary" solution risks becoming permanent by default.

**Validation steps:** once GitOps is in place, confirm its sync status accurately reflects live cluster state and that no competing Ansible-based reconciliation job remains running against the same resources (avoiding the dual-ownership conflict pattern recurring throughout this category).

**Rollback or recovery strategy:** not applicable — this is an architectural steering decision, not an infrastructure change.

**Long-term prevention:** document the Ansible/Kubernetes-native boundary explicitly for any team transitioning workloads to Kubernetes — a scheduled playbook is a plausible-sounding but structurally inferior substitute for a purpose-built GitOps controller, and this exact proposal is worth flagging early before engineering effort goes into building it.

### Step-by-Step Implementation
Not applicable as a build task — the recommended path is adopting a GitOps controller instead of building the proposed playbook.

### Under-the-Hood Explanation
A GitOps controller runs as a persistent, event-driven process inside the cluster, watching both the Git repository and live cluster state continuously — any drift is detected and corrected within seconds to minutes, with full status reporting, whereas a scheduled Ansible playbook is fundamentally a periodic, one-shot execution with no persistent watching capability between runs, a structurally weaker guarantee for the "keep live state matching desired state continuously" problem.

### Common Weak Answer
"Ansible can do this fine, just schedule it more frequently."

### Why the Weak Answer Fails
Increasing frequency narrows but never closes the drift-detection gap inherent to a scheduled, non-continuous mechanism, and still provides none of GitOps's sync-status visibility or self-healing integration — this is optimizing the wrong tool rather than using the right one.

### Follow-Up Questions
1. What genuinely still belongs to Ansible once a GitOps controller is managing in-cluster application state?
2. How would you structure a migration plan moving a team off a scheduled-reconciliation playbook and onto GitOps?
3. How does this compare to the companion EKS repository's explicit framing of this same boundary question?

### Key Interview Signals
Recognizes that Kubernetes-native, event-driven reconciliation is structurally superior to a scheduled Ansible playbook for continuous drift correction, and draws the Ansible/Kubernetes boundary clearly rather than defaulting to a familiar tool for an unsuited job.

### Hands-On Connection
[Lab 9 — Kubernetes and Helm](../labs/lab-09-kubernetes-and-helm/).

---

## Question 54: The k8s module that wasn't quite idempotent the way they expected

### Scenario
A playbook uses `kubernetes.core.k8s` to apply a Deployment manifest. On every single run (even when nothing changed), the task reports `changed: true`, because the manifest's `resources.requests` field is expressed differently (different key ordering, different but equivalent YAML formatting) than what the cluster's API server normalizes and stores.

### Interview Question
Diagnose this false-positive "changed" report and explain the underlying comparison mechanism.

### Strong Senior-Level Answer
**Initial assessment:** `kubernetes.core.k8s`'s idempotency depends on correctly diffing the *submitted* manifest against the *live* object's current state — a false "changed" report on every run despite no logical difference usually means the comparison is being thrown off by a formatting/representation difference the module's diff logic doesn't correctly normalize away, not a genuine configuration drift.

**Technical reasoning:** Kubernetes objects, once stored, often have server-side defaults/normalizations applied (field ordering, default values injected, unit representations changed) — if the module's local diff compares the raw submitted YAML against the live object without accounting for these normalizations, semantically-identical configurations can appear different, causing a false-positive "changed" result on every single run.

**Investigation process:** compare the exact submitted manifest against the live object's actual stored representation (`kubectl get deployment -o yaml`) to identify the specific field(s) whose formatting differs — this pinpoints exactly what's causing the spurious diff.

**Recommended solution:** use `kubernetes.core.k8s`'s server-side apply mode (`apply: true`, leveraging the Kubernetes API server's own server-side apply/diff logic rather than the module's local comparison) — letting the API server itself determine what's actually changed, which correctly handles server-side normalization and defaults.

**Risk controls:** validate that switching to server-side apply doesn't change field-ownership semantics in a way that conflicts with another controller (e.g., a GitOps controller or HPA) also managing fields on the same object — server-side apply tracks field ownership explicitly, which is generally an improvement but worth confirming doesn't introduce a new conflict.

**Validation steps:** after switching, run the playbook twice in immediate succession and confirm the second run reports `changed: false`, genuinely reflecting no drift.

**Rollback or recovery strategy:** revert to client-side apply if server-side apply introduces an unexpected field-ownership conflict, while investigating the specific conflict further.

**Long-term prevention:** default to server-side apply for any `kubernetes.core.k8s` task managing a resource type prone to server-side normalization, treating the false-positive-changed pattern as a signal to check the apply mode being used.

### Step-by-Step Implementation
```yaml
- name: Apply Deployment with server-side apply for correct idempotency
  kubernetes.core.k8s:
    state: present
    src: deployment.yaml
    apply: true   # server-side apply - API server determines actual diff
```

### Under-the-Hood Explanation
Server-side apply moves the diff/merge logic into the API server itself, which has full knowledge of the object's actual current, normalized state and can correctly determine whether a given field genuinely needs updating — client-side diffing (the module's default without `apply: true`) compares raw YAML representations, which can differ syntactically while being semantically identical, producing exactly this false-positive pattern.

### Common Weak Answer
"Just ignore the changed:true reports, they're harmless."

### Why the Weak Answer Fails
A false "changed" report on every run undermines the entire value of idempotency reporting (which tasks in a larger play actually made a change, useful for handler-triggering and auditability) and can mask a genuine, real change happening alongside the spurious one — the correct fix addresses the root comparison mechanism, not dismissing its output.

### Follow-Up Questions
1. What's the difference in field-ownership semantics between client-side and server-side apply?
2. How would this same false-positive pattern manifest for other resource types with server-side defaulting?
3. How does this compare to Terraform's own state-vs-live-config diffing challenges?

### Key Interview Signals
Correctly diagnoses a client-side-diff normalization gap as the cause of false-positive idempotency reports, and fixes it via server-side apply rather than dismissing the module's output.

### Hands-On Connection
[Lab 9 — Kubernetes and Helm](../labs/lab-09-kubernetes-and-helm/).

---

## Question 55: The bootstrap that outlived its purpose

### Scenario
A playbook using `kubernetes.core.helm` installs the AWS Load Balancer Controller, Karpenter, and ArgoCD as part of a new EKS cluster's initial bootstrap. Six months later, a team member runs the same playbook again "just to make sure everything's up to date," and it silently reverts several Helm values that the platform team had since customized directly via ArgoCD-managed Helm values (after GitOps took over ongoing management).

### Interview Question
Diagnose this dual-ownership conflict and design the correct handoff process.

### Strong Senior-Level Answer
**Initial assessment:** this is the same "two tools believe they own the same resource" conflict recurring throughout this repository — Ansible correctly bootstrapped these Helm releases initially, but once ArgoCD took over ongoing management of them, the original Ansible playbook became a stale, competing source of configuration that, when re-run, reverts ArgoCD's subsequent legitimate changes back to the bootstrap-time values.

**Technical reasoning:** `kubernetes.core.helm` has no awareness that a different tool (ArgoCD) has since taken over management of the same Helm release — re-running the original bootstrap playbook simply reapplies its own values, exactly as it's designed to do, with no knowledge of or respect for changes made through the other tool's management path since.

**Investigation process:** confirm exactly which Helm values reverted and cross-reference against ArgoCD's own Application history to see what legitimate changes were lost — this confirms the dual-ownership diagnosis and scopes the actual impact.

**Recommended solution:** treat the original Ansible bootstrap playbook as a one-time, initial-bootstrap-only tool — once ArgoCD (or any GitOps controller) takes over a given Helm release's ongoing management, retire or explicitly gate that release from the Ansible playbook's scope (e.g., removing it from the playbook's task list, or adding an explicit, documented "do not re-run against already-migrated releases" guard).

**Risk controls:** restore the reverted Helm values from ArgoCD's own tracked history/Git-declared values, and audit whether the bootstrap playbook has any other Helm releases still both Ansible- and ArgoCS-managed simultaneously.

**Validation steps:** confirm ArgoCD's sync status for the affected releases returns to reflecting the correct, intended values, and confirm the bootstrap playbook is no longer capable of being accidentally re-run against already-migrated releases.

**Rollback or recovery strategy:** not applicable beyond restoring the reverted values — the actual fix is preventing recurrence via scope-gating the playbook.

**Long-term prevention:** document explicitly, for every cluster, exactly which components are "Ansible-bootstrapped-then-handed-off" versus "still Ansible-managed ongoing," and never re-run a bootstrap-only playbook against a cluster without first confirming its target releases haven't since been migrated to GitOps management — exactly the same discipline as the EKS repository's CoreDNS dual-installation conflict, here applied to the Ansible-to-GitOps handoff moment specifically.

### Step-by-Step Implementation
```yaml
# Bootstrap playbook - explicitly scoped to first-run only, with a guard
- name: Bootstrap AWS Load Balancer Controller (ONE-TIME - do not re-run post-GitOps handoff)
  kubernetes.core.helm:
    name: aws-load-balancer-controller
    chart_ref: eks/aws-load-balancer-controller
    release_state: present
  when: bootstrap_confirm | default(false) | bool   # explicit opt-in guard against accidental re-run
```

### Under-the-Hood Explanation
Both Ansible's `kubernetes.core.helm` module and ArgoCD's Helm-source `Application` ultimately invoke the same underlying Helm release mechanism — neither has any built-in awareness of the other's involvement, meaning whichever one runs most recently simply overwrites the release's values according to its own configuration, with no coordination or conflict-detection between the two tools.

### Common Weak Answer
"Just re-run the Ansible playbook regularly to keep things consistent."

### Why the Weak Answer Fails
This is precisely the action that caused the incident — regularly re-running a bootstrap-only playbook against a release ArgoCD has since taken over guarantees exactly this kind of value-reversion conflict recurring on every re-run.

### Follow-Up Questions
1. How would you design an automated check flagging any Helm release both Ansible and ArgoCD are configured to manage simultaneously?
2. What's the correct process for handing off an Ansible-bootstrapped component to GitOps management cleanly?
3. How does this compare to the companion EKS repository's Helm-values-reversion scenario (Terraform repo Question 69 equivalent)?

### Key Interview Signals
Diagnoses the dual-ownership conflict precisely and designs a scope-gating fix (retiring the bootstrap playbook's authority once GitOps takes over) rather than treating periodic re-runs as a harmless consistency check.

### Hands-On Connection
[Lab 9 — Kubernetes and Helm](../labs/lab-09-kubernetes-and-helm/).

---

## Question 56: One kubeconfig, five clusters, one very confused playbook

### Scenario
A platform team's Ansible control node holds kubeconfig contexts for five different EKS clusters (dev, staging, and three regional production clusters). A playbook intended for the staging cluster is accidentally run with the production context still active from a previous session, applying a test change to production.

### Interview Question
Diagnose this context-confusion risk and design a safer multi-cluster Ansible pattern.

### Strong Senior-Level Answer
**Initial assessment:** relying on an ambient, previously-set kubeconfig context (rather than explicitly specifying the target cluster in every single task/play) is exactly the kind of implicit, easy-to-miss state dependency that causes cross-environment accidents — the playbook itself had no way to verify or enforce which cluster it was actually targeting.

**Technical reasoning:** `kubernetes.core.k8s` (and related modules) default to whatever kubeconfig context is currently active in the executing shell/environment unless explicitly overridden per-task — a control node juggling multiple clusters' contexts across different sessions is inherently error-prone if playbooks don't explicitly, unambiguously declare their target cluster every time.

**Investigation process:** confirm exactly which context was active when the accidental run occurred, and audit how many other playbooks in the library share this same implicit-context-dependency pattern — this is very likely not an isolated risk.

**Recommended solution:** require every Kubernetes-targeting playbook/task to explicitly specify its target cluster via the module's own `kubeconfig`/`context` parameters (never relying on ambient shell state), ideally sourced from an explicit, per-environment variable (`{{ target_cluster_context }}`) that must be deliberately set (e.g., via `-e` at invocation, never a silently-assumed default) — making the target cluster an explicit, visible, required input rather than implicit environmental state.

**Risk controls:** add an explicit confirmation/assertion step at the start of any production-targeting playbook, verifying the actual context matches the intended target before proceeding with any mutating task — a positive-control check against exactly this class of mistake.

**Validation steps:** test the explicit-context pattern by deliberately attempting to run a staging-intended playbook without setting the required context variable, confirming it fails fast with a clear error rather than silently defaulting to whatever context happens to be ambient.

**Rollback or recovery strategy:** for the specific incident, assess and revert the accidentally-applied test change in production via the standard rollback path for that resource type.

**Long-term prevention:** never rely on ambient kubeconfig context for any Ansible-driven Kubernetes automation — always require explicit, validated target-cluster specification as a mandatory input, exactly mirroring the companion repository's guidance against relying on an ambient AWS profile/region for cloud-targeting automation.

### Step-by-Step Implementation
```yaml
- name: Verify explicit target cluster before any mutating task
  ansible.builtin.assert:
    that:
      - target_cluster_context is defined
      - target_cluster_context == "staging-cluster"
    fail_msg: "target_cluster_context must be explicitly set and match the intended cluster"

- name: Apply manifest to the EXPLICITLY specified cluster only
  kubernetes.core.k8s:
    state: present
    src: manifest.yaml
    context: "{{ target_cluster_context }}"   # never ambient/default
```

### Under-the-Hood Explanation
Kubernetes client libraries (which `kubernetes.core` modules wrap) resolve their target cluster from the kubeconfig's "current context" unless explicitly told otherwise — this is convenient for interactive, single-cluster use but genuinely dangerous for automation spanning multiple clusters from one control node, since the "current context" is exactly the kind of silent, session-dependent state that can be stale or unexpected at automation-run time.

### Common Weak Answer
"Just be more careful to switch contexts before running any playbook."

### Why the Weak Answer Fails
This relies on manual discipline as the safeguard against exactly the kind of mistake that already happened — the durable fix makes the target cluster an explicit, required, and verified input to the playbook itself, removing the dependency on remembering to check ambient state correctly every time.

### Follow-Up Questions
1. How would you extend this explicit-target-verification pattern to other multi-account/multi-region automation beyond Kubernetes specifically?
2. What's the risk of a similar ambient-state dependency for AWS CLI profile/region in the same multi-cluster control node?
3. How would you audit the existing playbook library for other instances of implicit context dependency?

### Key Interview Signals
Identifies ambient kubeconfig context as an implicit, dangerous state dependency for multi-cluster automation, and designs an explicit, validated target-cluster-specification pattern as the fix.

### Hands-On Connection
[Lab 9 — Kubernetes and Helm](../labs/lab-09-kubernetes-and-helm/).

---

## Question 57: The one-off task that didn't need a whole playbook run

### Scenario
An operational task ("run a one-time data-migration script inside the cluster") is currently handled by SSHing into a bastion, then using `kubectl exec` manually into a running pod to execute a script. A team member proposes writing an Ansible playbook to automate this SSH-then-exec sequence instead.

### Interview Question
Is an Ansible playbook the right tool here? What's the more Kubernetes-native alternative?

### Strong Senior-Level Answer
**Initial assessment:** automating an SSH-then-`kubectl exec` sequence via Ansible is a plausible-seeming but not the most idiomatic fix — the more Kubernetes-native approach is a **Kubernetes `Job`** (a one-off, run-to-completion workload the cluster itself schedules and tracks), which removes the SSH/bastion dependency entirely and gives proper, cluster-native tracking of the task's execution and completion status.

**Technical reasoning:** a `Job` runs as a normal, scheduled pod with the migration script as its container command, tracked by the Kubernetes API (`kubectl get jobs` shows completion status, retry count, logs accessible via standard `kubectl logs`) — this is a fundamentally more observable, more idiomatic mechanism for a one-off in-cluster task than an external SSH/exec sequence orchestrated by Ansible.

**Investigation process:** confirm whether this task is genuinely a one-off (favoring a `Job`) or something recurring on a schedule (which would favor a `CronJob`, an even better-suited native mechanism) — either way, moving away from the SSH/bastion-dependent, `kubectl exec`-based approach is the right direction.

**Recommended solution:** replace the proposed Ansible-automated SSH/exec sequence with a `Job` manifest (applied via `kubernetes.core.k8s`, if Ansible is still used as the *trigger* mechanism — a reasonable, legitimate use, since triggering a Job's creation is a simple, appropriate task, distinct from Ansible trying to orchestrate the actual in-cluster execution via SSH/exec).

**Risk controls:** ensure the `Job`'s pod spec has appropriate resource limits and a `backoffLimit`/`activeDeadlineSeconds` configured, so a failing or hanging migration script doesn't retry indefinitely or run unbounded.

**Validation steps:** confirm the `Job` completes successfully (`kubectl get job -o jsonpath='{.status.succeeded}'`) and its logs show the expected migration output, without any dependency on bastion/SSH access at all.

**Rollback or recovery strategy:** if the migration script itself needs re-running, simply recreate the `Job` (or use a `CronJob` if genuinely recurring) — no SSH/bastion cleanup needed.

**Long-term prevention:** treat "does this operational task have a Kubernetes-native mechanism (Job, CronJob) that removes the need for SSH/bastion-based orchestration entirely" as a standard question whenever a new in-cluster operational task is proposed, rather than defaulting to the SSH-based pattern out of habit from pre-Kubernetes infrastructure.

### Step-by-Step Implementation
```yaml
# Ansible task - legitimately just TRIGGERS the Job, doesn't orchestrate SSH/exec
- name: Trigger one-off data migration Job
  kubernetes.core.k8s:
    state: present
    definition:
      apiVersion: batch/v1
      kind: Job
      metadata: { name: data-migration-{{ ansible_date_time.epoch }} }
      spec:
        backoffLimit: 2
        activeDeadlineSeconds: 600
        template:
          spec:
            restartPolicy: Never
            containers:
              - name: migrate
                image: my-registry/migration-script:v1
```

### Under-the-Hood Explanation
A Kubernetes `Job` is scheduled and tracked by the cluster's own control plane exactly like any other workload — its completion status, retries, and logs are all first-class, API-observable properties, in contrast to an SSH-then-`kubectl exec` sequence, whose success/failure and output are only as observable as whatever the orchestrating script (Ansible, in this case) happens to capture and report, with no persistent, cluster-native record of the execution afterward.

### Common Weak Answer
"Automating the SSH/exec sequence in Ansible is fine, it removes the manual toil."

### Why the Weak Answer Fails
This automates the *wrong* mechanism — it removes manual toil but retains the SSH/bastion dependency and the lack of cluster-native observability a `Job` would provide; the better fix replaces the underlying approach entirely, not just scripts around it.

### Follow-Up Questions
1. When would a `CronJob` be more appropriate than a one-off `Job` for this kind of task?
2. What's the resource/security consideration for a Job that needs elevated permissions beyond its own namespace?
3. How would you handle a migration script needing access to a Secret or ConfigMap, following the security guidance from earlier categories?

### Key Interview Signals
Recognizes the Kubernetes-native `Job`/`CronJob` mechanism as structurally superior to an SSH-orchestrated `kubectl exec` sequence, and correctly scopes Ansible's legitimate role to triggering the Job, not orchestrating the actual execution.

### Hands-On Connection
[Lab 9 — Kubernetes and Helm](../labs/lab-09-kubernetes-and-helm/).

---

## Question 58: The hybrid fleet that needed two playbooks pretending to be one

### Scenario
Mid-migration from VMs to EKS, a team has half their fleet still running on Ansible-managed EC2 instances and half migrated to Kubernetes. A shared configuration value (a feature flag, needed by both the VM-based and container-based versions of the same application) currently has to be updated in two completely separate places — an Ansible `group_vars` file and a Kubernetes `ConfigMap` — with no single source of truth, and the two have already drifted out of sync once.

### Interview Question
Design a single-source-of-truth approach for configuration shared across a hybrid VM/Kubernetes fleet during migration.

### Strong Senior-Level Answer
**Initial assessment:** maintaining the same logical configuration value in two independently-updated places is exactly the "two copies that need to stay in sync but have no enforced mechanism to" gap recurring throughout this repository series — the fix is establishing one genuine source of truth that both the VM-side and Kubernetes-side configuration mechanisms read from, rather than two parallel, independently-maintained copies.

**Technical reasoning:** AWS Systems Manager Parameter Store (or Secrets Manager, for anything sensitive) can serve as this single source of truth — Ansible can read from it via the `amazon.aws` lookup plugin for VM-targeted configuration, and Kubernetes can read from it via the External Secrets Operator or a custom init-container pattern for container-targeted configuration, with both sides sourcing the identical underlying value rather than maintaining independent copies.

**Investigation process:** confirm exactly which configuration values are genuinely shared across both fleet halves (versus values that are legitimately environment/platform-specific and shouldn't be unified) — only genuinely shared values warrant this single-source-of-truth treatment.

**Recommended solution:** migrate the shared feature-flag value to Parameter Store as the sole source of truth; update the Ansible playbook to read it via `amazon.aws.aws_ssm` lookup at deploy/config time (rather than a static `group_vars` value), and configure the Kubernetes side to source the same parameter via External Secrets Operator (or an equivalent Parameter-Store-to-ConfigMap sync mechanism) — both sides now genuinely reading the same, single value.

**Risk controls:** during the transition, verify both sides are correctly reading the new shared source before removing the old, separately-maintained copies — a brief overlap period confirming consistency is safer than an abrupt cutover.

**Validation steps:** update the value once, in Parameter Store only, and confirm both the VM-based and Kubernetes-based applications correctly pick up the new value without any separate, manual update to either side.

**Rollback or recovery strategy:** if the shared-source approach reveals an unexpected latency/reliability dependency (e.g., Parameter Store API throttling under load), revert temporarily to the previous dual-copy approach for the specific affected value while a caching layer or alternative distribution mechanism is designed.

**Long-term prevention:** treat any genuinely-shared configuration value during a hybrid VM/Kubernetes migration period as requiring a single, externally-hosted source of truth from the outset, rather than allowing two independently-evolving copies to exist even temporarily — this exact drift-detection-after-the-fact pattern is avoidable by establishing the shared source before, not after, the first divergence occurs.

### Step-by-Step Implementation
```yaml
# Ansible - reads the SHARED source of truth, not a static group_vars value
- name: Fetch shared feature flag from Parameter Store
  ansible.builtin.set_fact:
    feature_flag_value: "{{ lookup('amazon.aws.aws_ssm', '/shared/feature-flags/new-checkout', region='us-east-1') }}"
```
```yaml
# Kubernetes side - External Secrets Operator syncing the SAME Parameter Store value
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata: { name: shared-feature-flag }
spec:
  secretStoreRef: { name: aws-parameter-store, kind: ClusterSecretStore }
  target: { name: feature-flags-configmap }
  data:
    - secretKey: new-checkout
      remoteRef: { key: /shared/feature-flags/new-checkout }
```

### Under-the-Hood Explanation
Both Ansible's lookup plugin and the Kubernetes-side External Secrets Operator ultimately query the same underlying Parameter Store API for the same parameter path — establishing this as the single point of truth means any update, made exactly once, is correctly reflected on both sides of the hybrid fleet the next time each respectively reads it, eliminating the manual-dual-update process (and its inherent drift risk) entirely.

### Common Weak Answer
"Just add a reminder checklist step to update both places whenever this value changes."

### Why the Weak Answer Fails
This is the exact manual-process reliance that already caused a drift incident once — a checklist reminder doesn't structurally prevent recurrence the way an actual single source of truth does.

### Follow-Up Questions
1. How would you decide which shared values genuinely warrant this centralized approach versus remaining legitimately separate per platform?
2. What's the caching/reliability consideration if many VM-side playbook runs query Parameter Store frequently?
3. How would this pattern simplify once the migration to Kubernetes is fully complete and the VM side is decommissioned?

### Key Interview Signals
Identifies the dual-copy configuration drift as a single-source-of-truth gap and designs a genuinely shared, externally-hosted configuration source both platforms read from, rather than a process-reminder workaround.

### Hands-On Connection
[Lab 9 — Kubernetes and Helm](../labs/lab-09-kubernetes-and-helm/) and [Lab 7 — AWS Configuration Management](../labs/lab-07-aws-configuration-management/).

---

## Question 59: The AMI that Ansible baked, but Kubernetes wouldn't boot correctly

### Scenario
A Packer + Ansible pipeline (per Lab 8) bakes a custom EKS node AMI including several compliance agents. A newly-launched node from this AMI fails to join the cluster — its kubelet fails to start, with a version-mismatch error against the cluster's control plane.

### Interview Question
Diagnose this AMI-to-cluster compatibility gap and connect it to the golden-AMI discipline from earlier in this repository.

### Strong Senior-Level Answer
**Initial assessment:** per the [Lab 8](../labs/lab-08-packer-ami-baking/) golden-AMI pattern, the AMI's baked-in kubelet version must stay synchronized with whatever Kubernetes version the cluster's control plane is currently running — if the cluster was upgraded (per the companion EKS repository's upgrade-sequencing guidance) since this AMI was last baked, the AMI's kubelet is now stale relative to the control plane, exactly the kind of version-matrix gap the EKS repository's [Question 70](../../../eks/eks-senior-interview-preparation/interview-questions/08-addons-upgrades.md) covers for self-managed add-ons, here applied to the node AMI itself.

**Technical reasoning:** EKS enforces kubelet-to-control-plane version skew limits (kubelet generally must not be more than a few minor versions behind the control plane) — an AMI baked before a control-plane upgrade, if not correspondingly rebuilt, can fall outside this supported skew window, causing exactly the node-join failure described.

**Investigation process:** confirm the AMI's baked-in kubelet version (via the Packer build's own recorded metadata/tags) against the cluster's current control-plane version, and confirm whether a control-plane upgrade occurred since this AMI was last rebuilt — this settles the version-skew diagnosis definitively.

**Recommended solution:** rebuild the AMI with a kubelet version matching the cluster's current control-plane version (via the Packer + Ansible pipeline's normal rebuild process), and establish a trigger tying AMI rebuilds to control-plane version changes specifically — treating this as a required, not optional, step in the cluster-upgrade sequence.

**Risk controls:** incorporate a kubelet-version-compatibility check into the AMI-bake pipeline itself (a validation step confirming the baked kubelet version falls within the supported skew of the target cluster's control-plane version) before the AMI is considered ready for use.

**Validation steps:** after rebuilding, launch a test node from the new AMI and confirm it joins the cluster successfully with no version-mismatch error.

**Rollback or recovery strategy:** until the AMI is rebuilt, avoid launching any new nodes from the stale AMI — pin node groups/Karpenter `EC2NodeClass` to the previous, still-compatible AMI version if an emergency scale-out is needed before the rebuild completes.

**Long-term prevention:** integrate AMI-rebuild triggering directly into the EKS repository's own cluster-upgrade sequencing checklist (per its [`docs/addons-and-upgrades.md`](../../../eks/eks-senior-interview-preparation/docs/addons-and-upgrades.md) §2) — a control-plane upgrade should always trigger a corresponding AMI rebuild check, closing this exact cross-repository coordination gap between the Ansible-driven AMI pipeline and the EKS cluster's own version lifecycle.

### Step-by-Step Implementation
```yaml
# Packer + Ansible pipeline - kubelet version pinned to match the target cluster's control plane
- name: Install kubelet matching cluster control-plane version
  ansible.builtin.package:
    name: "kubelet-{{ target_control_plane_version }}"
    state: present
```

### Under-the-Hood Explanation
EKS's node-join process validates the joining kubelet's version against the control plane's own version, enforcing Kubernetes' documented version-skew policy — a kubelet baked into an AMI before a control-plane upgrade, if not correspondingly rebuilt, will eventually fall outside this supported skew window as the control plane continues to advance, producing exactly this join failure the moment the skew limit is exceeded.

### Common Weak Answer
"Just manually update the kubelet version on the running node after it fails to join."

### Why the Weak Answer Fails
This treats the symptom on one node without fixing the actual source (the AMI itself is stale) — every subsequent node launched from the same unrebuilt AMI would hit the identical failure, making a per-node manual fix an unsustainable, recurring effort instead of the correct, one-time AMI rebuild.

### Follow-Up Questions
1. How would you automate the trigger connecting a cluster control-plane upgrade to a required AMI rebuild?
2. What's the version-skew policy's specific limit, and how would you validate an AMI's compatibility against it programmatically?
3. How does this cross-repository coordination gap (Ansible AMI pipeline + EKS cluster lifecycle) get addressed at an organizational-process level, not just a technical one?

### Key Interview Signals
Connects the AMI-to-cluster kubelet version-skew failure to the golden-AMI discipline and explicitly ties AMI-rebuild triggering to the EKS repository's own cluster-upgrade sequencing, recognizing this as a genuine cross-repository coordination point.

### Hands-On Connection
[Lab 8 — Packer and Ansible AMI Baking](../labs/lab-08-packer-ami-baking/) and the companion [EKS repository's upgrade sequencing guidance](../../../eks/eks-senior-interview-preparation/docs/addons-and-upgrades.md).

---

## Question 60: Choosing between an Ansible role and a Helm chart for the same job

### Scenario
A new internal tool needs to be deployed both to a fleet of legacy VMs (via Ansible) and to a Kubernetes cluster (via Helm), for two different teams still on different platforms. A junior engineer asks whether they should just write one Ansible role that handles both cases, using conditionals to branch between VM-targeting and Kubernetes-targeting tasks.

### Interview Question
Evaluate this "one role, two platforms" proposal.

### Strong Senior-Level Answer
**Initial assessment:** a single role branching between fundamentally different target platforms (VM configuration management vs. Kubernetes manifest deployment) via conditionals tends to produce exactly the "overly generic, conditional-heavy role" anti-pattern from earlier in this repository's role-design guidance — VM configuration and Kubernetes deployment are different enough problems, with different idiomatic tools (Ansible modules vs. Helm templates) that forcing them into one role's conditional branches sacrifices clarity for superficial code-reuse.

**Technical reasoning:** an Ansible role's VM-targeting tasks (package installation, service management, config-file templating) and Kubernetes-targeting tasks (applying a Deployment/Service manifest via `kubernetes.core.k8s` or invoking Helm) have almost nothing in common at the implementation level beyond "deploy this application somewhere" — the conditional branching needed to house both inside one role adds complexity without meaningfully reducing duplication, since the actual task content for each branch is entirely different anyway.

**Investigation process:** identify what, if anything, is genuinely shared between the two deployment targets (perhaps just the application's version number or a shared configuration value, per Question 58) — this is usually a small, genuinely shareable subset, not the deployment mechanism itself.

**Recommended solution:** maintain two separate, platform-idiomatic deployment paths — an Ansible role for the VM fleet (using standard Ansible patterns) and a Helm chart for the Kubernetes deployment (using standard Helm/Kubernetes patterns) — with only the genuinely shared configuration (per Question 58's single-source-of-truth pattern) unified between them, not the deployment mechanism itself.

**Risk controls:** ensure both deployment paths reference the same application version/artifact source (the same container image or the same release artifact) so the two platforms, while deployed differently, are never running divergent application versions due to the separate deployment paths drifting independently.

**Validation steps:** confirm both deployment paths correctly deploy the intended application version, and confirm the shared configuration values (if any) are sourced identically per Question 58's pattern.

**Rollback or recovery strategy:** each platform's rollback follows its own idiomatic mechanism — `ansible-playbook` re-run with a previous version for VMs, `helm rollback`/GitOps revert for Kubernetes — no shared rollback mechanism needed given the genuinely separate deployment paths.

**Long-term prevention:** apply the same "opinionated, single-purpose role over an overly generic, conditional-heavy one" principle from Category 3's role-design guidance to this cross-platform scenario specifically — recognizing that superficial code-reuse across fundamentally different deployment targets usually costs more in complexity than it saves in duplication.

### Step-by-Step Implementation
```text
Two separate, platform-idiomatic paths:
- roles/my-tool-vm/          (Ansible role, standard VM deployment tasks)
- charts/my-tool/             (Helm chart, standard Kubernetes deployment)
Shared: application version/artifact reference, and any genuinely shared
config values sourced from a single external source (Question 58's pattern)
```

### Under-the-Hood Explanation
Ansible's task-execution model (imperative, step-by-step configuration of a target host) and Helm's templating-then-apply model (declarative manifest generation for the Kubernetes API) are fundamentally different deployment paradigms — forcing both into one role's conditional logic doesn't create genuine abstraction, since the actual work performed in each branch remains entirely platform-specific, meaning the "shared role" mostly just houses two unrelated implementations side by side with added conditional complexity.

### Common Weak Answer
"One role for both platforms is more maintainable since there's only one place to update."

### Why the Weak Answer Fails
There's only "one place to update" in name — the actual task content for each platform-specific branch remains entirely separate and must be maintained independently regardless, meaning this claimed maintainability benefit doesn't materialize, while the conditional complexity genuinely does.

### Follow-Up Questions
1. What would need to be true for a genuinely shared deployment abstraction across VM and Kubernetes targets to make sense?
2. How would you ensure the two separate deployment paths never end up running different application versions unintentionally?
3. How does this decision connect to the broader migration strategy discussed in the companion EKS repository's Question 118?

### Key Interview Signals
Recognizes that superficial code-reuse across fundamentally different deployment platforms (VM configuration vs. Kubernetes manifests) isn't genuine abstraction, and maintains two separate, idiomatic deployment paths while still ensuring genuinely shared elements (version, config) stay consistent.

### Hands-On Connection
[Lab 9 — Kubernetes and Helm](../labs/lab-09-kubernetes-and-helm/) and [Lab 2 — Roles and Structure](../labs/lab-02-roles-and-structure/).
