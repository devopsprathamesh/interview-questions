# Category 13: Performance, Scale, and Multi-Tenancy

Questions 111–114 of 120. Category weight: 4 questions. Deep-dive reference: [`docs/node-management-and-autoscaling.md`](../docs/node-management-and-autoscaling.md), [`docs/networking.md`](../docs/networking.md), [`diagrams/15-multi-tenant-isolation-model.md`](../diagrams/15-multi-tenant-isolation-model.md).

---

## Question 111: The cluster that outgrew its own control plane's comfort zone

### Scenario
A cluster grows from 50 to 800 nodes over a year, driven by organic business growth. API server latency for `list`/`watch` operations (used heavily by every controller, including Kubernetes' own core ones) has been steadily increasing, and a few controllers now show visible reconciliation delay.

### Interview Question
Diagnose the scaling pressure and design mitigations.

### Strong Senior-Level Answer
**Initial assessment:** while EKS's control plane is AWS-managed and scales automatically to a significant degree, an 800-node cluster generates a genuinely large volume of API server traffic (from every kubelet, every controller, every `list`/`watch` across every resource type) — even a well-scaled managed control plane has practical limits, and symptoms like this indicate the cluster may be approaching a scale where architectural changes (not just "the control plane will keep scaling transparently forever") become relevant.

**Technical reasoning:** every controller (built-in and custom, including CRD-based operators) that performs broad `list`/`watch` operations across the cluster contributes proportionally to API server load — at large node/pod counts, even efficient, well-written controllers generate substantial aggregate request volume, and a controller with an inefficient watch pattern (e.g., re-listing frequently instead of relying on its informer cache, or watching an overly broad resource scope) compounds this disproportionately.

**Investigation process:** review API server metrics (`apiserver_request_duration_seconds`, request volume by verb/resource) to identify which specific resource types/verbs are generating the most load, and audit custom controllers/operators for inefficient watch/list patterns (not properly using client-go's informer/cache pattern, or watching cluster-wide when a namespaced scope would suffice).

**Recommended solution:** fix any identified inefficient controller patterns first (often the highest-leverage, lowest-risk fix), and consider whether the cluster's actual workload mix genuinely warrants this single-cluster scale versus splitting into multiple, smaller clusters (per the companion Terraform/Ansible repositories' guidance on splitting an overly-large single unit of management once it exceeds practical operational limits) — 800 nodes in one cluster is workable but is approaching a scale where many organizations begin considering a multi-cluster architecture for both blast-radius and control-plane-load reasons.

**Risk controls:** before considering a disruptive cluster-split, exhaust the lower-risk mitigations first (controller efficiency fixes, ensuring `etcd` and API server resource requests/limits if any self-managed component competes for control-plane-adjacent resources) — a cluster split is a substantial architectural change that should be a considered decision, not a first response.

**Validation steps:** after controller-efficiency fixes, confirm API server latency trends improve measurably, and if a cluster-split is eventually pursued, confirm the resulting smaller clusters show meaningfully better control-plane responsiveness.

**Rollback or recovery strategy:** controller-level fixes are generally low-risk and don't require rollback consideration; a cluster split, if pursued, would follow its own careful, staged migration process (well beyond a simple configuration change).

**Long-term prevention:** treat API server request-volume/latency as a standing, monitored signal (per [`docs/observability.md`](../docs/observability.md)) as the cluster continues to grow, and periodically audit custom controllers for watch/list efficiency as part of the standard operational review, catching inefficiencies before they compound at ever-larger scale.

### Step-by-Step Implementation
```promql
# Identify the highest-load resource types/verbs on the API server
topk(10, sum by (resource, verb) (rate(apiserver_request_total[5m])))
```

### Under-the-Hood Explanation
Kubernetes' controller pattern relies on informers maintaining a local, watch-fed cache of relevant resources, minimizing redundant API server calls — a controller that bypasses this pattern (polling via repeated `list` calls instead of a properly-configured `watch`-backed informer) generates dramatically more API server load than necessary, and at large node/pod counts, this inefficiency compounds into measurable, cluster-wide latency impact for every other consumer of the same API server.

### Common Weak Answer
"Just ask AWS to scale up the control plane more."

### Why the Weak Answer Fails
EKS's control plane scaling is largely automatic and not something a customer can directly request scaling adjustments for in the way this answer implies — the actual, actionable levers are controller efficiency and, at sufficient scale, cluster architecture (splitting), not requesting manual intervention on AWS's managed infrastructure.

### Follow-Up Questions
1. How would you audit every custom controller/operator in the cluster for informer-based versus inefficient polling-based patterns?
2. What are the practical signals indicating a cluster has genuinely outgrown a single-cluster architecture, beyond just node count?
3. How would you plan a cluster-split migration if that's eventually determined to be the right long-term answer?

### Key Interview Signals
Identifies controller-level inefficiency as the first, lower-risk investigation target before considering a more disruptive cluster-split, and recognizes EKS's managed control-plane scaling has practical limits worth monitoring for proactively.

### Hands-On Connection
[Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).

---

## Question 112: The namespace quota that quietly capped growth

### Scenario
A rapidly-growing team's workloads start failing to schedule new pods with `exceeded quota` errors, despite the cluster having ample overall capacity. The team's `ResourceQuota`, set a year ago when the team was much smaller, was never revisited.

### Interview Question
Diagnose this and design a process preventing recurrence.

### Strong Senior-Level Answer
**Initial assessment:** a `ResourceQuota` set once and never revisited is exactly the same "static value that should scale with something else" gap as the manually-set CoreDNS replica count (Question 59) — here applied to a namespace's resource ceiling relative to a growing team's actual, evolving needs, rather than fleet size relative to a shared add-on.

**Technical reasoning:** `ResourceQuota` enforces a hard ceiling on aggregate resource consumption (CPU/memory requests, object counts) within a namespace, entirely independent of overall cluster capacity — a team can be blocked by their own quota even while the broader cluster has abundant unused capacity elsewhere, exactly the scenario described, since quota enforcement doesn't consider cluster-wide availability at all.

**Investigation process:** confirm via `kubectl describe resourcequota -n <namespace>` that the team is indeed at or near their quota's ceiling, and confirm (via cluster-wide capacity metrics) that overall cluster capacity is genuinely not the actual constraint — settling that this is a namespace-quota-sizing issue, not a genuine cluster-capacity shortage.

**Recommended solution:** review and adjust the team's `ResourceQuota` to reflect their actual current, legitimate needs (informed by real usage data and reasonable growth headroom, not just raising it arbitrarily), and establish a periodic (e.g., quarterly) quota-review process for every namespace, similar in spirit to the CoreDNS proportional-scaling fix but requiring human review here (since a team's legitimate resource needs, unlike CoreDNS's fleet-proportional load, isn't a purely mechanical function of an easily-measured input).

**Risk controls:** ResourceQuota exists specifically to prevent one team from consuming disproportionate shared cluster capacity — raising it should still be a deliberate, reviewed decision (not an unlimited removal of the constraint entirely), balancing this team's legitimate growth against fair, sustainable multi-tenant resource allocation.

**Validation steps:** after adjusting, confirm the team's pods schedule successfully, and confirm the new quota still provides meaningful protection against runaway consumption (not simply set so high it's effectively no constraint at all).

**Rollback or recovery strategy:** if the new quota proves insufficient again sooner than expected (faster growth than anticipated), that's itself useful information for calibrating the next periodic review's headroom assumptions.

**Long-term prevention:** institutionalize periodic ResourceQuota review across every namespace as a standing platform-operations practice, explicitly tied to team growth/usage trends (via the observability pipeline) rather than a "set once at namespace creation and never revisited" default — the same underlying lesson as Question 59, applied to a human-reviewed rather than fully-automated scaling context.

### Step-by-Step Implementation
```bash
kubectl describe resourcequota -n growing-team
```
```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: growing-team-quota
  namespace: growing-team
spec:
  hard:
    requests.cpu: "200"      # revised upward, informed by actual usage trend + headroom
    requests.memory: 400Gi
    pods: "150"
```

### Under-the-Hood Explanation
`ResourceQuota` enforcement happens at admission time, purely by summing the namespace's current resource consumption against the configured hard limits — it has no awareness of overall cluster capacity or any external signal about "how much this team has grown"; it simply enforces whatever static ceiling was configured, indefinitely, until a human explicitly reviews and adjusts it.

### Common Weak Answer
"Just remove the ResourceQuota entirely to unblock the team."

### Why the Weak Answer Fails
This eliminates the fair-sharing/runaway-consumption protection ResourceQuota provides for the entire shared cluster, not just fixing this one team's immediate need — a deliberately-recalibrated quota (informed by actual data) preserves the protective purpose while unblocking legitimate growth.

### Follow-Up Questions
1. How would you design a periodic quota-review process that scales across many namespaces without becoming its own significant manual burden?
2. What's the risk of setting a quota too generously "to avoid this happening again" without careful sizing?
3. How would you use actual observed usage trends to inform quota headroom for a genuinely fast-growing team?

### Key Interview Signals
Recognizes a static ResourceQuota as the same class of "should scale with something, but doesn't automatically" gap seen elsewhere in this repository series, and designs a periodic, data-informed review process rather than either ignoring the quota's purpose or leaving it permanently stale.

### Hands-On Connection
[Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).

---

## Question 113: The tenant that was too loud for the room

### Scenario
On the shared multi-tenant cluster (per [`diagrams/15-multi-tenant-isolation-model.md`](../diagrams/15-multi-tenant-isolation-model.md)), one team's workload experiences a sudden traffic spike, consuming its full `ResourceQuota` allocation and causing its own pods to be evicted/throttled — but unrelated teams sharing the same underlying nodes (not dedicated node pools) also experience noticeable performance degradation during this same window.

### Interview Question
Diagnose why namespace-level quota isolation didn't fully protect other tenants, and design a more complete isolation model.

### Strong Senior-Level Answer
**Initial assessment:** per [`diagrams/15-multi-tenant-isolation-model.md`](../diagrams/15-multi-tenant-isolation-model.md)'s explicit callout, `ResourceQuota`/RBAC/NetworkPolicy provide namespace-level isolation, but without dedicated node pools per tenant, workloads from different namespaces can still share the same underlying physical nodes — meaning one tenant's traffic spike, even while correctly bounded by its own quota, can still cause node-level resource contention (CPU throttling, memory pressure) affecting co-located pods from entirely different tenants.

**Technical reasoning:** `ResourceQuota` bounds the *aggregate requests* a namespace can declare, but actual runtime resource *usage* (especially CPU, which is compressible and can be throttled rather than hard-limited the way memory is) can still burst up to a pod's configured *limit* — if many of one tenant's pods burst simultaneously, and they share nodes with another tenant's pods, the node's actual CPU contention can degrade the other tenant's performance even though neither tenant technically exceeded their own namespace's quota.

**Investigation process:** confirm via node-level CPU/memory metrics during the incident window that the affected nodes were indeed shared between the spiking tenant and the affected, unrelated tenants — settling that this is a node-sharing contention issue, not something namespace-level quota alone could have prevented.

**Recommended solution:** for genuinely noisy-neighbor-sensitive tenants (or tenants with unpredictable traffic patterns), introduce dedicated node pools via taints/tolerations (per [`diagrams/15-multi-tenant-isolation-model.md`](../diagrams/15-multi-tenant-isolation-model.md)'s explicit recommendation) — isolating not just the namespace's logical resource allocation but the actual physical compute those pods run on, so one tenant's burst can't contend with another's node-level resources at all.

**Risk controls:** dedicated node pools per tenant increase cost (less efficient bin-packing across a shared, larger pool) — this should be a deliberate trade-off applied where genuinely warranted (tenants with variable/unpredictable load, or genuinely high isolation requirements), not a blanket default for every tenant regardless of actual risk.

**Validation steps:** after introducing dedicated node pools for the affected tenants, replay a similar traffic-spike scenario (in a controlled test) and confirm other tenants sharing the platform are no longer measurably affected.

**Rollback or recovery strategy:** node-pool dedication can be selectively rolled back for tenants where the cost/isolation trade-off doesn't prove worthwhile in practice, informed by real operational experience.

**Long-term prevention:** establish clear criteria for which tenants warrant dedicated node pools (variable load patterns, high isolation/compliance requirements) versus which are fine sharing a common pool, and revisit this classification periodically as tenants' actual usage patterns evolve.

### Step-by-Step Implementation
```yaml
# Dedicated node pool for a noisy-neighbor-sensitive tenant
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: tenant-a-dedicated
spec:
  template:
    spec:
      taints:
        - key: tenant
          value: tenant-a
          effect: NoSchedule
---
# Tenant A's workloads tolerate the taint, isolating them onto dedicated nodes
tolerations:
  - key: tenant
    operator: Equal
    value: tenant-a
    effect: NoSchedule
```

### Under-the-Hood Explanation
CPU is a compressible resource — the kernel's CFS scheduler throttles a container exceeding its CPU limit rather than terminating it (unlike memory, where exceeding a limit triggers an OOM kill) — meaning multiple co-located pods bursting toward their individual limits simultaneously genuinely compete for the node's actual, finite CPU cycles at the kernel level, a contention dynamic that `ResourceQuota`'s namespace-level *request* accounting doesn't directly prevent, since quota governs aggregate declared requests, not actual, simultaneous runtime usage bursts across co-located tenants.

### Common Weak Answer
"ResourceQuota isolates tenants, so this shouldn't be possible — check for a Kubernetes bug."

### Why the Weak Answer Fails
`ResourceQuota` provides namespace-level *logical* resource-allocation isolation, but explicitly does not provide node-level *physical* isolation unless combined with dedicated node pools — this is a well-understood, documented limitation of namespace-only multi-tenancy, not a bug, exactly as called out in this repository's own multi-tenant isolation model documentation.

### Follow-Up Questions
1. How would you decide the cost/isolation trade-off threshold for which tenants warrant dedicated node pools?
2. What's the difference in this contention risk between CPU (compressible, throttled) and memory (incompressible, OOM-killed) resource types?
3. How would you monitor for cross-tenant node contention proactively, rather than discovering it reactively during an actual incident?

### Key Interview Signals
Correctly distinguishes namespace-level logical isolation from node-level physical isolation, recognizing dedicated node pools (not just ResourceQuota) as the actual mechanism needed for genuine noisy-neighbor protection.

### Hands-On Connection
[Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).

---

## Question 114: The cost allocation nobody could untangle

### Scenario
Finance asks the platform team to break down EKS cost by team/business-unit for chargeback purposes. The team discovers this is nearly impossible with current tagging — shared node pools mix multiple teams' pods, and node-level costs (EC2, EBS) aren't easily attributable to the specific namespace/team whose pods happen to be running on a given node at any moment.

### Interview Question
Design an approach to accurate, granular cost allocation for a shared, multi-tenant EKS platform.

### Strong Senior-Level Answer
**Initial assessment:** accurate per-team cost allocation on a shared cluster is a genuinely non-trivial problem when teams share underlying node pools — node-level costs (EC2 instance cost, EBS volumes) don't have a natural, built-in per-namespace attribution the way, say, a per-team dedicated AWS account's costs would via Cost Explorer's account-level breakdown.

**Technical reasoning:** the standard solution is a Kubernetes cost-allocation tool (like **Kubecost**, or the open-source OpenCost project it's built on) that correlates actual pod-level resource *usage* (or requests, depending on the allocation methodology chosen) against underlying node costs, proportionally attributing shared node costs to the specific namespaces/pods that consumed them — solving exactly the "shared node pool" attribution problem that raw AWS billing/tagging alone can't address, since AWS's own cost tools have no visibility into what's happening *inside* a given EC2 instance at the Kubernetes-pod level.

**Investigation process:** confirm the current tagging strategy's actual limitation (tags applied at the node/instance level don't capture the fact that multiple teams' pods share that same instance) — this settles why simple AWS-tag-based cost allocation can't solve this specific multi-tenant scenario.

**Recommended solution:** deploy Kubecost/OpenCost, configured to correlate actual namespace-level resource requests/usage against the underlying node costs (via the AWS Cost and Usage Report, ingested and reconciled against Kubernetes-level consumption data) — providing genuine, defensible per-team cost allocation even on fully-shared node pools, without requiring a costly move to fully-dedicated per-team infrastructure just to achieve cost visibility.

**Risk controls:** be explicit with finance about the allocation *methodology* chosen (e.g., cost allocated proportional to resource *requests* versus actual *usage* — these can differ meaningfully, and the choice affects how "fair" the resulting chargeback feels to teams with different request-vs-usage efficiency) — this methodology choice should be a deliberate, documented, and communicated decision, not an unstated default.

**Validation steps:** cross-check the tool's aggregate cost allocation across all teams against the actual total AWS bill for the cluster, confirming the sum of all per-team allocations reconciles correctly to the real total spend, building confidence in the tool's accuracy before relying on it for actual chargeback decisions.

**Rollback or recovery strategy:** not applicable — this is an additive cost-visibility capability.

**Long-term prevention:** treat granular, defensible cost allocation as a standing platform capability (not a one-off finance request to satisfy once) — maintaining Kubecost/OpenCost's ongoing accuracy as new teams/workloads onboard, and periodically revisiting the allocation methodology's fairness as the platform's tenant mix evolves.

### Step-by-Step Implementation
```bash
helm install kubecost cost-analyzer --repo https://kubecost.github.io/cost-analyzer/ \
  --namespace kubecost --create-namespace \
  --set kubecostToken="..." \
  --set global.cloudCost.enabled=true   # reconciles against actual AWS Cost and Usage Report data
```

### Under-the-Hood Explanation
Kubecost/OpenCost ingests both Kubernetes-level resource-consumption data (via `metrics-server`/Prometheus, tracking per-pod actual usage and requests) and AWS's own Cost and Usage Report (the authoritative source for actual EC2/EBS/etc. spend), then computes a proportional allocation of each node's real, billed cost across the pods that ran on it during the relevant billing period — solving the shared-node attribution problem by correlating two data sources (Kubernetes consumption and AWS billing) that neither alone can fully answer this question with.

### Common Weak Answer
"Just tag every node with the team that uses it most and allocate cost that way."

### Why the Weak Answer Fails
This is a crude approximation that breaks down precisely in the shared-node-pool scenario described — a node running multiple teams' pods has no single "team that uses it most" in any precise, defensible sense, and this approach would misattribute cost in exactly the situations that actually need careful, proportional allocation the most.

### Follow-Up Questions
1. How would you decide between requests-based and usage-based cost-allocation methodology, and communicate that trade-off to finance/teams?
2. How would you validate Kubecost/OpenCost's allocation accuracy against the actual total AWS bill on an ongoing basis?
3. How would you handle genuinely shared infrastructure costs (like the observability stack itself) that don't belong to any single team?

### Key Interview Signals
Recognizes that shared-node-pool cost allocation is a genuinely hard problem requiring purpose-built tooling (Kubecost/OpenCost) correlating Kubernetes-level and AWS-billing-level data, rather than a crude tagging approximation that doesn't actually solve the attribution problem.

### Hands-On Connection
[Lab 15 — Enterprise Capstone](../labs/lab-15-enterprise-capstone/).
