# Cheat Sheet: Autoscaling and Karpenter

## Karpenter vs. Cluster Autoscaler
| | Cluster Autoscaler | Karpenter |
|---|---|---|
| Provisioning | Scales pre-defined ASGs only | Provisions EC2 directly, no ASG intermediary |
| Instance selection | Constrained to node-group boundaries | Live scheduling simulation, best-fit instance type |
| Consolidation | No native equivalent | Active — reclaims underutilized nodes automatically |
| Extended resources | Template-based simulation, can be inaccurate | Queries real EC2 instance-type specs directly |

## Diagnosing a pending pod Karpenter won't provision for
Karpenter only provisions instance types permitted by **at least one** `NodePool`. No matching `NodePool` (e.g., a GPU request with only general-purpose NodePools configured) = correctly does nothing, not a bug.
```bash
kubectl describe pod PENDING_POD   # check exact resource request
kubectl get nodepool -o yaml       # cross-reference against permitted instance families
```
[Question 36](../interview-questions/04-node-management.md#question-36-the-karpenter-nodepool-that-never-matched)

## Taints are required for genuine node-pool exclusivity
Affinity alone only controls the *intended* workload's placement — it does nothing to stop **unrelated** pods from also landing there. Only a taint on the node pool (with a matching toleration on intended workloads) reserves capacity exclusively.
```yaml
# NodePool
spec:
  template:
    spec:
      taints:
        - { key: nvidia.com/gpu, effect: NoSchedule }
```
[Question 55](../interview-questions/06-autoscaling-scheduling.md#question-55-the-taint-nobody-remembered-to-add)

## HPA + Karpenter oscillation
Two independently-timed control loops (HPA's `stabilizationWindowSeconds`, Karpenter's `consolidateAfter`) can compose into churn neither exhibits alone if tuned too aggressively relative to the workload's real load-variation period. Tune both **together**, don't just disable consolidation. [Question 41](../interview-questions/06-autoscaling-scheduling.md#question-41-hpa-and-karpenter-fighting-in-slow-motion)

## HPA + VPA conflict
Both scaling the **same** resource dimension (e.g., both reacting to CPU) creates a mutual feedback loop. Scope VPA to a different dimension (e.g., memory) than HPA's, or run VPA in recommendation-only mode. [Question 53](../interview-questions/06-autoscaling-scheduling.md#question-53-hpa-and-vpa-fighting-over-the-same-dial)

## KEDA for scale-to-zero
Standard HPA **cannot** scale to zero (structural API limit, not a config option). KEDA's `ScaledObject` manages the zero-to-one activation itself, handing off to a standard HPA for the non-zero range. [Question 57](../interview-questions/06-autoscaling-scheduling.md#question-57-keda-versus-hpas-built-in-metrics)

## Spot interruptions: expected, not anomalous
Design for the 2-minute interruption notice: Karpenter's native interruption handling (or AWS Node Termination Handler) + `terminationGracePeriodSeconds` + `PodDisruptionBudget`. [Question 35](../interview-questions/04-node-management.md#question-35-the-spot-interruption-nobody-handled-gracefully)

## Requests vs. limits — two different mechanisms
- **Requests**: scheduling/capacity-accounting only. An oversized request wastes cluster capacity.
- **Limits**: kernel cgroup-enforced ceiling at runtime. Missing limit = genuinely unbounded consumption, a noisy-neighbor risk regardless of request size.
[Question 60](../interview-questions/06-autoscaling-scheduling.md#question-60-scheduling-for-a-workload-that-lies-about-its-needs)
