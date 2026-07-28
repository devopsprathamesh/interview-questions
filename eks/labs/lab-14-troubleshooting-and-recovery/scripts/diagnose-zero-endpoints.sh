#!/bin/bash
set -euo pipefail
SVC=${1:-zero-endpoint-service}

echo "=== Endpoints for $SVC ==="
kubectl get endpoints "$SVC"

echo ""
echo "=== Service selector ==="
kubectl get service "$SVC" -o jsonpath='{.spec.selector}'
echo ""

echo ""
echo "=== Actual pod labels in the namespace ==="
kubectl get pods --show-labels

echo ""
echo "=== Diagnosis: compare the selector above against actual pod labels for a mismatch ==="
