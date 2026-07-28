# Category 2: Networking (VPC CNI, Security Groups, Load Balancers)

Questions 11–22 of 120. Category weight: 12 questions. Deep-dive reference: [`docs/networking.md`](../docs/networking.md).

---

## Question 11: The subnet that ran out of room

### Scenario
A cluster's node subnets are sized at `/24` (256 addresses) each. As the fleet grows, new nodes intermittently fail to join with `InsufficientCidrBlocks`-style errors, even though the node group's desired capacity hasn't changed dramatically — the actual constraint turns out to be IP exhaustion at the subnet level, not the ENI/IP-per-node level from Question in category 1's neighboring topics.

### Interview Question
Diagnose the subnet-level IP exhaustion and design the fix, distinguishing it from per-node ENI/IP limits.

### Strong Senior-Level Answer
**Initial assessment:** because every pod consumes a real, routable IP from the VPC CIDR (per [`docs/networking.md`](../docs/networking.md) §1), subnet sizing must account for the full expected pod count across every node that could ever run in that subnet, not just node count — a `/24` subnet with heavy pod density per node can exhaust its 256 addresses far sooner than intuition based on "node count" alone would suggest.

**Technical reasoning:** each node pre-allocates a "warm pool" of IPs (per `ipamd`'s warm targets) from the subnet, on top of what's actually in active use by running pods — meaning the *effective* consumption rate per node is higher than "actual running pod count," compounding subnet exhaustion faster than a naive calculation would predict.

**Investigation process:** confirm via VPC subnet available-IP-count metrics (or `aws ec2 describe-subnets`) exactly how close to exhaustion the subnet is, and correlate the timing of `InsufficientCidrBlocks`-style errors with subnet IP availability crossing a critical threshold.

**Recommended solution:** either resize/re-architect subnets with more headroom (a larger CIDR block, requiring subnet re-creation and node migration — disruptive), or adopt **custom networking** (`ENIConfig` + a dedicated, larger secondary CIDR like `100.64.0.0/16` for pod IPs specifically, separate from the primary node/VPC CIDR) — the standard, less-disruptive fix for organizations that under-sized their original VPC CIDR and can't easily expand primary subnets.

**Risk controls:** any subnet resizing or custom-networking migration is itself a significant networking change — stage it in a non-production cluster first, and plan for the node-replacement disruption custom networking's `ENIConfig` rollout requires (nodes need to be replaced to pick up the new pod-IP configuration).

**Validation steps:** after remediation, confirm subnet IP headroom is comfortably above projected peak fleet size (including autoscaler burst capacity, not just steady-state), and confirm no further `InsufficientCidrBlocks` errors occur under a deliberate scale-out test.

**Rollback or recovery strategy:** custom networking rollout can be reverted by returning to standard (non-custom) networking configuration, though this again requires node replacement to take effect.

**Long-term prevention:** size subnets (or plan for custom networking from the start) based on projected peak pod count, not projected node count — bake this into the companion Terraform repository's EKS VPC module as an explicit sizing calculation, not a default guess.

### Step-by-Step Implementation
```yaml
# ENIConfig - custom networking, separate CIDR for pod IPs
apiVersion: crd.k8s.amazonaws.com/v1alpha1
kind: ENIConfig
metadata:
  name: us-east-1a
spec:
  subnet: subnet-0123456789abcdef0   # a larger, dedicated pod-IP subnet e.g. from 100.64.0.0/16
  securityGroups:
    - sg-0123456789abcdef0
```
```bash
kubectl set env daemonset aws-node -n kube-system AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG=true
kubectl set env daemonset aws-node -n kube-system ENI_CONFIG_LABEL_DEF=topology.kubernetes.io/zone
```

### Under-the-Hood Explanation
Custom networking decouples the CIDR pods draw IPs from (via `ENIConfig`'s referenced subnet) from the primary VPC/node CIDR — allowing a much larger, purpose-built secondary CIDR (like the `100.64.0.0/16` CGNAT range, commonly used since it doesn't need to fit within the primary VPC's own address planning) to absorb pod-IP demand without requiring the primary VPC CIDR itself to be resized.

### Common Weak Answer
"Just add more nodes to smaller subnets in other AZs."

### Why the Weak Answer Fails
This doesn't address the root sizing problem, only redistributes it — every additional subnet still faces the same per-node pod-IP consumption math, and doesn't fix the underlying under-provisioned CIDR allocation strategy.

### Follow-Up Questions
1. How does custom networking's dedicated pod-IP CIDR interact with security group and NACL design for pod-to-pod traffic?
2. What's the migration disruption cost of adopting custom networking on an already-running production cluster?
3. How would you monitor subnet IP headroom proactively, before it becomes a node-join failure?

### Key Interview Signals
Distinguishes subnet-level IP exhaustion from per-node ENI/IP limits, and reaches for custom networking as the standard, purpose-built fix rather than an ad hoc subnet-juggling workaround.

### Hands-On Connection
[Lab 2 — Networking and VPC CNI](../labs/lab-02-networking-vpc-cni/).

---

## Question 12: The health check that lied

### Scenario
An ALB Ingress is configured with target type `instance`. Target-group health checks consistently show all targets healthy, yet a subset of user requests intermittently fail with connection errors. Investigation shows the failing requests were routed to a node whose specific pod had actually crashed minutes earlier — the node itself (and therefore the NodePort) was still healthy.

### Interview Question
Diagnose why the health check didn't catch this, and fix the underlying architecture.

### Strong Senior-Level Answer
**Initial assessment:** this is exactly the `instance` vs. `ip` target-type gap from [`docs/networking.md`](../docs/networking.md) §6 — in `instance` mode, health checks verify the *node's* NodePort is reachable, which stays healthy as long as *any* pod behind that NodePort/Service is up, not specifically the pod actually receiving a given request; the health check has no visibility into per-pod health at all.

**Technical reasoning:** `instance` mode routes to a node's NodePort, with kube-proxy then load-balancing across whichever pods currently match the Service's selector on that node — if a specific pod crashed but kube-proxy hasn't yet removed it from rotation (or another pod handles the NodePort fine while a different one is actually broken), the target-group health check (which only checks NodePort reachability, not pod-level health) has no way to detect or route around the specific failing pod.

**Investigation process:** confirm via target-group health-check configuration (`instance` vs. `ip` mode) and cross-reference the timing of the crashed pod against the failing requests — this settles that the health check's blind spot (pod-level failures under `instance` mode) is the actual cause, not a genuine load-balancer misconfiguration.

**Recommended solution:** switch the Ingress/target-group configuration to `ip` mode (per [`docs/networking.md`](../docs/networking.md) §6) — routing directly to pod IPs with pod-level health checks, so a crashed pod is immediately and accurately reflected as an unhealthy target, removed from rotation without depending on kube-proxy's own, separate failure-detection timing.

**Risk controls:** switching target-type modes requires the AWS Load Balancer Controller to recreate the target group — plan this as a brief, controlled change with monitoring for any transient disruption during the cutover, rather than assuming it's instantaneous and risk-free.

**Validation steps:** after switching to `ip` mode, deliberately crash a test pod and confirm the target group correctly and promptly marks it unhealthy, removing it from rotation without affecting requests routed to healthy pods.

**Rollback or recovery strategy:** revert the target-type annotation if the cutover reveals an unexpected issue — the AWS Load Balancer Controller will recreate the target group in the previous mode.

**Long-term prevention:** establish `ip` target-type mode as the default recommendation for all VPC-CNI-based clusters in the organization's Ingress manifests/Helm chart defaults, reserving `instance` mode only for the rare case of a non-VPC-CNI CNI plugin that doesn't support `ip` mode.

### Step-by-Step Implementation
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  annotations:
    alb.ingress.kubernetes.io/target-type: ip   # pod-level health checks, not node-level
    alb.ingress.kubernetes.io/scheme: internet-facing
spec:
  # ... rules
```

### Under-the-Hood Explanation
In `ip` mode, the AWS Load Balancer Controller registers each pod's actual VPC IP directly as a target-group target, and the target group's own health check (HTTP/HTTPS/TCP, configurable) hits that specific pod IP — giving health-check results that precisely reflect that individual pod's real health, unlike `instance` mode's NodePort-level check which is several layers removed from any individual pod's actual state.

### Common Weak Answer
"The health check is probably misconfigured, just adjust the interval/threshold."

### Why the Weak Answer Fails
Tuning health-check timing parameters doesn't fix the structural blind spot — `instance` mode fundamentally cannot see per-pod health regardless of how the check interval/threshold is tuned; the fix is the target-type mode itself, not its timing parameters.

### Follow-Up Questions
1. What's the operational cost of switching target-type mode on a live, high-traffic production Ingress?
2. How does `ip` mode interact with Security Groups for Pods, if pods have dedicated security groups?
3. How would you have caught this gap before it caused user-facing failures, via testing or review?

### Key Interview Signals
Identifies the specific structural blind spot in `instance`-mode health checks rather than assuming a generic health-check misconfiguration, and proposes the architecturally correct fix.

### Hands-On Connection
[Lab 7 — Ingress and Load Balancing](../labs/lab-07-ingress-and-load-balancing/).

---

## Question 13: The pod that needed its own front door

### Scenario
A single node runs both a PCI-scope payment-processing pod and several unrelated internal tooling pods. Security policy requires the payment pod's network access be tightly restricted at the AWS security-group layer, but all pods on the node currently share the node's one security group.

### Interview Question
Design a solution enforcing pod-specific security-group rules without moving the payment workload to a dedicated node.

### Strong Senior-Level Answer
**Initial assessment:** this is precisely the problem **Security Groups for Pods** solves (per [`docs/networking.md`](../docs/networking.md) §4) — by default, all pods on a node inherit that node's shared security group, with no pod-level distinction; Security Groups for Pods gives specific, labeled pods their own dedicated ENI and security group, independent of whatever else shares the node.

**Technical reasoning:** the `amazon-vpc-resource-controller` (running as part of the VPC CNI's broader capability set) watches `SecurityGroupPolicy` custom resources matching pods by label/service-account, provisioning a dedicated branch ENI with the specified security group(s) for matched pods specifically — while unmatched pods on the same node continue using the node's shared security group unaffected.

**Investigation process:** confirm the specific security-group rules the payment workload actually requires (informed by the PCI-scope requirements) and identify a stable label/service-account selector uniquely matching only the payment pod(s), not accidentally matching any other workload on the node.

**Recommended solution:** define a `SecurityGroupPolicy` matching the payment pod's label, referencing a dedicated, tightly-scoped security group — achieving pod-level network isolation without requiring node-level separation (a dedicated node group), which would be a heavier, less efficient isolation mechanism for this specific requirement.

**Risk controls:** verify the node's instance type supports the additional branch ENI capacity Security Groups for Pods requires (a real, instance-type-dependent limit, distinct from the standard ENI/IP limits) — some smaller instance types have limited or no branch-ENI capacity.

**Validation steps:** after applying the `SecurityGroupPolicy`, confirm via VPC Flow Logs (or a direct connectivity test) that the payment pod's traffic is genuinely constrained to the new security group's rules, and that other pods on the same node are unaffected.

**Rollback or recovery strategy:** removing the `SecurityGroupPolicy` reverts matched pods to the node's shared security group on their next scheduling — a low-risk, easily reversible change.

**Long-term prevention:** treat Security Groups for Pods as the standard tool for any workload requiring network isolation stricter than its node's shared security group, avoiding the more expensive/heavier alternative of dedicating entire nodes purely for network-isolation reasons when co-location is otherwise fine.

### Step-by-Step Implementation
```yaml
apiVersion: vpcresources.k8s.aws/v1beta1
kind: SecurityGroupPolicy
metadata:
  name: payment-pod-policy
  namespace: payments
spec:
  podSelector:
    matchLabels:
      app: payment-processor
  securityGroups:
    groupIds:
      - sg-0123456789abcdef0   # tightly-scoped PCI-compliant security group
```

### Under-the-Hood Explanation
Security Groups for Pods provisions a "branch" ENI (technically, a trunk-ENI-and-branch-ENI model where multiple pods' branch interfaces share one physical trunk ENI on the node) specifically for matched pods, with that branch interface's traffic subject to the specified security group's rules independently of the node's own primary ENI/security group — giving genuine AWS-security-group-level pod isolation without requiring a fully separate node.

### Common Weak Answer
"Just move the payment pod to its own dedicated node with its own security group."

### Why the Weak Answer Fails
This works but is a heavier-handed, less efficient solution than necessary — it dedicates an entire node (and its unused remaining capacity) purely to achieve network isolation that Security Groups for Pods provides at the pod level, without requiring node-level separation at all.

### Follow-Up Questions
1. What's the instance-type-specific branch-ENI capacity limit, and how would you plan around it at scale?
2. How does Security Groups for Pods interact with NetworkPolicy — are they complementary or redundant?
3. How would you validate that this isolation is actually effective, not just configured?

### Key Interview Signals
Reaches for the pod-granular tool (Security Groups for Pods) matched to the actual requirement, rather than defaulting to a heavier node-level isolation solution.

### Hands-On Connection
[Lab 2 — Networking and VPC CNI](../labs/lab-02-networking-vpc-cni/).

---

## Question 14: The NetworkPolicy that did nothing

### Scenario
A team applies a strict default-deny `NetworkPolicy` to a sensitive namespace, confirms via `kubectl get networkpolicy` that it exists, and considers the namespace isolated. A penetration test later shows unrestricted cross-namespace traffic still reaching the "isolated" namespace's pods.

### Interview Question
Explain why the NetworkPolicy had no effect, and how you'd verify enforcement going forward.

### Strong Senior-Level Answer
**Initial assessment:** a `NetworkPolicy` object existing in the API is not the same as it being enforced — per [`docs/networking.md`](../docs/networking.md) §7, enforcement requires an active CNI capability (native VPC CNI `ENABLE_NETWORK_POLICY=true`, or a separate plugin like Calico); without it, `NetworkPolicy` objects are silently inert, with no error or warning anywhere indicating the gap.

**Technical reasoning:** `kubectl get networkpolicy` only confirms the object is *stored* in the API — it says nothing about whether anything is actually *watching and enforcing* it at the network-datapath level, which is a property of the CNI configuration, entirely separate from the Kubernetes API object's own existence.

**Investigation process:** confirm the cluster's actual CNI configuration — check whether `ENABLE_NETWORK_POLICY` is set on the VPC CNI, or whether Calico (or another policy-enforcing CNI addition) is installed and running — this is the single, definitive check that would have caught this gap before the penetration test did.

**Recommended solution:** enable native VPC CNI network-policy enforcement (or install Calico if using an older VPC CNI version without native support), then re-verify the existing `NetworkPolicy` objects are now actually enforced.

**Risk controls:** enabling policy enforcement on a cluster that has never had it active can itself cause unexpected traffic blocking for any legitimate traffic pattern not covered by existing (previously-inert) policies — roll out in a non-production cluster first, or start with permissive/audit-capable policies before tightening, to avoid an enforcement-enablement outage.

**Validation steps:** the only real validation is an actual test — attempt a connection that the policy should block and confirm it's actually rejected (exactly what the penetration test did, which is why it caught this) — never trust policy object existence alone as proof of enforcement.

**Rollback or recovery strategy:** if enabling enforcement breaks legitimate traffic, disable it while auditing which specific policies need adjustment, then re-enable once corrected.

**Long-term prevention:** make "is NetworkPolicy enforcement actually active" a standing item in cluster security baselining (ideally automated, checked at cluster provisioning time and periodically thereafter) — never assume it based on policy object presence alone.

### Step-by-Step Implementation
```bash
# Check native VPC CNI policy enforcement status
kubectl get daemonset aws-node -n kube-system -o jsonpath='{.spec.template.spec.containers[0].env}' | grep -i network_policy

# If not enabled, enable it (requires a compatible VPC CNI version)
kubectl set env daemonset aws-node -n kube-system ENABLE_NETWORK_POLICY=true
```
```bash
# Real validation - a positive control test
kubectl run test-pod --image=busybox --rm -it --restart=Never -n other-namespace -- \
  wget -qO- --timeout=2 http://target-service.sensitive-namespace.svc.cluster.local
# Should be REJECTED after the fix, not just "the policy object exists"
```

### Under-the-Hood Explanation
A `NetworkPolicy` object is purely declarative — Kubernetes' API server stores it, but has no built-in network-enforcement mechanism of its own; enforcement is delegated entirely to whatever CNI plugin is configured to watch and act on these objects. A cluster with no enforcing capability accepts and stores `NetworkPolicy` objects exactly as if they were meaningful, with zero indication anywhere that they're not actually doing anything.

### Common Weak Answer
"The NetworkPolicy exists and looks correct, so the namespace should be isolated."

### Why the Weak Answer Fails
This is the exact assumption that led to the failed penetration test — confirming a policy object's existence and correctness says nothing about whether it's actually enforced, and this gap has no visible symptom until something actively tests the isolation boundary.

### Follow-Up Questions
1. How would you build an automated, standing test that continuously verifies NetworkPolicy enforcement rather than relying on periodic manual penetration tests?
2. What's the trade-off between native VPC CNI policy enforcement and Calico for a cluster not currently using either?
3. How would you safely roll out enforcement on a cluster that's never had it active, given the risk of breaking untested legitimate traffic?

### Key Interview Signals
Distinguishes a policy object's existence from actual enforcement, and insists on positive-control testing (attempting a connection that should be blocked) rather than trusting configuration review alone.

### Hands-On Connection
[Lab 2 — Networking and VPC CNI](../labs/lab-02-networking-vpc-cni/) and [Lab 8 — Security Hardening](../labs/lab-08-security-hardening/).

---

## Question 15: The DNS resolver that couldn't keep up

### Scenario
At roughly 400 nodes and several thousand pods, application teams begin reporting intermittent DNS resolution failures/timeouts under load, especially during traffic spikes. CoreDNS's own pods show high CPU utilization and occasional restarts during these windows.

### Interview Question
Diagnose the bottleneck and design the fix at this scale.

### Strong Senior-Level Answer
**Initial assessment:** this is the central-bottleneck-under-fleet-wide-load pattern named in [`docs/networking.md`](../docs/networking.md) §8 — CoreDNS's default replica count (commonly just 2) serves the *entire* cluster's DNS query volume, and at this fleet size, aggregate query volume during traffic spikes can exceed what a small, centrally-located CoreDNS deployment can handle, causing both elevated latency and the observed CPU pressure/restarts.

**Technical reasoning:** every pod's DNS query (for service discovery, external hostname resolution) round-trips to CoreDNS over the network — there's no local caching by default, meaning even highly repetitive, cacheable queries (the same few service names looked up constantly) still hit the central CoreDNS deployment every single time.

**Investigation process:** confirm via CoreDNS's own metrics (`coredns_dns_requests_total`, request latency histograms) that query volume/latency indeed correlates with the reported failure windows, and confirm CoreDNS's current replica count/resource requests against the actual fleet size — this settles whether it's genuinely a capacity/architecture problem versus a possible misconfiguration (e.g., an application performing excessive redundant lookups).

**Recommended solution:** deploy **NodeLocal DNSCache** (a DaemonSet running a local caching DNS resolver on every node) — pods query the local node's cache first, which only forwards genuinely uncached/expired queries to the central CoreDNS deployment, dramatically reducing the load reaching CoreDNS itself. Additionally, increase CoreDNS's own replica count and consider the cluster-proportional autoscaler for CoreDNS (scaling its replica count with cluster size automatically) as a complementary, not alternative, fix.

**Risk controls:** NodeLocal DNSCache changes each node's DNS resolution path — roll out to a subset of nodes first (if feasible) or a non-production cluster, verifying no application depends on some CoreDNS-specific behavor NodeLocal DNSCache's caching might subtly change (e.g., very short-TTL-dependent behavior).

**Validation steps:** after rollout, confirm DNS query latency and CoreDNS's own CPU/restart metrics both improve significantly under a repeated load test matching the original failure conditions.

**Rollback or recovery strategy:** NodeLocal DNSCache can be removed (reverting pods to querying CoreDNS directly) if it introduces any unexpected issue — a contained, per-node change.

**Long-term prevention:** treat CoreDNS capacity (replica count, NodeLocal DNSCache presence) as a fleet-size-proportional scaling concern reviewed periodically as the cluster grows, not a fixed, set-once-at-cluster-creation configuration.

### Step-by-Step Implementation
```bash
# Install NodeLocal DNSCache (typically via the official manifest, templated for your cluster's DNS service IP)
kubectl apply -f nodelocaldns.yaml

# Increase CoreDNS replica count as a complementary fix
kubectl scale deployment coredns -n kube-system --replicas=6
```

### Under-the-Hood Explanation
NodeLocal DNSCache runs as a DaemonSet, intercepting DNS queries via a link-local IP on each node and serving from a local cache when possible — dramatically cutting the query volume that actually reaches the cluster's shared CoreDNS deployment, since repeated/cacheable lookups (the vast majority of typical service-discovery traffic) are now resolved locally on-node rather than round-tripping to CoreDNS every time.

### Common Weak Answer
"Just restart CoreDNS when it has trouble."

### Why the Weak Answer Fails
Restarting CoreDNS is a reactive, temporary relief (briefly resetting resource usage) that doesn't address the actual root cause — aggregate query volume exceeding a small, centrally-located deployment's capacity — and the same failure will recur at the next comparable traffic spike.

### Follow-Up Questions
1. How would you monitor CoreDNS capacity proactively as the cluster continues to grow, rather than discovering the bottleneck reactively?
2. What's the interaction between NodeLocal DNSCache and very short-TTL DNS records some applications might rely on?
3. How would you diagnose if a specific application's excessive/redundant DNS lookups (rather than genuine fleet scale) was a contributing factor?

### Key Interview Signals
Identifies CoreDNS as a central, fleet-scale-sensitive bottleneck and reaches for NodeLocal DNSCache as the architecturally correct, root-cause fix rather than a reactive restart.

### Hands-On Connection
[Lab 2 — Networking and VPC CNI](../labs/lab-02-networking-vpc-cni/).

---

## Question 16: Two clusters, one collision

### Scenario
A second EKS cluster is provisioned in a new VPC for a new team, peered to the existing platform's shared-services VPC via Transit Gateway. Shortly after peering, cross-cluster service calls between the two clusters start failing intermittently, and investigation reveals the two clusters' pod-IP CIDR ranges overlap.

### Interview Question
Diagnose the root cause and design the prevention process for future clusters.

### Strong Senior-Level Answer
**Initial assessment:** overlapping CIDR ranges between peered/connected VPCs is a routing-fundamentals problem, not a Kubernetes-specific one — per [`docs/networking.md`](../docs/networking.md) §9, since pod IPs come directly from VPC CIDR space, any multi-cluster/multi-VPC architecture connecting clusters at the network layer requires disjoint CIDR planning across every connected VPC, exactly as it would for any other overlapping-subnet routing conflict.

**Technical reasoning:** when two peered VPCs have overlapping CIDR ranges, routing becomes ambiguous — traffic intended for a pod IP in one cluster may be routed (or fail to route) based on whichever overlapping route entry is matched, producing exactly the intermittent, confusing failure pattern described (sometimes working, sometimes not, depending on routing-table specifics and which overlapping range a given request happens to hit).

**Investigation process:** confirm via each VPC's actual CIDR allocation (primary and any secondary/custom-networking CIDRs) whether an overlap genuinely exists — this is a straightforward, definitive check once the possibility is considered, though it's easy to miss if CIDR planning wasn't centrally coordinated across teams provisioning clusters independently.

**Recommended solution:** there is no clean in-place fix for already-overlapping CIDRs short of re-CIDRing one of the clusters (a disruptive change, in the case of the new cluster ideally before it takes production traffic — re-provision the new cluster's VPC with a non-overlapping CIDR range, planned against a central CIDR-allocation registry covering every existing and planned cluster/VPC).

**Risk controls:** never provision a new cluster's VPC CIDR in isolation from awareness of every other VPC it might ever need to connect to (directly or transitively via Transit Gateway) — treat CIDR allocation as a centrally coordinated, tracked resource, exactly like IP address management (IPAM) for any other large network.

**Validation steps:** after re-provisioning with a non-overlapping CIDR, confirm cross-cluster service calls succeed reliably under sustained testing, not just a single successful request (given the original failure was intermittent, a one-off successful test isn't sufficient proof).

**Rollback or recovery strategy:** if the new cluster hasn't yet taken production traffic, re-provisioning its VPC/CIDR is the clean recovery path; if it has, this becomes a much higher-stakes migration requiring careful planning around any workload already depending on the conflicting cluster.

**Long-term prevention:** maintain a central CIDR-allocation registry (even a simple, shared spreadsheet or, better, an AWS IPAM pool) that every new VPC/cluster provisioning process must check against before finalizing its CIDR — bake this check into the companion Terraform repository's cluster-provisioning module/process as a mandatory pre-flight step.

### Step-by-Step Implementation
```bash
# Check for CIDR overlap before connecting any new VPC
aws ec2 describe-vpcs --query 'Vpcs[].{VpcId:VpcId,CIDR:CidrBlock,CIDRAssoc:CidrBlockAssociationSet[].CidrBlock}'
# Compare against every VPC that will be directly or transitively (via Transit Gateway) connected
```
Use AWS VPC IPAM to centrally allocate non-overlapping CIDR pools across the organization going forward.

### Under-the-Hood Explanation
VPC peering and Transit Gateway routing both rely on non-overlapping CIDR ranges to unambiguously route traffic to the correct destination VPC — when ranges overlap, the routing table's longest-prefix-match logic (or peering's inherent restriction against overlapping CIDRs, which AWS actually blocks for direct VPC peering, though Transit Gateway with more complex routing can mask this until traffic patterns expose it) produces exactly the ambiguous, intermittent-seeming failure this scenario describes.

### Common Weak Answer
"Just add more specific routes to work around the overlap."

### Why the Weak Answer Fails
Attempting to route around a fundamental CIDR overlap with more specific routes is fragile and doesn't scale — it treats a structural addressing conflict as a routing-table tuning problem, when the actual fix (non-overlapping CIDR allocation) is what prevents this class of ambiguity entirely.

### Follow-Up Questions
1. How would you design a centralized CIDR-allocation process that scales across many teams provisioning their own clusters independently?
2. What's the specific interaction between custom-networking pod-IP CIDRs (Question 11) and multi-cluster CIDR planning?
3. How would AWS VPC IPAM change this process compared to manual CIDR tracking?

### Key Interview Signals
Recognizes CIDR overlap as a fundamental network-addressing problem requiring centralized planning, not something routing-table tricks can reliably work around.

### Hands-On Connection
[Lab 2 — Networking and VPC CNI](../labs/lab-02-networking-vpc-cni/).

---

## Question 17: The Ingress that routed to the wrong version

### Scenario
Two Ingress resources in the same namespace both define rules for overlapping paths (`/api` and `/api/v2`) on the same host, targeting different backend Services, created by two different teams unaware of each other's Ingress. Requests to `/api/v2` intermittently reach the wrong backend.

### Interview Question
Diagnose the conflict and design a process to prevent it recurring.

### Strong Senior-Level Answer
**Initial assessment:** multiple Ingress resources targeting the same host with overlapping path rules creates ambiguous routing precedence — the AWS Load Balancer Controller merges rules from all matching Ingress resources into the same ALB's listener rules, and the resulting rule evaluation order (based on rule priority, which may not obviously reflect either team's intent) determines which backend actually wins for an overlapping path.

**Technical reasoning:** ALB listener rules are evaluated in priority order — if two Ingress resources don't explicitly and consistently set `alb.ingress.kubernetes.io/group.order` (when using IngressGroup to share one ALB) or aren't otherwise coordinated, path-overlap resolution can end up effectively arbitrary from either team's perspective, exactly producing intermittent-seeming (actually deterministic but unexpected) misrouting.

**Investigation process:** confirm via `kubectl get ingress -A` and the AWS Load Balancer Controller's rendered ALB listener rules (viewable in the AWS console) exactly which rule is winning for the conflicting path, and confirm this correlates with the reported misrouting.

**Recommended solution:** consolidate path ownership explicitly — either merge the two teams' routing rules into a single, coordinated Ingress (or IngressGroup with explicit `group.order` priorities reflecting an agreed precedence), or restructure paths so they're genuinely non-overlapping and unambiguous (`/api/v1/*` vs. `/api/v2/*` as clearly disjoint prefixes) rather than relying on implicit rule-priority resolution.

**Risk controls:** any change to Ingress routing rules on a live ALB risks a brief disruption during reconciliation — validate the intended new routing behavior in a non-production environment first.

**Validation steps:** after the fix, test every previously-ambiguous path explicitly and confirm it consistently reaches the intended backend, not just once but repeatedly (to rule out any remaining non-determinism).

**Rollback or recovery strategy:** revert to the previous Ingress configuration if the consolidation introduces an unexpected regression, while the path-ownership conflict is re-resolved.

**Long-term prevention:** establish an organizational convention for path namespacing/ownership per team (e.g., each team owns a distinct top-level path prefix) and, if multiple Ingress resources must share one ALB via IngressGroup, require explicit, reviewed `group.order` coordination as part of any new Ingress's review process.

### Step-by-Step Implementation
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: team-a-ingress
  annotations:
    alb.ingress.kubernetes.io/group.name: shared-alb
    alb.ingress.kubernetes.io/group.order: "10"   # explicit, coordinated priority
spec:
  rules:
    - host: api.example.com
      http:
        paths:
          - path: /api/v1
            pathType: Prefix
            backend:
              service:
                name: team-a-service
                port: { number: 80 }
```

### Under-the-Hood Explanation
The AWS Load Balancer Controller aggregates rules from every Ingress sharing the same `group.name` (or, without explicit grouping, potentially still interacting if they target the same host on separately-provisioned ALBs with DNS-level ambiguity) into one ALB's listener rule set, ordered by `group.order` where specified or an otherwise implementation-determined default — with no inherent awareness of which team "intended" a given path to route where, since Ingress resources are evaluated purely by their declared rules and priority, not by organizational intent.

### Common Weak Answer
"Just tell one team to change their path so it doesn't conflict."

### Why the Weak Answer Fails
This treats the symptom (two overlapping paths right now) without establishing the process (explicit path-ownership conventions, coordinated `group.order`) that prevents the next two teams from creating the same conflict independently in the future.

### Follow-Up Questions
1. How would you design an automated pre-merge check catching overlapping Ingress path/host combinations before they're deployed?
2. What's the trade-off between one shared ALB (via IngressGroup) versus separate ALBs per team, for this kind of conflict?
3. How would you communicate and enforce a path-namespacing convention across many independent teams?

### Key Interview Signals
Diagnoses the actual ALB rule-priority mechanism causing the ambiguous routing, and designs both an immediate fix and an organizational/process-level prevention.

### Hands-On Connection
[Lab 7 — Ingress and Load Balancing](../labs/lab-07-ingress-and-load-balancing/).

---

## Question 18: Layer 4 or Layer 7?

### Scenario
A team needs to expose a gRPC-based internal service to other internal clients, and separately needs to expose a public-facing REST API with path-based routing and TLS termination. They ask whether to use an NLB or ALB for each.

### Interview Question
Make the recommendation for each case and justify it.

### Strong Senior-Level Answer
**Initial assessment:** these are genuinely different requirements calling for different load balancer types — NLB (Layer 4, TCP/UDP) for the gRPC service, ALB (Layer 7, HTTP/HTTPS) for the path-based-routing REST API — not an arbitrary choice but one driven by each workload's actual protocol and routing needs.

**Technical reasoning:** gRPC's use of HTTP/2 with long-lived connections and its own internal multiplexing benefits from NLB's low-latency, connection-preserving Layer 4 passthrough (or, if Layer 7 features like path-based routing genuinely aren't needed, avoiding ALB's additional Layer 7 processing overhead) — and NLB natively supports the sustained, high-throughput connection patterns typical of internal service-to-service gRPC traffic. The REST API's requirement for path-based routing and TLS termination are inherently Layer 7 capabilities — only ALB (or an Ingress controller built on it) can inspect and route based on HTTP path/host, which NLB, operating below the HTTP layer, structurally cannot do.

**Investigation process:** for any load-balancer type decision, explicitly enumerate the workload's actual protocol-level and routing requirements (Layer 4 passthrough vs. Layer 7 content-based routing, TLS termination location, expected connection patterns) before defaulting to whichever load-balancer type is more familiar or commonly used elsewhere in the organization.

**Recommended solution:** NLB (via a `Service` of type `LoadBalancer` with NLB-specific annotations, or an NLB-backed Ingress if intermediate Layer 7 features are still needed for the gRPC service specifically) for the internal gRPC service; ALB (via a standard Ingress) for the public REST API, using its native path-based routing and TLS-termination capabilities directly.

**Risk controls:** confirm gRPC-specific NLB configuration correctly preserves the client's actual source IP and handles connection draining gracefully during any target replacement (node/pod rescheduling), since gRPC's long-lived connections are more sensitive to abrupt connection termination than typical short-lived HTTP requests.

**Validation steps:** load-test both configurations under realistic traffic patterns (sustained long-lived gRPC connections; bursty REST API path-routed traffic) to confirm each load balancer type performs as expected for its specific workload shape.

**Rollback or recovery strategy:** load balancer type can be changed by updating the Service/Ingress configuration and letting the AWS Load Balancer Controller reprovision accordingly — a contained, if not instantaneous, change.

**Long-term prevention:** document this Layer 4 vs. Layer 7 decision framework (protocol needs, routing needs, connection patterns) as a standard reference for future workload-exposure decisions, rather than re-deriving it from scratch each time.

### Step-by-Step Implementation
```yaml
# NLB for internal gRPC service (Layer 4)
apiVersion: v1
kind: Service
metadata:
  name: grpc-service
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: nlb
    service.beta.kubernetes.io/aws-load-balancer-scheme: internal
spec:
  type: LoadBalancer
  ports:
    - port: 443
      targetPort: 8080
---
# ALB for public REST API (Layer 7)
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: rest-api
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:...
spec:
  rules:
    - http:
        paths:
          - path: /v1
            pathType: Prefix
            backend: { service: { name: rest-api-v1, port: { number: 80 } } }
```

### Under-the-Hood Explanation
NLB operates at the transport layer, passing through TCP/UDP connections with minimal processing overhead and preserving connection characteristics well-suited to long-lived, high-throughput traffic like gRPC — it has no visibility into HTTP-level content (paths, headers) at all. ALB operates at the application layer, terminating and inspecting HTTP(S) requests, enabling path/host-based routing and centralized TLS termination, at the cost of additional Layer 7 processing that's unnecessary overhead for a workload that doesn't need it.

### Common Weak Answer
"Just use ALB for everything since it's more feature-rich."

### Why the Weak Answer Fails
ALB's Layer 7 features are irrelevant overhead for a workload with no actual Layer 7 routing need, and its HTTP-oriented processing model is a worse fit for gRPC/long-lived-connection traffic patterns than NLB's Layer 4 passthrough — "more features" doesn't mean "better fit," and choosing based on protocol/routing needs rather than feature-richness is the correct decision process.

### Follow-Up Questions
1. How would this decision change if the gRPC service also needed path-based routing between multiple gRPC methods/services?
2. What's the TLS-termination trade-off between terminating at the ALB versus passing through to the pod for NLB?
3. How would you handle a workload needing both Layer 4 passthrough for some traffic and Layer 7 routing for other traffic simultaneously?

### Key Interview Signals
Makes the NLB-vs-ALB decision based on the workload's actual protocol and routing requirements, not familiarity or a one-size-fits-all default.

### Hands-On Connection
[Lab 7 — Ingress and Load Balancing](../labs/lab-07-ingress-and-load-balancing/).

---

## Question 19: kube-proxy at the edge of its comfort zone

### Scenario
A cluster running kube-proxy in `iptables` mode with several thousand Services starts showing measurably increased latency for Service-to-Service connections, along with elevated CPU usage on nodes correlating with any Service creation/update event.

### Interview Question
Diagnose the scaling limitation and propose the fix.

### Strong Senior-Level Answer
**Initial assessment:** `iptables` mode's rule-update mechanism scales poorly with Service count — every Service/Endpoint change requires kube-proxy to rewrite a large, sequentially-evaluated iptables rule chain, and at several thousand Services, both the per-packet rule-traversal cost (increased latency) and the rule-rewrite cost on any change (elevated CPU during updates) become measurable, real problems, not theoretical concerns.

**Technical reasoning:** `iptables` mode evaluates rules largely sequentially for a given packet (with some optimization via hash-based jumps, but still scaling worse than a true hash-table lookup) — as Service count grows into the thousands, this sequential-ish evaluation cost per packet becomes a real, measurable latency contributor, and full rule-table rewrites on every Service/Endpoint change become increasingly expensive computationally as the ruleset grows.

**Investigation process:** confirm via kube-proxy's own metrics/logs (sync duration metrics specifically) and correlate elevated CPU with Service/Endpoint change events — this settles that the scaling limitation is genuinely kube-proxy's rule-management overhead, not an unrelated cause.

**Recommended solution:** switch kube-proxy to **IPVS mode**, which uses a genuine hash-table-based lookup for Service routing (O(1) lookup regardless of Service count) rather than iptables' more sequential rule evaluation, and updates incrementally rather than requiring full ruleset rewrites on every change — the standard fix for exactly this kube-proxy scaling profile.

**Risk controls:** switching kube-proxy modes is a cluster-wide, potentially disruptive change (it affects how every Service is routed) — test thoroughly in non-production first, and plan a careful rollout (e.g., via a DaemonSet update with appropriate `maxUnavailable` pacing) rather than a single simultaneous cluster-wide flip.

**Validation steps:** after switching to IPVS, confirm both the latency and CPU-on-change metrics improve as expected under representative load, and confirm no Service connectivity regression across a broad sample of workloads.

**Rollback or recovery strategy:** revert kube-proxy's mode configuration and roll back the DaemonSet if IPVS mode introduces any unexpected connectivity issue — a contained, reversible change if caught quickly.

**Long-term prevention:** for any cluster anticipated to grow into the thousands of Services, plan for IPVS mode (or an eBPF-based dataplane like Cilium's kube-proxy replacement, an even more modern alternative) proactively rather than waiting for `iptables` mode's scaling limits to cause a production incident first.

### Step-by-Step Implementation
```bash
# Switch kube-proxy to IPVS mode (via its ConfigMap)
kubectl edit configmap kube-proxy -n kube-system
# Set: mode: "ipvs"
kubectl rollout restart daemonset kube-proxy -n kube-system
```

### Under-the-Hood Explanation
IPVS (IP Virtual Server, a Linux kernel load-balancing technology) maintains Service-to-Endpoint mappings in an actual hash table, giving constant-time lookup regardless of how many Services exist, and supports incremental updates when Endpoints change — a structurally more scalable design than `iptables` mode's sequential (if hash-jump-optimized) rule-chain evaluation and full-table-rewrite-on-change behavior.

### Common Weak Answer
"Just add more CPU to the nodes to handle the load."

### Why the Weak Answer Fails
Throwing more CPU at the problem treats the symptom (elevated CPU usage) without addressing the actual algorithmic scaling limitation in `iptables` mode's rule-management approach — IPVS mode fixes the root cause structurally, at a fraction of the cost of over-provisioning node CPU indefinitely as Service count continues to grow.

### Follow-Up Questions
1. What's the trade-off of adopting an eBPF-based dataplane (like Cilium) as a further evolution beyond IPVS?
2. How would you validate IPVS mode's compatibility with existing NetworkPolicy enforcement before the cluster-wide switch?
3. How would you pace a cluster-wide kube-proxy mode change to minimize risk during rollout?

### Key Interview Signals
Identifies the specific algorithmic scaling limitation of `iptables` mode and proposes the structurally correct fix (IPVS) rather than a resource-throwing workaround.

### Hands-On Connection
[Lab 2 — Networking and VPC CNI](../labs/lab-02-networking-vpc-cni/).

---

## Question 20: The custom networking migration that took down new pods

### Scenario
A team enables custom networking (`ENIConfig` + `AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG=true`) on a running production cluster to solve subnet IP exhaustion (per Question 11), without first cordoning/draining existing nodes. New pods scheduled on existing (already-running, not-yet-replaced) nodes begin failing to get IPs at all.

### Interview Question
Explain why existing nodes broke, and design the correct migration sequence.

### Strong Senior-Level Answer
**Initial assessment:** custom networking's configuration change only takes effect for a node's pod-IP allocation *after that node's `aws-node` (VPC CNI) pod restarts and re-initializes with the new configuration* — critically, existing, already-provisioned ENIs on a node don't automatically remap to the new custom-networking CIDR, and a node that hasn't been replaced (or had its CNI properly re-initialized per the documented migration process) can end up in an inconsistent state where new pod scheduling fails.

**Technical reasoning:** enabling custom networking changes which subnet/CIDR the VPC CNI draws pod IPs from going forward, but a node's existing warm IP pool (allocated from the *old*, non-custom-networking configuration) doesn't retroactively update — and depending on exactly how the rollout was sequenced, a node can end up with a `aws-node` pod that's restarted into the new configuration mode while running on a node lacking the correspondingly-required `ENIConfig`-referenced subnet resources properly available, causing new IP allocation to fail entirely for that node.

**Investigation process:** confirm via `aws-node` pod logs on the affected nodes exactly what IP-allocation error is occurring, and confirm whether those specific nodes were part of the fleet at the time custom networking was enabled (pre-existing) versus newly launched after (which would correctly pick up the new configuration from the start via their bootstrap process).

**Recommended solution:** follow AWS's documented custom-networking migration procedure precisely: enable the configuration cluster-wide, then **replace every existing node** (not just restart the CNI pod) so each node bootstraps fresh under the new custom-networking configuration from the start, rather than attempting to transition a running node in place.

**Risk controls:** perform the node replacement in a paced, rolling fashion (via a managed node group version update, or Karpenter's own node-replacement mechanism) respecting `PodDisruptionBudget`s, exactly like any other node-replacement operation — never a simultaneous, all-at-once replacement.

**Validation steps:** after full node replacement, confirm every node in the fleet is running under the new custom-networking configuration (checking `aws-node` environment/logs across the fleet) and confirm new pod scheduling succeeds reliably cluster-wide.

**Rollback or recovery strategy:** for nodes already broken by the incomplete migration, the fix is the same node replacement that should have been done proactively — cordon, drain, and replace the affected nodes to bring them onto the new configuration correctly.

**Long-term prevention:** treat any VPC-CNI-level configuration change (custom networking, prefix delegation, `WARM_IP_TARGET` tuning) as requiring a full, paced node-replacement migration, never an in-place transition — document this explicitly as a standing rule for CNI configuration changes, exactly like the companion Terraform repository's "some infrastructure changes force a replacement, plan for it" guidance applied to node-level VPC CNI configuration specifically.

### Step-by-Step Implementation
```bash
# 1. Enable custom networking configuration cluster-wide (affects new nodes going forward)
kubectl set env daemonset aws-node -n kube-system AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG=true

# 2. Apply ENIConfig per AZ (see Question 11)

# 3. Replace EVERY existing node - paced, respecting PodDisruptionBudgets
#    (e.g., trigger a managed node group version update, or let Karpenter's
#    drift detection replace nodes as they no longer match the desired NodeClass)
```

### Under-the-Hood Explanation
The VPC CNI's `ipamd` daemon on each node determines pod-IP allocation behavior based on its own current configuration and the ENIs it has already attached — a configuration change doesn't retroactively re-derive a node's already-attached ENI/IP state; only a fresh node, bootstrapping under the new configuration from the start, correctly initializes according to it, which is exactly why AWS's documented migration procedure requires full node replacement rather than an in-place transition.

### Common Weak Answer
"Just restart the aws-node DaemonSet pods on the existing nodes to pick up the new config."

### Why the Weak Answer Fails
Restarting the `aws-node` pod alone doesn't correctly re-derive the node's already-established ENI/IP state under the new custom-networking configuration — this is precisely the incomplete-migration mistake that caused the incident; only full node replacement correctly and safely completes the transition.

### Follow-Up Questions
1. How would you validate a custom-networking migration in a non-production cluster before applying it to production?
2. What's the interaction between this migration and an active Karpenter-managed fleet versus a static managed node group?
3. How would you communicate the expected node-churn/disruption window to affected application teams during this migration?

### Key Interview Signals
Correctly identifies that a CNI-level configuration change requires full node replacement (not just a component restart) to take effect safely, and designs a paced, PDB-respecting migration rather than an in-place shortcut.

### Hands-On Connection
[Lab 2 — Networking and VPC CNI](../labs/lab-02-networking-vpc-cni/) and [Lab 4 — Managed Node Groups](../labs/lab-04-managed-node-groups/).

---

## Question 21: The internal service that leaked externally

### Scenario
A Service intended to be internal-only (`internal` load-balancer scheme) is accidentally created with `internet-facing` scheme due to a copy-pasted annotation from an unrelated public-facing Service's manifest, exposing an internal API to the public internet for several hours before discovery.

### Interview Question
How would you have caught this before it happened, and how do you prevent recurrence?

### Strong Senior-Level Answer
**Initial assessment:** this is a governance/policy-as-code gap, not fundamentally a networking-mechanics problem — the AWS Load Balancer Controller faithfully did exactly what the (incorrect) annotation specified; the actual failure was the absence of any automated check catching an internal-only-intended Service being configured as internet-facing before it reached a live cluster.

**Technical reasoning:** the `service.beta.kubernetes.io/aws-load-balancer-scheme` (or the Ingress-equivalent `alb.ingress.kubernetes.io/scheme`) annotation directly controls whether the provisioned NLB/ALB gets a public or internal-only DNS name and routing — there's no additional Kubernetes-native safeguard preventing an incorrect value from being applied; it's purely declarative and trusted as-is.

**Investigation process:** confirm exactly how the incorrect annotation entered the manifest (a copy-paste error, as described) — this is a straightforward root-cause once identified, but the more important investigation is *why no automated check caught it* before the manifest was applied/synced.

**Recommended solution:** implement an admission-time policy (via Kyverno/OPA Gatekeeper, per [`docs/governance-policy.md`](../docs/governance-policy.md)) enforcing that any Service/Ingress in namespaces/labels designated "internal-only" cannot be configured with an internet-facing scheme — a structural, non-bypassable guardrail rather than relying on manual manifest review to catch every such mistake.

**Risk controls:** additionally, add a CI-level policy test (`kyverno test`/`gator test`, per [`docs/governance-policy.md`](../docs/governance-policy.md) §4) catching this exact misconfiguration pre-merge, before it's even synced by the GitOps controller — defense-in-depth, not relying on the admission-time check alone.

**Validation steps:** deliberately attempt to create a test Service with the same incorrect combination (internal-only namespace label + internet-facing scheme annotation) after implementing the policy, confirming it's actually rejected both in CI and at admission time.

**Rollback or recovery strategy:** for the immediate incident, correct the annotation and confirm the load balancer's scheme updates accordingly (may require a brief service interruption as the Load Balancer Controller reprovisions); separately assess whether the several-hour public exposure window requires further incident response (was any sensitive data actually accessed, credential rotation needed, etc.).

**Long-term prevention:** treat "does this Service/Ingress's exposure scheme match its intended internal/external designation" as a standing, policy-enforced, tested guardrail for every namespace/workload going forward — exactly the same "prevent plus independently detect" layered-defense discipline established in the companion Ansible repository's [Question 52](../../ansible/interview-questions/05-aws-cloud-integration.md#question-52-the-tag-that-decided-everything) tagging-guardrail guidance, applied here to load-balancer exposure scheme.

### Step-by-Step Implementation
```yaml
# Kyverno ClusterPolicy - block internet-facing scheme for internal-only namespaces
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: enforce-internal-only-scheme
spec:
  validationFailureAction: Enforce
  rules:
    - name: block-internet-facing-in-internal-namespaces
      match:
        any:
          - resources:
              kinds: [Service, Ingress]
              namespaceSelector:
                matchLabels:
                  network-exposure: internal-only
      validate:
        message: "internet-facing load balancer scheme is not allowed in internal-only namespaces"
        pattern:
          metadata:
            annotations:
              =(service.beta.kubernetes.io/aws-load-balancer-scheme): "internal"
```

### Under-the-Hood Explanation
The AWS Load Balancer Controller reads the scheme annotation and passes it directly to the underlying AWS load-balancer-provisioning API call — there's no independent Kubernetes-level validation of whether a given scheme "matches" the workload's intended exposure level unless a policy engine is explicitly configured to check for it; without that check, an incorrect annotation is provisioned exactly as declared, with full trust and no default sanity check.

### Common Weak Answer
"Just be more careful during manifest review to catch copy-paste errors like this."

### Why the Weak Answer Fails
Relying on manual review vigilance is precisely the non-control this repository series consistently identifies as insufficient — a structural, policy-enforced, and CI-tested guardrail catches this class of mistake reliably regardless of any individual reviewer's attentiveness on a given day.

### Follow-Up Questions
1. How would you extend this policy pattern to other potentially-dangerous annotation/configuration combinations beyond load-balancer scheme?
2. What's the incident-response process for a several-hour accidental public exposure of an internal API — what needs investigating beyond just fixing the misconfiguration?
9. How would you retroactively audit all existing Services/Ingresses for this same class of scheme-mismatch risk?

### Key Interview Signals
Frames this as a governance/policy-as-code gap rather than a one-off human error, and designs both a structural admission-time guardrail and a CI-level pre-merge test as complementary layers.

### Hands-On Connection
[Lab 7 — Ingress and Load Balancing](../labs/lab-07-ingress-and-load-balancing/) and [Lab 13 — Policy as Code](../labs/lab-13-policy-as-code-opa/).

---

## Question 22: The migration from Calico that nobody tested

### Scenario
A cluster running Calico (for NetworkPolicy enforcement, installed before native VPC CNI network-policy support existed) plans to migrate to native VPC CNI network-policy enforcement to simplify the CNI stack and remove a self-managed component. The migration plan is "just enable the native feature and uninstall Calico."

### Interview Question
Evaluate this migration plan and identify what's missing.

### Strong Senior-Level Answer
**Initial assessment:** the plan's sequencing risks a real enforcement gap or, worse, a policy-semantics mismatch — Calico's policy engine and the native VPC CNI's network-policy implementation, while both consuming standard Kubernetes `NetworkPolicy` objects, may not support fully identical feature coverage (e.g., Calico's own `GlobalNetworkPolicy` CRD extensions, or subtle differences in how each implementation handles specific selector/rule edge cases) — "just enable the native feature and uninstall Calico" skips validating this compatibility entirely.

**Technical reasoning:** if Calico is uninstalled before confirming the native implementation correctly enforces every existing policy's actual intent, there's a real risk of a silent enforcement gap (a policy that worked correctly under Calico is subtly under-enforced or over-permissive under the native implementation) — and given [`docs/networking.md`](../docs/networking.md) §7's core lesson (NetworkPolicy enforcement gaps are invisible without active testing), this exact migration is precisely the kind of change that needs deliberate, positive-control validation, not an optimistic "should be equivalent" assumption.

**Investigation process:** inventory every existing `NetworkPolicy` object (and any Calico-specific `GlobalNetworkPolicy`/`NetworkSet` extensions in use) and confirm feature-parity against the native VPC CNI implementation's documented capabilities — identifying any policy relying on a Calico-specific extension that has no native equivalent before proceeding.

**Recommended solution:** run both implementations in parallel during a validation window if feasible (or, if not feasible simultaneously, validate exhaustively in a non-production cluster mirroring production's actual policy set) — for every existing policy, run the same positive-control tests (attempt connections that should be blocked and should be allowed) under the native implementation before uninstalling Calico, and only decommission Calico once every policy's enforcement behavior is confirmed equivalent.

**Risk controls:** for any policy relying on a Calico-specific extension with no native equivalent, either find an alternative native-compatible way to express the same intent, or explicitly accept and document keeping Calico (or a subset of its functionality) for those specific cases rather than silently losing that enforcement.

**Validation steps:** for every single existing `NetworkPolicy`, execute a real connection test against both the should-be-blocked and should-be-allowed cases under the native implementation — exactly the same "never trust a policy object's existence alone" discipline from Question 14, applied here to a migration between two enforcement mechanisms rather than an initial enablement.

**Rollback or recovery strategy:** keep Calico installed (even if redundant) until the native implementation's validation is fully complete — only uninstall once confident, since re-installing Calico after a gap is discovered in production is a much higher-stakes, reactive scramble than simply not having removed it yet.

**Long-term prevention:** treat any CNI/policy-enforcement migration as requiring the same exhaustive positive-control test coverage as the original policy-enforcement rollout (Question 14) — never assume equivalence between two different enforcement implementations without explicit, per-policy verification.

### Step-by-Step Implementation
```bash
# Inventory every existing policy and any Calico-specific extensions
kubectl get networkpolicy -A -o yaml > all-policies.yaml
kubectl get globalnetworkpolicy -o yaml > calico-global-policies.yaml   # Calico-specific, no native equivalent

# For each policy, run positive-control tests under BOTH implementations before cutover
# (should-be-blocked and should-be-allowed cases, per Question 14's validation pattern)
```

### Under-the-Hood Explanation
Both Calico and the native VPC CNI network-policy implementation consume the same standard Kubernetes `NetworkPolicy` API object, but each has its own independent enforcement engine translating that declarative object into actual datapath rules (iptables/eBPF-based, implementation-specific) — meaning subtle differences in rule interpretation, default-deny semantics at edge cases, or extended feature support (Calico's CRD extensions) are genuinely possible between the two, and are only caught by explicit, per-policy behavioral testing, not by assuming API-object compatibility implies enforcement-behavior compatibility.

### Common Weak Answer
"They both implement the same NetworkPolicy API, so switching should be seamless."

### Why the Weak Answer Fails
Implementing the same API surface doesn't guarantee identical enforcement behavior at every edge case, and Calico-specific extensions (like `GlobalNetworkPolicy`) have no native equivalent at all — assuming seamless equivalence without testing risks a silent security-enforcement regression exactly like the gap in Question 14, just introduced via a migration instead of an initial rollout.

### Follow-Up Questions
1. How would you handle a policy that relies specifically on a Calico-only feature with no native equivalent?
2. What's your plan if the parallel-validation window reveals a genuine enforcement gap in the native implementation for some specific policy?
3. How would you communicate the migration timeline and risk to application teams whose workloads depend on correctly-enforced NetworkPolicy?

### Key Interview Signals
Refuses to assume equivalence between two different policy-enforcement implementations without explicit, exhaustive, positive-control testing, applying the same enforcement-verification discipline established in Question 14 to a migration scenario.

### Hands-On Connection
[Lab 2 — Networking and VPC CNI](../labs/lab-02-networking-vpc-cni/) and [Lab 8 — Security Hardening](../labs/lab-08-security-hardening/).
