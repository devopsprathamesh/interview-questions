#!/bin/bash
# Demonstrates metrics-server's complete lack of history (Question 79).
set -euo pipefail

echo "=== metrics-server: CURRENT values only ==="
kubectl top pods -A | head -5

echo ""
echo "=== Attempting to query metrics-server for historical data (will fail - it has none) ==="
kubectl get --raw "/apis/metrics.k8s.io/v1beta1/pods" | jq '.items[0]' 2>/dev/null || true
echo "Note: metrics-server's API has no time-range parameter at all - there is no"
echo "'an hour ago' to query. This is the exact gap Prometheus/Grafana closes."

echo ""
echo "=== Prometheus: genuine historical query ==="
echo "Example PromQL (run in Grafana or via port-forward to Prometheus):"
echo "  container_memory_working_set_bytes{pod=~\"latency-simulator.*\"}[1h]"
