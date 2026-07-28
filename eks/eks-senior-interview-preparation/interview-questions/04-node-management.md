# Category 4: Node Management (Managed Node Groups, Karpenter, Fargate)

Questions 35–42 of 120. Category weight: 8 questions. Deep-dive reference: [`docs/node-management-and-autoscaling.md`](../docs/node-management-and-autoscaling.md).

---

## Question 35: The Spot interruption nobody handled gracefully

### Scenario
A cost-optimization initiative moves a fleet onto Spot instances via Karpenter. Weeks later, a Spot interruption causes several user-facing requests to fail with connection-reset errors during the two-minute interruption window, despite Karpenter successfully launching replacement capacity.

### Interview Question
Diagnose why replacement capacity succeeding didn't prevent user-facing failures, and fix it.

### Strong Senior-Level Answer
**Initial assessment:** Karpenter successfully provisioning replacement capacity solves the *capacity* problem but says nothing about whether *in-flight requests on the interrupted node* were drained gracefully before termination — per [`docs/node-management-and-autoscaling.md`](../docs/node-management-and-autoscaling.md) §4, handling Spot interruption correctly requires both replacement capacity *and* graceful connection draining on the interrupted node during its two-minute notice window.

**Technical reasoning:** without the AWS Node Termination Handler (or Karpenter's built-in interruption handling correctly configured) actively cordoning and draining the node on interruption notice, pods on that node are abruptly terminated when AWS reclaims the instance — any in-flight request being served by those pods fails mid-connection, regardless of how quickly replacement capacity elsewhere comes online, since replacement capacity doesn't help requests already in-flight against the node that's disappearing.

**Investigation process:** confirm whether Karpenter's interruption handling (or a separately-installed Node Termination Handler) is actually configured and correctly wired to the Spot interruption notice, and confirm pod-level `PodDisruptionBudget`s exist for the affected workload — both are needed for graceful, request-preserving drainage.

**Recommended solution:** enable Karpenter's native interruption handling (watching the EC2 Spot interruption notice via EventBridge) so cordoning/draining begins immediately on notice, configure appropriate `terminationGracePeriodSeconds` on the workload's pod spec to allow in-flight requests to complete, and ensure a `PodDisruptionBudget` prevents too many replicas draining simultaneously across concurrent interruptions.

**Risk controls:** validate the workload's own graceful-shutdown behavior (does it stop accepting new connections but finish in-flight ones on SIGTERM) — infrastructure-level draining only helps if the application itself shuts down gracefully when signaled.

**Validation steps:** simulate a Spot interruption (via a controlled test) and confirm in-flight requests complete successfully while new requests are routed to healthy replacas during the drain window.

**Rollback or recovery strategy:** if Spot-related failures persist despite these fixes, consider a mixed on-demand/Spot capacity strategy for this specific latency-sensitive workload, accepting a smaller cost-saving in exchange for reduced interruption exposure.

**Long-term prevention:** treat interruption-handling configuration (Node Termination Handler/Karpenter native handling, `terminationGracePeriodSeconds`, `PodDisruptionBudget`) as a mandatory checklist item for any workload moved onto Spot capacity, not an afterthought discovered after the first real interruption causes user-facing impact.

### Step-by-Step Implementation
```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: spot-pool
spec:
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
  template:
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot"]
```
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: my-app-pdb
spec:
  minAvailable: 2
  selector:
    matchLabels: { app: my-app }
```

### Under-the-Hood Explanation
AWS issues a Spot interruption notice roughly two minutes before reclaiming an instance, delivered via the instance metadata service and mirrored to EventBridge — Karpenter's native interruption handling watches this event and proactively cordons/drains the node, giving pods their configured grace period to finish in-flight work and shut down cleanly, rather than the instance simply disappearing mid-request without any warning propagated to the workload.

### Common Weak Answer
"Just avoid Spot instances for anything user-facing."

### Why the Weak Answer Fails
This discards Spot's cost benefit entirely rather than correctly engineering around its known, well-documented interruption behavior — properly configured interruption handling and graceful shutdown make Spot viable for many user-facing workloads, and avoiding it outright is an overly blunt response to a solvable problem.

### Follow-Up Questions
1. How would you decide which workloads are and aren't good Spot candidates based on their tolerance for graceful, brief disruption?
2. What's the interaction between Karpenter's consolidation (Question in category 6) and Spot interruption handling?
3. How would you monitor Spot interruption frequency and correlate it with any user-facing impact over time?

### Key Interview Signals
Distinguishes "replacement capacity available" from "in-flight requests preserved," and designs the full graceful-drain chain (interruption handling, grace period, PDB) rather than treating Spot risk as binary.

### Hands-On Connection
[Lab 5 — Karpenter Autoscaling](../labs/lab-05-karpenter-autoscaling/).

---

## Question 36: The Karpenter NodePool that never matched

### Scenario
A workload with a GPU resource request (`nvidia.com/gpu: 1`) sits `Pending` indefinitely. Karpenter is installed and healthy, and its logs show no errors — it simply never attempts to provision a matching node.

### Interview Question
Diagnose why Karpenter isn't reacting to this pending pod at all.

### Strong Senior-Level Answer
**Initial assessment:** Karpenter only provisions nodes that satisfy a pending pod's requirements *and* fall within the constraints of at least one existing `NodePool`/`EC2NodeClass` — if no `NodePool` in the cluster is configured to allow GPU-capable instance types, Karpenter has no valid provisioning option and, by design, does nothing rather than provisioning something that wouldn't satisfy the pod anyway.

**Technical reasoning:** `NodePool` requirements (instance family, architecture, purchase option) act as a hard boundary on what Karpenter is even allowed to provision — a pod requesting a GPU resource that no configured `NodePool` permits (e.g., every existing `NodePool` restricts to general-purpose `m5`/`m6i` families) is structurally unschedulable by Karpenter, not a bug or a timing issue.

**Investigation process:** confirm via `kubectl describe pod` the pending pod's exact resource requirements, and cross-reference against every `NodePool`'s `spec.template.spec.requirements` to check whether any permits an instance family with GPU support (e.g., the `p`/`g` families) — this settles definitively whether a `NodePool` gap, not a Karpenter malfunction, is the cause.

**Recommended solution:** add a new `NodePool` (and corresponding `EC2NodeClass`) explicitly permitting GPU-capable instance families, typically tainted so only GPU-requesting workloads schedule onto the resulting nodes (avoiding non-GPU workloads wastefully consuming expensive GPU-instance capacity).

**Risk controls:** GPU instances are typically significantly more expensive than general-purpose instances — scope the new `NodePool`'s instance-family requirements and any relevant limits/consolidation settings carefully to avoid unexpectedly expensive over-provisioning.

**Validation steps:** after adding the `NodePool`, confirm the previously-pending pod is now scheduled onto a newly-provisioned GPU node, and confirm non-GPU workloads are correctly prevented from landing on the new, tainted GPU nodes (via the taint/toleration pairing).

**Rollback or recovery strategy:** remove or adjust the `NodePool` if it inadvertently permits an unexpectedly broad or costly set of instance types — a contained, low-risk configuration change.

**Long-term prevention:** maintain an explicit mapping of workload resource-requirement categories (GPU, high-memory, ARM-specific) to the `NodePool`s that support them, reviewed whenever a new workload type with unusual resource requirements is onboarded, so this gap is caught during workload design rather than discovered via an indefinitely-pending pod.

### Step-by-Step Implementation
```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: gpu-pool
spec:
  template:
    spec:
      requirements:
        - key: karpenter.k8s.aws/instance-family
          operator: In
          values: ["g5", "p4d"]
      taints:
        - key: nvidia.com/gpu
          effect: NoSchedule
```

### Under-the-Hood Explanation
Karpenter's scheduling simulation only considers instance types permitted by at least one `NodePool`'s requirements — a pending pod whose resource needs (GPU, architecture, etc.) can't be satisfied by any currently-permitted instance type simply has no viable provisioning candidate, and Karpenter correctly does nothing rather than provisioning an instance type that wouldn't actually satisfy the pod's requirements anyway.

### Common Weak Answer
"Karpenter must be broken, restart the controller."

### Why the Weak Answer Fails
Restarting a correctly-functioning controller does nothing to address a genuine configuration gap (no `NodePool` permits the required instance family) — this reflects not having checked whether the existing `NodePool` configuration structurally supports the pending pod's requirements at all.

### Follow-Up Questions
1. How would you design NodePool taints/tolerations to prevent expensive GPU capacity from being wastefully consumed by non-GPU workloads?
2. How would you monitor for "pending pods with unsatisfiable NodePool requirements" proactively, rather than discovering it reactively?
3. What's the cost-governance consideration for adding a new, expensive-instance-family NodePool to a shared cluster?

### Key Interview Signals
Correctly diagnoses a NodePool configuration gap as a structural, non-error condition rather than assuming Karpenter itself is malfunctioning, and designs cost-conscious guardrails for the new capacity.

### Hands-On Connection
[Lab 5 — Karpenter Autoscaling](../labs/lab-05-karpenter-autoscaling/).

---

## Question 37: The managed node group stuck mid-update

### Scenario
A managed node group's version update (rolling out a new AMI) stalls indefinitely at 60% complete — some old nodes have been replaced, but the remaining old nodes never drain, and no new nodes launch to replace them.

### Interview Question
Diagnose the likely cause of a stalled managed node group update.

### Strong Senior-Level Answer
**Initial assessment:** a managed node group update respects `PodDisruptionBudget`s during draining — a stalled update most commonly means the drain process for a remaining old node is blocked by a `PodDisruptionBudget` that can never be satisfied (e.g., `minAvailable` set higher than the workload's actual replica count, or a single-replica workload with a PDB requiring at least one available replica at all times, which blocks eviction of its only pod indefinitely).

**Technical reasoning:** the node group's update mechanism cordons an old node and attempts to evict its pods respecting any applicable PDBs — if evicting a specific pod would violate its PDB (and no other node exists for that pod to be rescheduled onto first, or the PDB is simply unsatisfiable as configured), the eviction is refused repeatedly, and the drain — and therefore the whole update — stalls at that specific node indefinitely.

**Investigation process:** check `kubectl get pdb -A` for any PDB whose `minAvailable`/`maxUnavailable` configuration is inconsistent with its workload's actual current replica count, and check `kubectl describe node <stalled-node>` / eviction-related events for the specific pod blocking the drain.

**Recommended solution:** fix the misconfigured PDB (aligning `minAvailable`/`maxUnavailable` with the workload's actual, intended availability tolerance) or, if the workload genuinely has too few replicas to tolerate any disruption at all, temporarily scale it up before resuming the node group update, or explicitly accept and schedule the brief disruption if appropriate.

**Risk controls:** before initiating any node group update, proactively audit every PDB in the cluster for internal consistency against current replica counts — this exact stall is entirely preventable by catching a misconfigured PDB beforehand rather than discovering it mid-rollout.

**Validation steps:** after fixing the PDB, confirm the node group update resumes and completes successfully, replacing all remaining old nodes.

**Rollback or recovery strategy:** a stalled (not failed) update can typically be resumed once the blocking condition is resolved — no need to roll back the partially-completed update, since the already-replaced nodes are healthy and correctly running the new AMI.

**Long-term prevention:** add an automated pre-upgrade check validating every PDB's `minAvailable`/`maxUnavailable` against the workload's actual current replica count, catching this class of stall before any node group update is initiated, cluster-wide.

### Step-by-Step Implementation
```bash
# Find PDBs whose configuration might be unsatisfiable
kubectl get pdb -A -o json | jq -r '.items[] | "\(.metadata.namespace)/\(.metadata.name): minAvailable=\(.spec.minAvailable) currentHealthy=\(.status.currentHealthy) desiredHealthy=\(.status.desiredHealthy)"'

# Identify the specific pod blocking eviction on the stalled node
kubectl get events -A --field-selector reason=FailedEviction
```

### Under-the-Hood Explanation
The node group's drain logic uses the standard Kubernetes Eviction API, which explicitly respects `PodDisruptionBudget`s by design — an eviction request that would violate a PDB is rejected by the API server, and the node group's update controller retries periodically rather than forcing the eviction, meaning a permanently-unsatisfiable PDB causes a permanent stall rather than an eventual timeout-and-proceed.

### Common Weak Answer
"Force-delete the stuck pods to unblock the drain."

### Why the Weak Answer Fails
Force-deleting bypasses the PDB's protection entirely, potentially causing exactly the availability loss the PDB was configured to prevent — the correct fix addresses the PDB's actual misconfiguration (or the workload's replica count) rather than overriding the safety mechanism that's correctly doing its job as configured.

### Follow-Up Questions
1. How would you design a pre-upgrade validation catching every PDB inconsistency across a large fleet before initiating any node group update?
2. What's the trade-off between a strict PDB (protecting availability) and update velocity during routine node replacement?
3. How would this same stall manifest differently under Karpenter's node-replacement mechanism versus a managed node group's update process?

### Key Interview Signals
Correctly identifies a PDB misconfiguration as the specific, common cause of a stalled node replacement, and fixes the actual constraint rather than bypassing the safety mechanism enforcing it.

### Hands-On Connection
[Lab 4 — Managed Node Groups](../labs/lab-04-managed-node-groups/).

---

## Question 38: Cluster Autoscaler's blind spot

### Scenario
A team using Cluster Autoscaler (not yet migrated to Karpenter) finds that a specific pending pod, requesting a particular combination of instance-type-specific resources (an extended network interface count), never triggers a scale-out — even though a matching ASG with the correct instance type exists and has room to grow.

### Interview Question
Explain a plausible reason Cluster Autoscaler might fail to scale out for this specific pod, distinct from a Karpenter-based cluster's failure modes.

### Strong Senior-Level Answer
**Initial assessment:** unlike Karpenter's live, per-pod scheduling simulation against actual instance-type capabilities, Cluster Autoscaler's scale-out decision relies on simulating scheduling against a **template** derived from the ASG's launch configuration/template — if that template's simulated node doesn't accurately reflect the real instance type's actual extended resource capabilities (a common gap for less-common, instance-type-specific extended resources), Cluster Autoscaler may incorrectly conclude the ASG can't satisfy the pod even though a real instance of that type actually could.

**Technical reasoning:** Cluster Autoscaler determines whether scaling out a given ASG would help by simulating the ASG's node template against pending pods — for standard resources (CPU/memory) this simulation is generally accurate, but for extended/custom resources that aren't part of Cluster Autoscaler's built-in awareness (particularly certain instance-type-specific hardware capabilities), the template may not correctly reflect what a real launched instance would actually provide, causing an incorrect "this won't help" conclusion.

**Investigation process:** confirm Cluster Autoscaler's logs show it evaluating (and rejecting) this specific ASG for this pending pod, and check whether the extended resource in question is one Cluster Autoscaler is known to have limited or no built-in awareness of — this is a documented category of limitation, not a bug specific to this cluster.

**Recommended solution:** if using an extended/custom resource type not well-supported by Cluster Autoscaler's simulation model, either restructure the workload's resource request to use a more standard mechanism Cluster Autoscaler correctly simulates, or (the increasingly common answer) migrate the affected workload's node pool to Karpenter, which performs live, accurate scheduling simulation against real instance-type specifications rather than a potentially-inaccurate static template — directly solving this exact class of gap.

**Risk controls:** if migrating only this specific pool to Karpenter while the rest of the fleet remains on Cluster Autoscaler, ensure both autoscalers are configured not to compete over the same node groups/pools, which would create its own conflict.

**Validation steps:** after the fix (either resource restructuring or Karpenter migration), confirm the previously-pending pod now correctly triggers appropriate scale-out and schedules successfully.

**Rollback or recovery strategy:** if a partial Karpenter migration for this specific pool introduces unexpected interaction issues with the remaining Cluster-Autoscaler-managed pools, isolate them clearly (distinct node selectors/taints) to prevent cross-interference.

**Long-term prevention:** treat this class of extended-resource-simulation gap as a standing reason to evaluate Karpenter migration for any workload with less-common resource requirements, rather than working around Cluster Autoscaler's template-simulation limitations indefinitely.

### Step-by-Step Implementation
```bash
# Check Cluster Autoscaler's own reasoning for rejecting a scale-out
kubectl logs -n kube-system deployment/cluster-autoscaler | grep -i "no.*scale.*up\|extended resource"
```

### Under-the-Hood Explanation
Cluster Autoscaler maintains a simulated "template node" per ASG, derived from the ASG's launch template/configuration, and uses this template to predict whether scaling out would satisfy a pending pod — for standard, well-known resources this simulation is reliable, but Cluster Autoscaler's awareness of instance-type-specific extended resources is inherently limited to what it's been explicitly taught to recognize, unlike Karpenter's approach of directly querying real EC2 instance-type specifications for its scheduling simulation.

### Common Weak Answer
"Cluster Autoscaler must just be misconfigured, check its RBAC permissions."

### Why the Weak Answer Fails
This assumes a permissions/configuration error without first considering Cluster Autoscaler's documented, structural simulation-accuracy limitation for less-common extended resources — a fundamentally different (and more instructive) explanation than a simple misconfiguration.

### Follow-Up Questions
1. What specific extended resource types is Cluster Autoscaler known to simulate less reliably?
2. How would you plan and stage a migration from Cluster Autoscaler to Karpenter for an entire fleet?
3. How does Karpenter's live scheduling simulation avoid this exact class of template-inaccuracy gap?

### Key Interview Signals
Identifies the specific architectural difference (template-based simulation vs. Karpenter's live simulation) causing this gap, rather than assuming a generic misconfiguration.

### Hands-On Connection
[Lab 5 — Karpenter Autoscaling](../labs/lab-05-karpenter-autoscaling/).

---

## Question 39: Fargate's silent DaemonSet gap

### Scenario
A team moves an entire namespace to Fargate for operational simplicity, only to discover weeks later that their security-baseline DaemonSet (host-level file-integrity monitoring) simply never runs for any workload in that namespace, with no error anywhere.

### Interview Question
Explain why this happened and what the actual options are.

### Strong Senior-Level Answer
**Initial assessment:** per [`docs/node-management-and-autoscaling.md`](../docs/node-management-and-autoscaling.md) §1, Fargate has no persistent, addressable "node" in the traditional sense that a DaemonSet's "one pod per node" model depends on — a DaemonSet targeting a Fargate-only namespace's pods simply has no node to schedule onto, and Kubernetes doesn't error or warn about this; the DaemonSet's pods for that "node" category just never materialize.

**Technical reasoning:** DaemonSets rely on the scheduler placing exactly one pod per matching node — Fargate pods each run in their own isolated micro-VM with no shared, addressable node object in the way EC2-backed nodes work, so there's structurally no target for a DaemonSet to schedule against for Fargate-hosted workloads.

**Investigation process:** confirm via `kubectl get daemonset -n <namespace>` that the DaemonSet shows zero desired/current pods for the Fargate namespace specifically, and confirm the namespace is indeed fully Fargate-backed (via its Fargate profile selector) — settling that this is the structural incompatibility, not a misconfiguration of the DaemonSet itself.

**Recommended solution:** since Fargate cannot run the DaemonSet, redesign the security requirement as a **sidecar container** injected into every pod in the namespace (via a mutating admission webhook, or explicitly in each Deployment's pod spec) rather than a DaemonSet — achieving the same per-workload security coverage through a Fargate-compatible mechanism, at the cost of the sidecar's own per-pod resource overhead (a real, if usually modest, cost consideration).

**Risk controls:** confirm the sidecar redesign genuinely provides equivalent security coverage to the original DaemonSet's host-level monitoring — a host-level file-integrity monitor and a per-pod sidecar may have meaningfully different visibility/capability, worth validating explicitly rather than assuming equivalence.

**Validation steps:** after redesigning as a sidecar, confirm every pod in the namespace actually includes and correctly runs the security sidecar, and confirm its monitoring coverage meets the original security requirement's actual intent.

**Rollback or recovery strategy:** if the sidecar approach proves insufficient for the security requirement, move this specific namespace/workload back to EC2-backed node groups where the original DaemonSet-based approach works natively, accepting the loss of Fargate's operational simplicity for this specific case.

**Long-term prevention:** before moving any namespace/workload to Fargate, explicitly check for any DaemonSet-dependent requirement (security agents, log shippers, node-level monitoring) as a standing pre-migration checklist item — this exact gap is entirely foreseeable and preventable if checked before migration rather than discovered afterward.

### Step-by-Step Implementation
```yaml
# Sidecar-based security agent, injected per-pod instead of a DaemonSet
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      containers:
        - name: my-app
          image: my-app:v1
        - name: security-sidecar
          image: security-agent:v1   # replaces the DaemonSet-based approach for Fargate compatibility
```

### Under-the-Hood Explanation
Fargate's execution model provisions dedicated, isolated compute per pod rather than scheduling pods onto a persistent, shared node object — since a DaemonSet's controller logic specifically watches for `Node` objects and ensures one matching pod per node, and Fargate's abstraction doesn't expose an addressable node in that same sense for the DaemonSet controller to target, the DaemonSet simply has nothing to schedule against, silently resulting in zero running instances for the Fargate-backed portion of the cluster.

### Common Weak Answer
"Just check why the DaemonSet pods are stuck Pending and troubleshoot from there."

### Why the Weak Answer Fails
The DaemonSet's pods aren't stuck `Pending` — they simply don't exist at all for Fargate-backed nodes, since there's no node for them to be scheduled against in the first place; troubleshooting a "stuck" state that isn't actually what's happening misses the structural incompatibility entirely.

### Follow-Up Questions
1. What other DaemonSet-dependent capabilities (besides security monitoring) commonly get missed during a Fargate migration?
2. How would you build an automated pre-migration check specifically flagging DaemonSet-dependent namespaces before they're moved to Fargate?
3. What's the resource-overhead trade-off of the sidecar approach at scale across many pods, compared to one DaemonSet pod per node?

### Key Interview Signals
Correctly identifies Fargate's structural incompatibility with DaemonSets (not a troubleshootable error state) and designs a workload-level sidecar redesign as the practical Fargate-compatible alternative.

### Hands-On Connection
[Lab 4 — Managed Node Groups](../labs/lab-04-managed-node-groups/) (Fargate profile configuration).

---

## Question 40: The node bootstrap that diverged from the AMI

### Scenario
A team maintains a custom EKS-optimized AMI (built via a Packer-based process) with several pre-installed compliance agents. A new engineer, needing to quickly add a new agent, edits the node group's user-data bootstrap script directly (adding an install step at boot time) instead of rebuilding the AMI, "to move faster."

### Interview Question
Evaluate this approach and connect it to the golden-AMI discipline established elsewhere in this repository series.

### Strong Senior-Level Answer
**Initial assessment:** installing software via a boot-time user-data script instead of baking it into the AMI reintroduces exactly the in-place-configuration-drift risk the golden-AMI pattern (per [`docs/node-management-and-autoscaling.md`](../docs/node-management-and-autoscaling.md) §7 and the companion Ansible repository's [Lab 8](../../../ansible/ansible-senior-interview-preparation/labs/lab-08-packer-ami-baking/)) exists specifically to eliminate — every node now depends on a boot-time script succeeding reliably (network reachability to a package source, no transient failure) rather than the software already being present, verified, and immutable in the AMI itself.

**Technical reasoning:** a boot-time install step is a genuine reintroduction of "moving fast" risk: it can fail silently or partially on any given boot (network blip, package-source unavailability, a race condition with another boot-time step), producing a fleet where some nodes have the new agent correctly installed and others don't — precisely the kind of instance-to-instance configuration inconsistency the golden-AMI pattern is designed to prevent, and exactly mirroring the companion Ansible repository's rolling-vs-immutable trade-off discussion (Ansible Question 50) but for the underlying node image itself rather than the application layer.

**Investigation process:** confirm whether the user-data change was already rolled out to any nodes, and if so, audit the fleet for consistency (did every node's boot-time step actually succeed) — likely revealing exactly the inconsistency this approach risks.

**Recommended solution:** revert the user-data script change and instead bake the new agent into the AMI via the existing Packer-based build process, treating the "move faster" pressure as a reason to streamline the AMI-rebuild pipeline itself (faster CI, better caching) rather than bypassing it — the durable fix addresses the actual friction (a slow rebuild process) rather than accepting configuration-drift risk as the trade-off.

**Risk controls:** any node that already booted with the ad hoc user-data change should be treated as suspect until replaced with a node from the properly-rebuilt AMI — don't assume it's equivalent without verification.

**Validation steps:** after rebuilding and rolling out the corrected AMI, confirm (via a fleet-wide compliance-agent presence check) that every node consistently has the new agent installed, with no boot-time-script-dependent variability remaining.

**Rollback or recovery strategy:** replace any nodes that booted under the ad hoc user-data script with nodes from the properly-rebuilt AMI, via the standard paced node-replacement process.

**Long-term prevention:** establish and enforce a policy that node-level software changes always go through the AMI-rebuild pipeline, never a direct user-data edit — and invest in making that pipeline fast enough that "just add a boot-time script" never feels like the faster option in the first place.

### Step-by-Step Implementation
```text
Correct process: add the new agent to the Packer build's Ansible provisioning
step (companion Ansible repo Lab 8) -> rebuild the AMI -> roll out via a
paced managed-node-group version update or Karpenter EC2NodeClass AMI
reference update -> every node consistently has the agent from boot,
verified once at bake time, not re-verified (and potentially failing)
independently on every single boot.
```

### Under-the-Hood Explanation
A golden AMI's contents are fixed and verified once, at build time — every node launched from it is guaranteed identical in that respect, with zero runtime dependency on a script succeeding. A boot-time user-data step, by contrast, re-executes independently on every single node launch, meaning its success is only as reliable as whatever it depends on (network reachability, package-source availability) being consistently available at that exact moment, for every single boot, indefinitely.

### Common Weak Answer
"It's just one small script, it's not a big deal."

### Why the Weak Answer Fails
The risk isn't the script's size — it's the reintroduction of per-boot, unverified variability into what should be a fixed, pre-verified node image, exactly the anti-pattern the golden-AMI discipline exists to eliminate, regardless of how small the specific change seems in isolation.

### Follow-Up Questions
1. How would you make the AMI-rebuild pipeline fast enough that it's never tempting to bypass it for a "quick" change?
2. How would you audit the existing fleet for nodes that might have booted under the ad hoc user-data script?
3. How does this scenario mirror the companion Ansible repository's rolling-vs-immutable patching trade-off (Question 50), applied to the node image layer specifically?

### Key Interview Signals
Recognizes boot-time user-data changes as a reintroduction of configuration drift the golden-AMI pattern is meant to eliminate, and addresses the actual root friction (slow rebuild pipeline) rather than accepting the drift risk as a trade-off for speed.

### Hands-On Connection
[Lab 4 — Managed Node Groups](../labs/lab-04-managed-node-groups/).

---

## Question 41: HPA and Karpenter, fighting in slow motion

### Scenario
A workload's HPA scales replicas up in response to load, Karpenter provisions new nodes to accommodate them, load subsides, HPA scales replicas back down, and Karpenter's consolidation then terminates the now-underutilized nodes — but this entire cycle takes so long that by the time consolidation finishes, load has spiked again, triggering the whole cycle anew. The team observes near-constant node churn.

### Interview Question
Diagnose this oscillation and design a fix.

### Strong Senior-Level Answer
**Initial assessment:** this is a timing-mismatch oscillation between two independently-operating autoscaling layers (HPA's replica scaling and Karpenter's node provisioning/consolidation) — each is behaving correctly in isolation, but their combined reaction times, relative to the workload's actual load-variation frequency, produce a self-perpetuating churn cycle rather than settling into a stable state.

**Technical reasoning:** HPA's scale-down behavior includes a stabilization window (default 5 minutes) specifically to avoid reacting too quickly to transient dips — but if Karpenter's consolidation kicks in and terminates a node *during* a brief lull that's about to reverse, and HPA then needs to scale back up (triggering fresh node provisioning) faster than the load pattern's actual period, the two systems end up perpetually chasing a moving target rather than reaching equilibrium.

**Investigation process:** correlate the actual load pattern's variation frequency/amplitude against both HPA's stabilization window and Karpenter's consolidation timing settings — this reveals whether the load pattern is genuinely too volatile for the current autoscaling timing configuration, or whether the timing settings themselves are simply too aggressive relative to a load pattern that's more predictable than the churn suggests.

**Recommended solution:** lengthen HPA's scale-down stabilization window to better tolerate brief lulls without immediately shedding replicas, and configure Karpenter's consolidation to be less aggressive (e.g., via `consolidateAfter` delay settings) so it doesn't immediately reclaim capacity the moment utilization dips, giving both systems enough "patience" to ride out short-lived fluctuations without triggering the full provision-then-reclaim cycle repeatedly.

**Risk controls:** balance this against cost — reducing consolidation aggressiveness trades some of Karpenter's cost-optimization benefit for reduced churn; tune deliberately based on the actual observed load pattern rather than defaulting to maximally conservative settings that would erode most of the cost benefit.

**Validation steps:** after tuning, observe node-churn frequency and cost over a representative period, confirming it's meaningfully reduced without materially increasing steady-state cost beyond what the workload's actual load pattern justifies.

**Rollback or recovery strategy:** revert timing adjustments if they introduce unacceptable under-provisioning during genuine sustained load increases — this is a tuning exercise requiring iteration against real observed behavior, not a one-shot fix.

**Long-term prevention:** treat HPA and Karpenter's timing settings as a jointly-tuned system, not two independently-configured components — review both together whenever either is adjusted, and monitor node-churn rate as a standing signal for this exact oscillation pattern recurring after any future load-pattern change.

### Step-by-Step Implementation
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
spec:
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 600   # lengthened from default 300s
```
```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
spec:
  disruption:
    consolidateAfter: 10m   # give more patience before reclaiming capacity
```

### Under-the-Hood Explanation
HPA and Karpenter operate on entirely independent control loops with no awareness of each other's timing — HPA reacts to metrics on its own polling/stabilization schedule, and Karpenter's consolidation reacts to observed node utilization on its own schedule; if these two independent timings are each individually reasonable but poorly matched to the workload's actual load-variation period, the composition of both loops can produce oscillation neither loop would exhibit in isolation.

### Common Weak Answer
"Just disable Karpenter consolidation entirely to stop the churn."

### Why the Weak Answer Fails
This discards essentially all of Karpenter's cost-optimization value (the entire point of consolidation) as a blunt fix for a timing-tuning problem — the correct fix adjusts the relative timing of both systems to match the workload's actual behavior, preserving most of the cost benefit while eliminating the churn.

### Follow-Up Questions
1. How would you determine the right stabilization/consolidation timing values empirically, rather than guessing?
2. What's the cost trade-off of a more conservative consolidation setting across the whole fleet, not just this one workload?
3. How would you monitor for this exact oscillation pattern proactively across many different workloads with different load patterns?

### Key Interview Signals
Diagnoses the interaction between two independently-correct autoscaling systems as the actual cause of oscillation, and tunes their relative timing rather than disabling one system's core value proposition.

### Hands-On Connection
[Lab 5 — Karpenter Autoscaling](../labs/lab-05-karpenter-autoscaling/) and [Lab 6 — Storage: EBS/EFS CSI](../labs/lab-06-storage-ebs-efs-csi/) (autoscaling interactions with storage-bound workloads).

---

## Question 42: Bootstrapping a node group Terraform doesn't fully own

### Scenario
A newly-onboarded team insists on manually launching a few "special" EC2 instances directly (outside Terraform, outside any managed node group or Karpenter NodePool) and joining them to the cluster manually via the EKS bootstrap script, for a workload they claim has unusual requirements Terraform's module "can't express yet."

### Interview Question
Evaluate this request and design the correct path forward.

### Strong Senior-Level Answer
**Initial assessment:** manually-joined, unmanaged nodes outside of Terraform/managed-node-group/Karpenter's tracking are exactly the "invisible to your automation" risk pattern established in the companion Ansible repository's [Question 52](../../../ansible/ansible-senior-interview-preparation/interview-questions/05-aws-cloud-integration.md#question-52-the-tag-that-decided-everything) tagging-guardrail scenario, applied here to node lifecycle — these nodes won't be patched, replaced, or accounted for by any of the fleet's normal lifecycle-management processes, and their existence may not even be discoverable without deliberate auditing.

**Technical reasoning:** a manually-launched, manually-joined node has no ASG/launch-template/Karpenter-NodeClaim backing it — it won't be included in any managed node group's version-upgrade rollout, won't be replaced automatically on failure, and (unless deliberately tagged and audited for) may not appear in any inventory of "nodes this platform team is responsible for," exactly the invisible-infrastructure risk this repository series consistently flags.

**Investigation process:** understand the actual "unusual requirement" driving this request — in most cases, what seems to require manual node management can actually be expressed via Karpenter's flexible `NodePool`/`EC2NodeClass` constraints (custom AMI, custom user-data, specific instance families) or a dedicated, Terraform-managed self-managed node group, without resorting to fully unmanaged, manually-joined instances.

**Recommended solution:** work with the team to express their actual requirement through a properly Terraform/Karpenter-managed mechanism — extending the existing module/NodePool configuration to support whatever genuinely unusual need exists, rather than accepting a manually-managed, invisible exception to the fleet's lifecycle-management guarantees.

**Risk controls:** if a genuinely unmanageable-through-normal-means requirement exists (rare), require explicit, documented tagging and inclusion in a tracked exceptions registry, plus an explicit compensating process (manual patching cadence, manual monitoring) acknowledging what's being given up by operating outside normal fleet management — never a silent, undocumented exception.

**Validation steps:** confirm whatever solution is reached (extended Karpenter configuration, Terraform module extension, or a documented tracked exception) is actually discoverable by the platform team's standard fleet-inventory and patching processes going forward.

**Rollback or recovery strategy:** if manually-launched nodes already exist, bring them under proper management (replace with Karpenter/Terraform-provisioned equivalents) as the correction, rather than retroactively trying to "adopt" unmanaged instances into existing automation, which is often more error-prone than clean replacement.

**Long-term prevention:** establish and enforce a policy that no node joins the cluster outside of Terraform-managed node groups or Karpenter's NodePool mechanism — treating any request for an exception as a signal to extend the existing managed mechanisms' flexibility, not to create an unmanaged, invisible carve-out.

### Step-by-Step Implementation
```yaml
# Express the "unusual requirement" through Karpenter's flexible NodeClass instead of manual instances
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: special-requirement-nodeclass
spec:
  amiFamily: Custom
  amiSelectorTerms:
    - id: ami-0123456789abcdef0   # the team's custom AMI, still Karpenter-managed
  userData: |
    #!/bin/bash
    # any genuinely special bootstrap logic, still tracked and reproducible
```

### Under-the-Hood Explanation
Managed node groups and Karpenter both maintain an explicit, queryable record of every node they've provisioned (via ASG membership or Karpenter's `NodeClaim` objects respectively) — a manually-launched, manually-joined instance has no such record anywhere in this tracking, meaning every automated process built around "the fleet is whatever Terraform/Karpenter says it is" simply doesn't see it, exactly the same structural blind spot as an untagged, manually-launched EC2 instance in the companion Ansible repository's tagging-guardrail scenario.

### Common Weak Answer
"It's just a few instances, let them do it as a one-off exception."

### Why the Weak Answer Fails
"A few instances" as an unmanaged, invisible exception is exactly how this class of gap accumulates over time — each individually-reasonable exception compounds into a growing set of unmanaged, unpatched, untracked nodes that nobody has full visibility into, precisely the failure mode this repository series consistently warns against.

### Follow-Up Questions
1. How would you audit an existing fleet for any already-present manually-joined, unmanaged nodes?
2. What's the actual process for extending a Karpenter EC2NodeClass or Terraform module to support a genuinely novel requirement?
3. If a genuinely unmanageable exception is truly necessary, what compensating controls would you require?

### Key Interview Signals
Recognizes manually-managed, unmanaged nodes as an invisible-infrastructure risk directly analogous to the untagged-instance pattern established elsewhere in this repository series, and works to express the underlying requirement through proper managed mechanisms rather than accepting a silent exception.

### Hands-On Connection
[Lab 4 — Managed Node Groups](../labs/lab-04-managed-node-groups/) and [Lab 5 — Karpenter Autoscaling](../labs/lab-05-karpenter-autoscaling/).
