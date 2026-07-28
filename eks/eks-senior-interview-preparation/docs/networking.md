# EKS Networking

Deep-dive reference for [`interview-questions/02-networking.md`](../interview-questions/02-networking.md) and [Lab 2 — Networking and VPC CNI](../labs/lab-02-networking-vpc-cni/).

## 1. The VPC CNI's IP-per-pod model

The default Amazon VPC CNI plugin assigns every pod a real, routable IP address from the VPC's own address space (not an overlay network) — each pod IP is a secondary private IP address on one of the node's ENIs. This is why pod-to-pod traffic doesn't require any encapsulation/overlay and integrates directly with VPC-native constructs (security groups, VPC Flow Logs, Network ACLs), but it also means **pod density per node is bounded by ENI/IP capacity**, not just CPU/memory.

## 2. ENI and IP allocation limits — the real scaling constraint

Every EC2 instance type has a maximum number of ENIs it can attach and a maximum number of IPs per ENI, both fixed by instance type (documented in the `ENI-max-pods` table AWS publishes). The VPC CNI's `ipamd` daemon pre-allocates ENIs/IPs on each node up to a "warm pool" target so pod scheduling doesn't block on live ENI attachment. A node running out of attachable IPs shows pods stuck in `ContainerCreating` with CNI-plugin errors — a distinct failure mode from a scheduling failure (insufficient CPU/memory), and one many engineers misdiagnose as a generic networking issue rather than IP exhaustion specifically.

## 3. Prefix delegation — solving IP exhaustion at the source

Prefix delegation (enabling `ENABLE_PREFIX_DELEGATION=true` on the VPC CNI) assigns each ENI a `/28` IPv4 prefix (16 addresses) instead of individual secondary IPs, dramatically increasing the pods-per-node ceiling for the same ENI count — the direct fix for nodes hitting IP-exhaustion limits before they hit CPU/memory limits. The trade-off: it consumes a larger contiguous CIDR block per ENI, which matters for subnet sizing (a subnet needs enough headroom for prefix-aligned allocation, not just raw IP count) — see [Question 11](../interview-questions/02-networking.md#question-11) for the full scenario.

## 4. Security groups: node-level vs. pod-level

By default, all pods on a node share that node's security group — there's no pod-level network isolation via security groups without additional configuration. **Security Groups for Pods** (via the `amazon-vpc-resource-controller` and a `SecurityGroupPolicy` custom resource) allows specific pods (matched by label) to get their own ENI with a dedicated security group, distinct from the node's — the mechanism for enforcing genuinely pod-granular network access control at the AWS security-group layer, as opposed to Kubernetes-native NetworkPolicy (§6) which operates at a different layer entirely.

## 5. Service types and how they actually reach AWS load balancing

- **ClusterIP:** internal-only, virtual IP handled by `kube-proxy` (iptables or IPVS mode) — no AWS load balancer involved at all.
- **NodePort:** exposes a port on every node's IP — rarely used directly in production; usually an implementation detail underneath a LoadBalancer service or Ingress.
- **LoadBalancer:** provisions a real AWS load balancer (Classic, NLB, or ALB depending on annotations/controller) — the **AWS Load Balancer Controller** (a self-managed add-on, not EKS-managed) is what actually watches `Service`/`Ingress` objects and provisions/configures the corresponding NLB/ALB and target groups.
- **Ingress:** routes HTTP(S) traffic by host/path to backend Services — requires an Ingress controller; on EKS this is almost always the AWS Load Balancer Controller provisioning an ALB, using `alb.ingress.kubernetes.io/*` annotations for configuration.

## 6. Target type: instance vs. ip — a critical, easy-to-miss decision

The AWS Load Balancer Controller's ALB/NLB target groups can register targets as:

- **`instance`** — routes to a node's port (NodePort under the hood), adding an extra network hop (kube-proxy) inside the node before reaching the actual pod, and target-group health checks reflect node-level, not pod-level, health.
- **`ip`** (recommended for VPC CNI clusters) — routes directly to the pod's own routable IP, skipping the node hop and giving health checks true pod-level accuracy — this is the modern default recommendation specifically because the VPC CNI's IP-per-pod model makes it possible.

Choosing `instance` mode on a VPC-CNI cluster is a common "it works, but it's not how you should do it" answer — see [Question 12](../interview-questions/02-networking.md#question-12).

## 7. NetworkPolicy: not enforced by default with the vanilla VPC CNI

Kubernetes `NetworkPolicy` objects are inert unless something actually enforces them — the vanilla VPC CNI historically required a separate CNI plugin (Calico) for NetworkPolicy enforcement; more recent VPC CNI versions support native NetworkPolicy enforcement directly (`ENABLE_NETWORK_POLICY=true`), removing the need for Calico for this specific purpose on newer clusters. The senior-level check for any cluster claiming "we use NetworkPolicy for isolation": confirm *something* is actually enforcing it, since a `NetworkPolicy` object applied against a cluster with no enforcement mechanism silently does nothing — no error, no warning, just an inert YAML object.

## 8. CoreDNS: a cluster-wide single point of contention at scale

CoreDNS runs as a Deployment (typically 2 replicas by default) serving DNS resolution for the entire cluster's service discovery. At scale (many pods making frequent DNS lookups), CoreDNS can become a bottleneck or even a point of cascading failure if it falls behind — NodeLocal DNSCache (a DaemonSet caching DNS responses locally on each node) is the standard mitigation, reducing the query load that reaches the central CoreDNS Deployment. This mirrors the same "central bottleneck under fleet-wide load" pattern seen elsewhere in this repository (API server request load, inventory-resolution API throttling in the companion Ansible repo) — see [Question 17](../interview-questions/02-networking.md#question-17).

## 9. Cross-VPC and multi-cluster connectivity

Multi-cluster or hub-and-spoke architectures (a shared services VPC, multiple workload-cluster VPCs) typically connect via Transit Gateway or VPC peering, with careful CIDR planning to avoid overlap (since pod IPs come directly from VPC CIDR space, cluster VPC sizing must account for the full expected pod count across all node groups, not just node count) — see [Question 18](../interview-questions/02-networking.md#question-18) for a CIDR-exhaustion scenario at the multi-cluster level.

## Common weak vs. senior answers

| Weak answer | Senior answer |
|---|---|
| "Pods get IPs somehow, it just works" | Explains the ENI/secondary-IP allocation model and its per-node capacity limits |
| "Use `instance` target type, it's simpler" | Knows `ip` target type is the correct default for VPC-CNI clusters, and why |
| "NetworkPolicy isolates our pods" | Verifies an actual enforcement mechanism (native VPC CNI policy support or Calico) exists before trusting a NetworkPolicy object does anything |
| "Just add more CoreDNS replicas if DNS is slow" | Recognizes NodeLocal DNSCache as the more effective, root-cause fix at scale |

## Related material

- [`docs/eks-architecture.md`](eks-architecture.md), [`docs/iam-irsa.md`](iam-irsa.md) (Security Groups for Pods overlaps IRSA-adjacent identity concepts)
- [Lab 2 — Networking and VPC CNI](../labs/lab-02-networking-vpc-cni/), [Lab 7 — Ingress and Load Balancing](../labs/lab-07-ingress-and-load-balancing/)
