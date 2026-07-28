#!/bin/bash
# Systematic elimination checklist - per Question 103's "rule out
# configuration before blaming the platform" discipline.
set -euo pipefail
POD=${1:-unschedulable-pod-demo}

echo "=== 1. Resource requests vs. available cluster capacity ==="
kubectl describe pod "$POD" | grep -A3 "Requests:"
kubectl describe nodes | grep -A5 "Allocated resources"

echo ""
echo "=== 2. Node selector / affinity vs. actual node labels ==="
kubectl get pod "$POD" -o jsonpath='{.spec.nodeSelector}{"\n"}{.spec.affinity}'

echo ""
echo "=== 3. Taints vs. tolerations ==="
kubectl get nodes -o json | jq -r '.items[] | "\(.metadata.name): \(.spec.taints // "no taints")"'
kubectl get pod "$POD" -o jsonpath='{.spec.tolerations}'

echo ""
echo "=== 4. Topology spread constraints ==="
kubectl get pod "$POD" -o jsonpath='{.spec.topologySpreadConstraints}'

echo ""
echo "=== 5. Karpenter NodePool constraints (if applicable) ==="
kubectl get nodepools 2>/dev/null || echo "Karpenter not installed / no NodePools found"

echo ""
echo "=== Final: the actual scheduling failure reason ==="
kubectl describe pod "$POD" | grep -A5 "Events:"

echo ""
echo "Only after all five checks above are ruled out should a genuine"
echo "scheduler defect be considered (per Question 103)."
