# Cheat Sheet: kubectl and AWS CLI Commands for EKS

| Command | Purpose | Notes |
|---|---|---|
| `aws eks update-kubeconfig --name X --region Y` | Configure kubectl for a cluster | First command against any new cluster |
| `aws eks describe-cluster --name X --query cluster.resourcesVpcConfig` | Check endpoint access mode | Public/private/CIDR-restricted — a security-relevant check |
| `aws eks describe-addon --cluster-name X --addon-name vpc-cni` | Check an EKS-managed add-on's version/config | |
| `kubectl get nodes -o wide` | List nodes with IPs/versions | Check for version skew against control plane |
| `kubectl describe pod POD` | Full pod detail including Events | The first diagnostic step for any stuck pod |
| `kubectl get events -A --sort-by=.lastTimestamp` | Cluster-wide recent events | |
| `kubectl top pods/nodes` | Current resource usage | `metrics-server` only — no history, see [Question 79](../interview-questions/09-observability.md#question-79-the-autoscaling-that-had-no-history) |
| `kubectl get pods -A --field-selector=status.phase=Pending` | Find all pending pods cluster-wide | |
| `kubectl get endpoints SERVICE` | Check a Service's actual matched pods | Empty = label-selector mismatch, [Question 9](../docs/troubleshooting.md#9-dynamic-inventoryequivalent-a-service-silently-matching-zero-pods) |
| `kubectl get pdb -A` | List all PodDisruptionBudgets | Check for `disruptionsAllowed: 0` before any node drain |
| `kubectl drain NODE --ignore-daemonsets` | Cordon and evict a node | Respects PDBs — can stall, see [Question 37](../interview-questions/04-node-management.md#question-37-the-managed-node-group-stuck-mid-update) |
| `kubectl get nodeclaims` | Karpenter's own provisioning record | Karpenter-specific, not a core kubectl resource |
| `kubectl get --raw /apis/metrics.k8s.io/v1beta1/pods` | Raw metrics-server API query | No time-range parameter exists — proves the no-history claim directly |
| `kubectl auth can-i VERB RESOURCE --as=IDENTITY` | Test RBAC permissions | Positive-control testing for least-privilege verification |
| `kubectl get polr -A` | Kyverno PolicyReport (audit-mode findings) | Check before promoting a policy to Enforce |
| `argocd app get APP` | ArgoCD application sync/health status | |
| `kubectl argo rollouts get rollout NAME --watch` | Watch a canary/blue-green rollout live | |
| `aws elbv2 describe-target-health --target-group-arn ARN` | Check ALB target health directly | Cross-reference against `kubectl get endpoints` for `instance` vs `ip` mode diagnosis |
