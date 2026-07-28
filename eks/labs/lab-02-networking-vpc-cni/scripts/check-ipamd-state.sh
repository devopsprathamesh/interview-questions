#!/bin/bash
# Diagnose CNI IP-allocation errors for stuck pods.
set -euo pipefail

echo "=== Pods NOT Running (candidates for CNI IP-exhaustion) ==="
kubectl get pods -A --field-selector=status.phase=Pending -o wide

echo "=== Events referencing IP allocation failures ==="
kubectl get events -A --field-selector=reason=FailedCreatePodSandBox 2>/dev/null || true
kubectl get events -A | grep -i "insufficient.*ip\|failed to assign an ip" || echo "No IP-exhaustion events found (yet)"

echo "=== aws-node current ENABLE_PREFIX_DELEGATION setting ==="
kubectl get daemonset aws-node -n kube-system -o jsonpath='{.spec.template.spec.containers[0].env}' | grep -o 'ENABLE_PREFIX_DELEGATION[^,}]*' || echo "not set"
