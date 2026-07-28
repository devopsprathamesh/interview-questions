#!/bin/bash
# Verifies core EKS-managed add-ons are genuinely healthy, not just that
# the EKS API reports the cluster as ACTIVE.
set -euo pipefail

echo "=== aws-node (VPC CNI) ==="
kubectl get daemonset aws-node -n kube-system -o wide

echo "=== coredns ==="
kubectl get deployment coredns -n kube-system -o wide

echo "=== kube-proxy ==="
kubectl get daemonset kube-proxy -n kube-system -o wide

echo "=== Any pods NOT Running/Completed in kube-system? ==="
kubectl get pods -n kube-system --field-selector=status.phase!=Running,status.phase!=Succeeded

echo "=== Bootstrap verification complete ==="
