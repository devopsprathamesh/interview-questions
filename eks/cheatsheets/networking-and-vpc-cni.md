# Cheat Sheet: Networking and VPC CNI

## Pod density: a separate ceiling from CPU/memory
Pods-per-node is capped by **ENI count × IPs-per-ENI** for the instance type — hit before compute limits, especially on smaller instances. Fix: prefix delegation.
```bash
kubectl set env daemonset aws-node -n kube-system ENABLE_PREFIX_DELEGATION=true
```
[Question 11](../interview-questions/02-networking.md#question-11-the-subnet-that-ran-out-of-room) — requires full node replacement to take effect cleanly, not just a DaemonSet restart. [Question 20](../interview-questions/02-networking.md#question-20-the-custom-networking-migration-that-took-down-new-pods)

## Target-type: the health-check granularity decision
| | `instance` | `ip` (recommended default) |
|---|---|---|
| Health check reflects | Node/NodePort reachability | The specific pod's actual health |
| Extra hop | Yes (via kube-proxy) | No — direct to pod IP |
| Blind spot | A crashed pod on a healthy node still gets traffic briefly | None — catches pod-level failure immediately |
[Question 12](../interview-questions/02-networking.md#question-12-the-health-check-that-lied)

## NetworkPolicy: object existence ≠ enforcement
```bash
# Check if anything is actually enforcing NetworkPolicy at all
kubectl get daemonset aws-node -n kube-system -o jsonpath='{.spec.template.spec.containers[0].env}' | grep NETWORK_POLICY
```
**Never trust a NetworkPolicy claim without a positive-control test** — attempt the connection that should be blocked. [Question 14](../interview-questions/02-networking.md#question-14-the-networkpolicy-that-did-nothing)

## CoreDNS at scale
Default replica count (often 2) serves the *entire* cluster — a central bottleneck past a few hundred nodes. Fix: NodeLocal DNSCache (caches locally, reduces load reaching central CoreDNS) + cluster-proportional-autoscaler for CoreDNS's own replica count. [Question 15](../interview-questions/02-networking.md#question-15-the-dns-resolver-that-couldnt-keep-up)

## IngressGroup path conflicts
Multiple Ingress resources sharing one ALB via `group.name` merge into one listener rule set, evaluated by priority. Without explicit `group.order`, precedence is deterministic but effectively arbitrary. [Question 17](../interview-questions/02-networking.md#question-17-the-ingress-that-routed-to-the-wrong-version)

## NLB vs. ALB
| | NLB (Layer 4) | ALB (Layer 7) |
|---|---|---|
| Best for | gRPC, long-lived connections, raw TCP/UDP | HTTP(S), path/host-based routing, TLS termination |
| Health check | Connection-level | HTTP-request-level |
[Question 18](../interview-questions/02-networking.md#question-18-layer-4-or-layer-7)

## CIDR planning for multi-cluster
Pod IPs come directly from VPC CIDR space — any multi-cluster/VPC-peered architecture needs disjoint CIDRs across every connected VPC, planned centrally (AWS VPC IPAM), not discovered after a peering conflict. [Question 16](../interview-questions/02-networking.md#question-16-two-clusters-one-collision)
