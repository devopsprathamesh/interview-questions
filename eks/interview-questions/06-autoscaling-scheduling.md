# Category 6: Autoscaling and Scheduling

Questions 53–60 of 120. Category weight: 8 questions. Deep-dive reference: [`docs/node-management-and-autoscaling.md`](../docs/node-management-and-autoscaling.md).

---

## Question 53: HPA and VPA, fighting over the same dial

### Scenario
A workload has both HPA (scaling on CPU utilization) and VPA (in `Auto` mode, adjusting CPU requests/limits) configured simultaneously. Replica count and per-pod CPU allocation both oscillate unpredictably under steady load, with the workload never settling into a stable state.

### Interview Question
Diagnose the interaction causing this and design the fix.

### Strong Senior-Level Answer
**Initial assessment:** per [`docs/node-management-and-autoscaling.md`](../docs/node-management-and-autoscaling.md) §5, HPA and VPA both adjusting the *same* resource dimension (CPU) on the same workload creates a feedback loop — HPA reacts to per-pod CPU utilization by changing replica count, while VPA simultaneously reacts to observed usage by changing the per-pod CPU request itself, and each system's adjustment changes the input the other system is reacting to, without either being aware of the other's existence.

**Technical reasoning:** VPA in `Auto` mode actually restarts pods to apply new resource requests — each such restart changes the pod count/availability HPA is also observing, and HPA's own scaling changes the aggregate CPU-utilization-per-pod picture VPA is basing its own recommendation on; neither system has any coordination mechanism with the other, so both can end up perpetually reacting to changes the other one caused.

**Investigation process:** confirm via HPA/VPA events and metrics history that scaling/resizing events for both correlate closely in time with each other rather than independently with genuine load changes — this confirms the mutual-feedback-loop diagnosis rather than, say, a genuinely volatile underlying load pattern.

**Recommended solution:** scope HPA and VPA to different resource dimensions if both are genuinely needed (e.g., HPA on CPU, VPA on memory only, via VPA's `resourcePolicy.containerPolicies[].controlledResources` setting), or, more commonly, run VPA in `Off`/recommendation-only mode (providing sizing guidance for a human/CI process to apply deliberately) rather than `Auto` mode when HPA is also active on the same workload.

**Risk controls:** whichever approach is chosen, validate under a realistic, sustained load test that the workload actually settles into a stable state rather than continuing to oscillate, before considering the fix complete.

**Validation steps:** observe replica count and per-pod resource allocation over a representative period post-fix, confirming both stabilize appropriately in response to genuine load changes without oscillating independently of actual load.

**Rollback or recovery strategy:** revert to whichever single-mechanism configuration (HPA alone, or VPA alone in Auto mode) was stable before introducing the conflicting combination, while a properly-scoped combined configuration is designed and tested.

**Long-term prevention:** treat HPA and VPA co-configuration on the same workload as requiring explicit, deliberate resource-dimension scoping (or choosing recommendation-only VPA mode) as a standard design review item, rather than enabling both by default assuming they'll compose safely.

### Step-by-Step Implementation
```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
spec:
  updatePolicy:
    updateMode: "Off"   # recommendation-only, avoids fighting with HPA's CPU-based scaling
  resourcePolicy:
    containerPolicies:
      - containerName: '*'
        controlledResources: ["memory"]   # if Auto mode is used, scope to a dimension HPA doesn't touch
```

### Under-the-Hood Explanation
HPA's control loop polls metrics (via `metrics-server` or a custom/external metrics API) on its own interval and adjusts `spec.replicas`; VPA's recommender independently observes historical usage and its updater (in `Auto` mode) evicts/recreates pods with new resource requests on its own schedule — since Kubernetes provides no built-in coordination primitive between these two independently-operating controllers, any overlap in the resource dimension each is reacting to and adjusting creates the potential for this exact mutual-feedback oscillation.

### Common Weak Answer
"Just disable one of them, whichever seems less important."

### Why the Weak Answer Fails
This discards real value (either finer-grained resource-request accuracy from VPA, or replica-count elasticity from HPA) rather than correctly scoping the two to non-overlapping resource dimensions, which preserves both mechanisms' benefit without the oscillation.

### Follow-Up Questions
1. How would you determine appropriate VPA resource-policy scoping for a workload with genuinely variable memory needs alongside CPU-based HPA scaling?
2. What's the operational cost of VPA's `Auto` mode's pod restarts on a latency-sensitive workload?
3. How would KEDA (event-driven autoscaling) change this picture if introduced as a third scaling mechanism?

### Key Interview Signals
Identifies the specific mutual-feedback mechanism between HPA and VPA on an overlapping resource dimension, and resolves it via deliberate scoping rather than discarding one mechanism entirely.

### Hands-On Connection
[Lab 5 — Karpenter Autoscaling](../labs/lab-05-karpenter-autoscaling/).

---

## Question 54: The custom metric that scaled on noise

### Scenario
An HPA configured to scale on a custom metric (queue depth from an external message queue, via the Prometheus Adapter) scales the workload up and down erratically, seemingly disconnected from actual processing backlog.

### Interview Question
Diagnose likely causes of erratic custom-metric-based scaling.

### Strong Senior-Level Answer
**Initial assessment:** custom-metric-based HPA scaling is only as stable as the underlying metric's own signal quality and the query/aggregation window computing it — erratic scaling most commonly traces back to a noisy, poorly-aggregated, or improperly-scoped metric query, not an HPA malfunction itself.

**Technical reasoning:** if the Prometheus query backing this custom metric uses an instantaneous or very short-window value (rather than an appropriately smoothed rate/average over a reasonable window matching the workload's actual processing cadence), transient spikes/dips in queue depth (normal, momentary fluctuation) get treated by HPA as genuine, sustained signal, triggering scaling reactions to noise rather than real backlog trends.

**Investigation process:** review the actual PromQL query configured in the `ExternalMetric`/`PodsMetric` definition backing this HPA, checking its aggregation window and whether it's querying a raw, instantaneous value versus an appropriately time-windowed rate/average — and cross-reference the HPA's own polling interval and stabilization window settings against the metric's natural volatility.

**Recommended solution:** adjust the underlying PromQL query to use a suitable averaging/rate window (e.g., `avg_over_time(queue_depth[5m])` rather than an instantaneous point value) matching the workload's actual processing timescale, and tune HPA's `stabilizationWindowSeconds` (both scale-up and scale-down) to avoid reacting to short-lived fluctuations within that same timescale.

**Risk controls:** balance smoothing against responsiveness — an overly long averaging window risks the HPA reacting too slowly to a genuine, sustained backlog increase; tune based on the actual observed relationship between queue-depth volatility and genuine processing-capacity need.

**Validation steps:** after adjusting the query/stabilization settings, observe scaling behavior over a representative period with both genuinely quiet and genuinely busy conditions, confirming scaling now tracks real backlog trends rather than short-term noise.

**Rollback or recovery strategy:** revert to the previous metric query/HPA configuration if the adjustment overcorrects (now too slow to react to genuine spikes) — this is an iterative tuning process, not a one-shot fix.

**Long-term prevention:** treat any custom-metric-based HPA's underlying query as requiring the same careful, workload-timescale-informed tuning as any alerting threshold — a poorly-smoothed metric query is a common, avoidable source of erratic autoscaling behavior.

### Step-by-Step Implementation
```yaml
# Prometheus Adapter rule - properly smoothed query instead of an instantaneous value
- seriesQuery: 'queue_depth{namespace!="",pod!=""}'
  metricsQuery: 'avg_over_time(queue_depth{<<.LabelMatchers>>}[5m])'
```
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
spec:
  behavior:
    scaleUp:   { stabilizationWindowSeconds: 60 }
    scaleDown: { stabilizationWindowSeconds: 300 }
```

### Under-the-Hood Explanation
HPA polls its configured metric source at a regular interval and reacts directly to whatever value it receives — it has no inherent smoothing of its own beyond the `stabilizationWindowSeconds` behavior settings (which govern how quickly it acts on a *change* in the computed desired-replica-count, not the underlying metric's own noise) — meaning the actual signal quality is entirely determined by how the metric itself is queried/aggregated upstream, in Prometheus's own query, before it ever reaches HPA.

### Common Weak Answer
"Just increase the HPA's polling interval to reduce noise."

### Why the Weak Answer Fails
HPA's polling interval affects how often it checks the metric, not how noisy the metric's underlying value is — the actual fix is smoothing the metric query itself (an averaging/rate window in the PromQL), which addresses the noise at its source rather than just checking a still-noisy value less frequently.

### Follow-Up Questions
1. How would you choose an appropriate averaging window empirically for a specific workload's processing cadence?
2. What's the trade-off between `stabilizationWindowSeconds` tuning and query-level smoothing — are they solving the same or different problems?
3. How would KEDA's scaler-specific configuration options compare to the Prometheus Adapter approach here?

### Key Interview Signals
Correctly locates the noise source in the underlying metric query rather than in HPA's own polling/reaction behavior, and tunes both the query and HPA settings appropriately.

### Hands-On Connection
[Lab 5 — Karpenter Autoscaling](../labs/lab-05-karpenter-autoscaling/) and [Lab 9 — Observability Stack](../labs/lab-09-observability-stack/).

---

## Question 55: The taint nobody remembered to add

### Scenario
A dedicated, expensive GPU node pool (provisioned via Karpenter, per Question 36) is discovered — during a cost review — to be running several non-GPU workloads that happened to schedule there because the node pool wasn't actually tainted, only its intended workloads were configured with a matching node *affinity* (not a required toleration).

### Interview Question
Diagnose the scheduling gap and design the correct constraint.

### Strong Senior-Level Answer
**Initial assessment:** node affinity alone (even `requiredDuringSchedulingIgnoredDuringExecution` affinity on the *intended* GPU workloads) only controls where those specific workloads *can* schedule — it does nothing to prevent *other*, unrelated workloads (with no such affinity, and no toleration requirement) from also landing on the same nodes if they otherwise fit; taints (on the nodes) paired with tolerations (on the intended workloads) are the actual mechanism needed to *reserve* nodes exclusively.

**Technical reasoning:** without a taint on the GPU nodes, any pod satisfying basic resource requirements (CPU/memory) can be scheduled there by the default scheduler, regardless of whether it has any GPU-related affinity — affinity is a pull mechanism ("I want to go here"), while taint/toleration is the corresponding push-back mechanism ("nothing may come here unless it explicitly tolerates this") that dedicated node pools actually require to be genuinely exclusive.

**Investigation process:** confirm via `kubectl describe node <gpu-node>` the absence of any taint, and confirm via `kubectl get pods -o wide` on that node which non-GPU workloads have landed there — settling that this is a missing-taint gap, not a misconfigured affinity on the intended workloads.

**Recommended solution:** add the taint to the GPU `NodePool`'s node template (per Question 36's example) and add the corresponding toleration to the GPU-requiring workloads specifically — with the taint now actively preventing any pod lacking the toleration from scheduling there, correctly reserving the expensive capacity exclusively for its intended purpose.

**Risk controls:** after adding the taint, existing non-GPU workloads already running on these nodes won't be automatically evicted (taints only affect *new* scheduling decisions by default, unless combined with `NoExecute` effect) — explicitly reschedule/evict them to actually reclaim the capacity, not just prevent future misallocation.

**Validation steps:** after the fix, confirm no new non-GPU workload can schedule onto the GPU nodes (a deliberate test pod without the toleration should remain `Pending` or schedule elsewhere), and confirm the GPU-requiring workloads continue to schedule and run correctly with their toleration in place.

**Rollback or recovery strategy:** removing the taint reverts to the previous (mis-)behavior if the fix causes an unexpected issue — a low-risk, reversible change.

**Long-term prevention:** treat taint+toleration (not affinity alone) as the standard, required pattern for any genuinely dedicated/reserved node pool, and add this as an explicit checklist item whenever provisioning specialized, cost-sensitive compute capacity.

### Step-by-Step Implementation
```yaml
# Taint on the GPU NodePool (the missing piece)
apiVersion: karpenter.sh/v1
kind: NodePool
spec:
  template:
    spec:
      taints:
        - key: nvidia.com/gpu
          effect: NoSchedule
```
```yaml
# Toleration on the GPU-requiring workload
spec:
  tolerations:
    - key: nvidia.com/gpu
      operator: Exists
      effect: NoSchedule
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - { key: karpenter.k8s.aws/instance-family, operator: In, values: ["g5"] }
```

### Under-the-Hood Explanation
The scheduler treats affinity and taint/toleration as two independent filtering mechanisms — affinity narrows *which* nodes a given pod is allowed to consider (a constraint on the pod's own placement options), while taints narrow *which pods* a given node is willing to accept (a constraint the node itself imposes) — genuinely exclusive node reservation requires the node-side mechanism (taint), since affinity alone says nothing about what *other*, unrelated pods with no affinity constraint at all are permitted to do.

### Common Weak Answer
"The GPU workloads have affinity set correctly, that should be enough to keep other workloads off."

### Why the Weak Answer Fails
Affinity constrains the *intended* workload's own placement options — it has no effect whatsoever on unrelated pods that never declared any affinity in the first place, which is exactly why non-GPU workloads were freely scheduling onto these nodes despite the GPU workloads' own affinity being correctly configured.

### Follow-Up Questions
1. How would you handle already-running misallocated workloads on the GPU nodes without disrupting them abruptly?
2. What's the difference between `NoSchedule` and `NoExecute` taint effects, and when would you use each here?
3. How would you monitor for this exact class of node-pool misallocation proactively across the whole fleet?

### Key Interview Signals
Correctly distinguishes affinity (pod-side pull) from taint/toleration (node-side push-back) as the actual mechanism needed for genuine node-pool exclusivity.

### Hands-On Connection
[Lab 5 — Karpenter Autoscaling](../labs/lab-05-karpenter-autoscaling/).

---

## Question 56: The topology spread constraint that scheduled nothing

### Scenario
A Deployment with a `topologySpreadConstraint` set to `whenUnsatisfiable: DoNotSchedule` across `topology.kubernetes.io/zone` gets stuck with several replicas permanently `Pending`, even though the cluster has ample total capacity across all AZs.

### Interview Question
Diagnose why `DoNotSchedule` is causing pods to remain unscheduled despite available capacity.

### Strong Senior-Level Answer
**Initial assessment:** `whenUnsatisfiable: DoNotSchedule` is a *hard* constraint — if the scheduler cannot place a pod without violating the configured `maxSkew` (the maximum allowed imbalance in replica count across the topology domains), it leaves the pod `Pending` rather than scheduling it in a way that would violate the constraint, even if raw capacity exists in an "over-represented" zone.

**Technical reasoning:** if, for example, `maxSkew: 1` is configured across 3 AZs and one AZ genuinely has less available capacity (or is entirely at capacity) than the other two, the scheduler may be structurally unable to maintain the requested even distribution without exceeding `maxSkew` in the remaining AZs — with `DoNotSchedule`, it correctly refuses to violate this constraint rather than silently scheduling unevenly, leaving the pod stuck rather than accepting an imbalance.

**Investigation process:** confirm via `kubectl describe pod` the specific scheduling failure reason (referencing the topology spread constraint explicitly) and check actual available capacity per AZ — this determines whether the issue is genuine capacity imbalance across AZs (an autoscaler/node-pool gap) versus the `maxSkew` value itself being too strict for the current replica count/AZ count ratio.

**Recommended solution:** either address the underlying capacity imbalance (ensure the autoscaler can provision capacity evenly across all relevant AZs) or, if the imbalance is a genuine, acceptable/expected condition (e.g., one AZ temporarily has less available capacity for legitimate reasons), switch `whenUnsatisfiable` to `ScheduleAnyway` for this constraint specifically — treating even distribution as a *preference* rather than a hard requirement, which trades some spread guarantee for actually getting pods scheduled.

**Risk controls:** understand and explicitly accept the trade-off before switching to `ScheduleAnyway` — this reduces the AZ-resilience guarantee (per [`docs/ha-dr.md`](../docs/ha-dr.md) §2) that the topology spread constraint exists to provide, in exchange for scheduling flexibility; this shouldn't be a default choice made just to make a stuck-pod symptom go away without considering the trade-off.

**Validation steps:** after the fix (either capacity rebalancing or the `ScheduleAnyway` change), confirm all replicas schedule successfully, and if `ScheduleAnyway` was chosen, confirm the actual resulting distribution is still reasonably balanced under normal conditions, only diverging during genuine capacity constraints.

**Rollback or recovery strategy:** revert to `DoNotSchedule` once the underlying capacity imbalance is fixed, restoring the stronger AZ-resilience guarantee once it can actually be satisfied.

**Long-term prevention:** monitor per-AZ available capacity as a standing signal for any workload using `DoNotSchedule` topology spread constraints, catching capacity imbalance before it causes stuck pods rather than discovering it reactively.

### Step-by-Step Implementation
```yaml
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: ScheduleAnyway   # changed from DoNotSchedule, a deliberate trade-off
    labelSelector:
      matchLabels: { app: my-app }
```

### Under-the-Hood Explanation
The scheduler's topology-spread scoring/filtering logic computes, for each candidate node, whether placing the pod there would keep the per-topology-domain replica-count skew within `maxSkew` — under `DoNotSchedule`, any node that would violate this is entirely filtered out as a candidate, and if every remaining node would violate it (due to genuine, current capacity imbalance across domains), the pod has no valid placement at all and remains `Pending`, exactly reflecting the hard-constraint semantics as configured.

### Common Weak Answer
"Just remove the topology spread constraint entirely to unblock scheduling."

### Why the Weak Answer Fails
This discards the AZ-resilience guarantee entirely rather than making a deliberate, informed trade-off — switching to `ScheduleAnyway` preserves the *preference* for even distribution while allowing scheduling to proceed under genuine constraint, a meaningfully better outcome than abandoning the spread requirement altogether.

### Follow-Up Questions
1. How would you distinguish a genuine, temporary capacity imbalance from a persistent, structural one requiring node-pool reconfiguration?
2. What's the interaction between topology spread constraints and Karpenter's own provisioning decisions?
3. How would you monitor actual achieved distribution over time to confirm `ScheduleAnyway` isn't silently degrading resilience more than expected?

### Key Interview Signals
Understands `DoNotSchedule`'s hard-constraint semantics precisely and makes a deliberate, trade-off-aware choice (capacity fix vs. `ScheduleAnyway`) rather than abandoning the resilience guarantee reflexively to clear a stuck-pod symptom.

### Hands-On Connection
[Lab 5 — Karpenter Autoscaling](../labs/lab-05-karpenter-autoscaling/) and [Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).

---

## Question 57: KEDA versus HPA's built-in metrics

### Scenario
A team needs to scale a workload based on the depth of an external SQS queue it consumes from, with the ability to scale down to zero replicas entirely during genuinely idle periods. They ask whether standard HPA (with the Prometheus Adapter, per Question 54) or KEDA is the better fit.

### Interview Question
Make the recommendation and explain the deciding factor.

### Strong Senior-Level Answer
**Initial assessment:** the scale-to-zero requirement is the deciding factor here — standard HPA cannot scale a Deployment to zero replicas at all (its minimum is always at least 1), while KEDA is specifically designed to support scaling to and from zero based on external event-source metrics, making it the structurally correct choice for this exact requirement.

**Technical reasoning:** KEDA operates by installing a `ScaledObject` that, under the hood, still ultimately drives a standard HPA object for the non-zero scaling range, but additionally manages the zero-to-one transition itself (activating/deactivating based on the event source's metric crossing a threshold) — a capability HPA's own architecture doesn't provide natively, since HPA assumes at least one replica is always running to be scaled from.

**Investigation process:** confirm the actual business requirement genuinely needs scale-to-zero (cost savings during long idle periods, e.g., a batch-processing queue consumer that's often completely idle) rather than just "scale down to a low number" — if minimum-1-replica is actually fine, standard HPA with the Prometheus Adapter remains a perfectly reasonable, simpler choice without introducing KEDA as an additional component.

**Recommended solution:** for this specific scale-to-zero requirement, adopt KEDA with its built-in AWS SQS scaler (a purpose-built integration, removing the need to separately wire up the Prometheus Adapter/CloudWatch-exporter path just to expose queue depth as a metric) — a more direct, purpose-fit solution than assembling the equivalent capability from HPA plus custom metric plumbing, which still wouldn't achieve scale-to-zero regardless.

**Risk controls:** scaling from zero introduces a genuine cold-start latency (time to provision a pod, and potentially a new node via Karpenter, before the first message can be processed) — validate this latency is acceptable for the workload's actual latency requirements before committing to the scale-to-zero approach.

**Validation steps:** test the full zero-to-scaled and scaled-to-zero transition under realistic queue-arrival patterns, confirming both the cost savings during idle periods and the acceptable cold-start latency when new messages arrive after an idle period.

**Rollback or recovery strategy:** if cold-start latency proves unacceptable, configure a `minReplicaCount` of 1 (rather than 0) within the KEDA `ScaledObject`, retaining KEDA's purpose-built SQS integration while sacrificing the full scale-to-zero cost benefit for reduced latency — a middle-ground adjustment rather than reverting to plain HPA entirely.

**Long-term prevention:** establish scale-to-zero as an explicit decision criterion (not an afterthought) when evaluating HPA versus KEDA for any new event-driven workload, given HPA's structural inability to support it at all.

### Step-by-Step Implementation
```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: sqs-consumer-scaler
spec:
  scaleTargetRef:
    name: sqs-consumer
  minReplicaCount: 0   # scale-to-zero, not possible with standard HPA
  maxReplicaCount: 20
  triggers:
    - type: aws-sqs-queue
      metadata:
        queueURL: https://sqs.us-east-1.amazonaws.com/ACCOUNT/my-queue
        queueLength: "5"
      authenticationRef:
        name: keda-aws-credentials   # IRSA-backed, per docs/iam-irsa.md
```

### Under-the-Hood Explanation
KEDA's controller manages the zero-to-one activation itself (polling the external metric source directly, independent of the standard `metrics.k8s.io`/`external.metrics.k8s.io` API HPA relies on for its own polling) and, once at least one replica is running, hands off to a KEDA-managed HPA object for scaling within the non-zero range — combining a capability HPA's own architecture doesn't provide (zero-replica activation) with HPA's proven scaling mechanism for everything above that threshold.

### Common Weak Answer
"HPA can do this too if you just set minReplicas to 0."

### Why the Weak Answer Fails
Standard Kubernetes HPA does not support `minReplicas: 0` at all — this is a hard API-level restriction, not a configuration option; achieving scale-to-zero genuinely requires KEDA (or a custom controller providing equivalent capability), not a parameter tweak to plain HPA.

### Follow-Up Questions
1. How would you measure and validate cold-start latency for this workload before committing to scale-to-zero in production?
2. What other event sources does KEDA support beyond SQS, and how would this generalize to a different external trigger?
3. How does KEDA's `ScaledObject` interact with Karpenter's own node-provisioning latency during a scale-from-zero event?

### Key Interview Signals
Correctly identifies HPA's structural inability to scale to zero as the deciding factor, and recommends KEDA specifically for its purpose-built activation and event-source-scaler capabilities rather than assuming HPA can be configured to achieve the same result.

### Hands-On Connection
[Lab 5 — Karpenter Autoscaling](../labs/lab-05-karpenter-autoscaling/).

---

## Question 58: The priority class that starved everything else

### Scenario
A new, business-critical workload is given a very high `PriorityClass` to "make sure it always gets scheduled." Shortly after, several unrelated, lower-priority workloads begin being preempted (evicted) unexpectedly during normal cluster operation, even without any genuine resource shortage event.

### Interview Question
Diagnose why a high-priority workload is causing preemption even without an actual capacity crunch, and correct the configuration.

### Strong Senior-Level Answer
**Initial assessment:** `PriorityClass` and preemption are powerful, cluster-wide-effect mechanisms — assigning very high priority "to be safe" without matching it to genuinely proportionate resource requests can cause the scheduler to preempt lower-priority pods to make room, even under conditions that wouldn't otherwise be a genuine emergency, since the scheduler is doing exactly what priority/preemption is designed to do: ensure a higher-priority pod schedules, at the cost of evicting lower-priority ones if necessary.

**Technical reasoning:** if this new workload's resource *requests* are set generously (perhaps also "to be safe," oversized relative to actual need) combined with very high priority, the scheduler may find it needs to preempt more lower-priority pods than would actually be necessary if the workload's requests accurately reflected its real resource needs — the preemption behavior is functioning correctly given the inputs, but the inputs (priority and/or request sizing) don't accurately reflect genuine relative importance and need.

**Investigation process:** review both the new workload's actual `PriorityClass` value relative to what's genuinely warranted (is it *the* most critical thing in the cluster, or was "very high" chosen without calibrating against what else already holds high priority) and its resource requests relative to its actual observed usage — oversized requests combined with high priority compounds the preemption impact unnecessarily.

**Recommended solution:** right-size the workload's resource requests based on actual observed usage (reducing the amount of capacity that needs to be freed via preemption in the first place), and calibrate its `PriorityClass` deliberately against the organization's actual priority hierarchy (reserving the highest tiers for genuinely irreplaceable, cluster-critical workloads) rather than defaulting to "very high" for anything deemed business-important.

**Risk controls:** establish and document a small, deliberately-designed set of `PriorityClass` tiers (e.g., `critical-infrastructure`, `production-standard`, `batch-best-effort`) with clear criteria for each, rather than allowing every team to independently choose an arbitrarily high value for their own workload.

**Validation steps:** after right-sizing requests and re-calibrating priority, confirm the workload still reliably schedules under genuine resource pressure (its actual intended protection), while normal-condition preemption of unrelated workloads stops occurring.

**Rollback or recovery strategy:** if right-sizing/re-calibration doesn't fully resolve unwanted preemption, investigate whether genuine cluster-wide capacity is simply insufficient (an autoscaler capacity issue, distinct from a priority-configuration issue) as the underlying cause.

**Long-term prevention:** treat `PriorityClass` assignment as a governed, reviewed decision (not self-service, arbitrary "very high" selection) with a documented tier structure, and pair any priority assignment review with a resource-request accuracy check, since the two compound each other's impact on preemption behavior.

### Step-by-Step Implementation
```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: production-standard
value: 100000   # deliberately calibrated against a documented tier structure
globalDefault: false
description: "Standard production workloads - not the highest tier, reserved for genuinely critical infrastructure"
```

### Under-the-Hood Explanation
The scheduler's preemption logic, when a high-priority pod can't otherwise be scheduled, identifies and evicts lower-priority pods on some node(s) to free enough resources — it evaluates this purely based on the configured priority values and each pod's resource requests, with no awareness of whether the requesting team's actual intent was "this needs the absolute highest priority in the cluster" or just "this feels important to us" — the mechanism does exactly what the configured values instruct, regardless of how carefully those values were chosen.

### Common Weak Answer
"Just lower the new workload's priority until preemption stops."

### Why the Weak Answer Fails
This treats the symptom without addressing whether the resource requests are also oversized (compounding any priority level's preemption impact) or whether a documented, calibrated priority-tier structure exists at all — a piecemeal, reactive priority reduction doesn't prevent the next team from making the same "very high, to be safe" choice for their own workload.

### Follow-Up Questions
1. How would you design and document an organization-wide PriorityClass tier structure that prevents this kind of ad hoc, uncalibrated assignment?
2. What's the interaction between PriorityClass-driven preemption and Karpenter's own provisioning — does Karpenter provision new capacity instead of relying on preemption in some cases?
3. How would you monitor for unexpected preemption events as a standing signal, rather than discovering this reactively via team complaints?

### Key Interview Signals
Identifies that priority and resource-request sizing compound each other's preemption impact, and designs a governed, calibrated priority-tier structure rather than a reactive, piecemeal adjustment.

### Hands-On Connection
[Lab 5 — Karpenter Autoscaling](../labs/lab-05-karpenter-autoscaling/).

---

## Question 59: Cluster-proportional scaling for a shared add-on

### Scenario
CoreDNS (per Question 15) has had its replica count manually bumped from 2 to 6 to handle current fleet size. Six months later, the fleet has grown further, and DNS latency issues recur — the manual replica count was never revisited.

### Interview Question
Design a solution that doesn't require remembering to manually adjust this again.

### Strong Senior-Level Answer
**Initial assessment:** a manually-set replica count for a fleet-size-proportional workload (like CoreDNS) is exactly the same "remember to adjust it later" gap this repository series consistently flags — the correct fix is a mechanism that automatically scales the component's replica count in proportion to cluster size, removing the dependency on anyone remembering to revisit a manual setting as the fleet grows.

**Technical reasoning:** the **cluster-proportional-autoscaler** (a purpose-built controller for exactly this pattern) adjusts a target Deployment's replica count based on a configured ratio to cluster size (node count or core count), specifically designed for fleet-size-proportional add-ons like CoreDNS where a fixed replica count inevitably becomes insufficient (or excessive) as the fleet's size changes over time.

**Investigation process:** confirm the current CoreDNS replica count is indeed still a manually-set static value with no proportional-scaling mechanism, and confirm cluster growth since the last manual adjustment correlates with the recurrence of the original latency symptoms from Question 15.

**Recommended solution:** deploy the cluster-proportional-autoscaler targeting the CoreDNS Deployment, configured with a ratio (e.g., "1 CoreDNS replica per N nodes, minimum 2") reflecting the fleet's actual demonstrated DNS-load characteristics — replacing the manual, easily-stale replica count with a self-adjusting one.

**Risk controls:** validate the chosen ratio against actual DNS query volume per node (not just an arbitrary guess) so the proportional scaling genuinely tracks real load, not just node count as an imperfect proxy for it.

**Validation steps:** after deployment, confirm CoreDNS replica count actually adjusts automatically as the fleet scales up/down over subsequent weeks, and confirm DNS latency remains stable through a deliberate scale-up test rather than requiring another manual intervention.

**Rollback or recovery strategy:** the cluster-proportional-autoscaler can be removed (reverting to a static replica count) if its behavior proves undesirable for any reason — a low-risk, contained addition.

**Long-term prevention:** apply this same "don't rely on a manually-set value for anything that should scale with fleet size" principle to any other fleet-size-proportional component in the cluster (any shared add-on whose appropriate capacity naturally grows with cluster size), rather than treating this as a one-off fix specific to CoreDNS alone.

### Step-by-Step Implementation
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns-autoscaler
  namespace: kube-system
data:
  linear: |-
    {
      "coresPerReplica": 256,
      "nodesPerReplica": 16,
      "min": 2,
      "max": 12
    }
```

### Under-the-Hood Explanation
The cluster-proportional-autoscaler periodically polls the cluster's current node/core count and computes a target replica count for its configured target Deployment using a simple linear formula, updating the Deployment's `spec.replicas` automatically as cluster size changes — replacing what was previously a one-time, manually-chosen static value with a continuously self-adjusting one tied directly to the actual signal (fleet size) that determines the appropriate capacity.

### Common Weak Answer
"Just set the replica count higher this time so we don't have to revisit it again soon."

### Why the Weak Answer Fails
This is the exact same manual, eventually-stale approach that caused the original recurrence — a higher static number only delays the next time it becomes insufficient (or wastes resources in the meantime by over-provisioning for current fleet size); the durable fix removes the dependency on a manually-chosen static value entirely.

### Follow-Up Questions
1. How would you determine the appropriate `coresPerReplica`/`nodesPerReplica` ratio empirically for your specific DNS query-volume characteristics?
2. What other cluster-wide add-ons might benefit from this same proportional-scaling approach?
3. How does this interact with NodeLocal DNSCache (Question 15) — are they complementary or does one reduce the need for the other?

### Key Interview Signals
Recognizes a manually-set, fleet-size-proportional value as a recurring maintenance gap and replaces it with a self-adjusting mechanism rather than simply choosing a new, larger manual value.

### Hands-On Connection
[Lab 2 — Networking and VPC CNI](../labs/lab-02-networking-vpc-cni/) and [Lab 5 — Karpenter Autoscaling](../labs/lab-05-karpenter-autoscaling/).

---

## Question 60: Scheduling for a workload that lies about its needs

### Scenario
A team, frustrated by past OOMKilled incidents, sets a workload's memory *request* far higher than its actual typical usage ("to be safe"), while leaving the memory *limit* unset entirely. A cost review finds this workload's oversized requests are causing significant node under-utilization/over-provisioning cluster-wide, while the missing limit means the pod could still theoretically consume unbounded memory on a node.

### Interview Question
Diagnose both problems this configuration creates and design the correct request/limit strategy.

### Strong Senior-Level Answer
**Initial assessment:** this configuration gets both resource-management levers wrong in different, compounding ways — an oversized *request* reserves far more capacity than actually needed (forcing the scheduler/autoscaler to provision for phantom demand, driving real, unnecessary cost cluster-wide), while a missing *limit* leaves the workload theoretically able to consume unbounded memory on whatever node it lands on, risking exactly the kind of node-level memory pressure that could destabilize *other* workloads sharing that node.

**Technical reasoning:** the scheduler uses a pod's *request* (not its actual usage) to decide which nodes have room for it, and Karpenter/Cluster Autoscaler size new node provisioning based on aggregate pending-pod *requests* — an oversized request directly translates into over-provisioned, wasted capacity regardless of the workload's real usage. Separately, without a *limit*, there's no cgroup-enforced ceiling on this specific container's memory consumption — a memory leak or unexpected spike could consume node-level memory beyond what any *other* workload's own requests assumed would remain available, a genuine noisy-neighbor risk.

**Investigation process:** gather actual observed memory usage data (via `docs/observability.md`'s metrics pipeline) over a representative period, including genuine peak/spike conditions, to determine a real, data-informed request value rather than an arbitrary "to be safe" guess — and separately confirm no limit currently exists via `kubectl describe pod`.

**Recommended solution:** set the memory *request* based on actual observed typical-to-slightly-above-typical usage (informed by real data, not fear-driven padding), and set an explicit memory *limit* with reasonable headroom above the request (covering legitimate peak usage) to actually bound worst-case consumption on the node, preventing this workload from starving others regardless of an unexpected spike or leak.

**Risk controls:** re-introduce the original OOMKilled concern explicitly — if the team's oversized request was a reaction to past OOM incidents, address the *actual* root cause (was the previous limit too low for legitimate peak usage, or was there a genuine memory leak) rather than simply padding the request as an indirect, imprecise workaround; Question 4 in Category 1's OOMKilled diagnosis approach applies directly here.

**Validation steps:** after right-sizing both request and limit based on real data, monitor for both a return of the original OOMKilled symptom (indicating the limit is still too low or a real leak exists) and confirm cluster-wide node utilization improves as the phantom over-provisioning is removed.

**Rollback or recovery strategy:** if the new, right-sized limit reintroduces occasional OOMKills under legitimate peak conditions, this indicates the limit (not the original oversized request) needs adjustment — informed by the same real usage data, not a return to indiscriminate padding.

**Long-term prevention:** establish a data-informed resource-request/limit-sizing practice (using VPA in recommendation-only mode, per Question 53, as one concrete mechanism) as the standard for every workload, rather than either arbitrary padding (this scenario) or no limit at all — treating both request and limit as deliberate, evidence-based values, not guesses in either direction.

### Step-by-Step Implementation
```yaml
resources:
  requests:
    memory: "512Mi"    # informed by actual observed typical usage, not padded "to be safe"
  limits:
    memory: "1Gi"       # explicit ceiling, covering legitimate peak usage with headroom
```

### Under-the-Hood Explanation
Kubernetes uses a pod's resource *requests* purely for scheduling/capacity-accounting decisions (which nodes have room, how much aggregate capacity autoscalers need to provision) — it has no bearing on runtime enforcement. The *limit*, by contrast, is enforced by the kernel's cgroup mechanism at runtime, triggering an OOM kill if the container's actual memory usage exceeds it — these are two entirely separate mechanisms serving different purposes, and getting either one wrong (oversized request, missing limit) produces a distinct, separate problem, exactly as this scenario demonstrates both simultaneously.

### Common Weak Answer
"Since the request is already high, we don't really need a limit too."

### Why the Weak Answer Fails
Request and limit serve entirely different functions — a high request doesn't provide any runtime enforcement ceiling at all; without an explicit limit, this container's actual memory consumption remains genuinely unbounded at runtime, regardless of how generously its request happens to be set for scheduling purposes.

### Follow-Up Questions
1. How would you use VPA in recommendation-only mode to inform correct, data-driven request/limit values for a large fleet of workloads at once?
2. What's the noisy-neighbor risk specifically if this workload shares a node with other, correctly-sized workloads and has no limit set?
3. How would you address the team's original OOMKilled concern at its actual root cause rather than through request padding?

### Key Interview Signals
Clearly distinguishes the scheduling function of requests from the runtime-enforcement function of limits, diagnosing both the cost-inefficiency and the noisy-neighbor risk this configuration creates simultaneously, and traces the padding back to an unaddressed original concern worth revisiting directly.

### Hands-On Connection
[Lab 5 — Karpenter Autoscaling](../labs/lab-05-karpenter-autoscaling/) and [Lab 14 — Troubleshooting and Recovery](../labs/lab-14-troubleshooting-and-recovery/).
