#!/bin/bash
# Generates traffic where 95% of requests are fast and 5% are severely slow -
# the exact pattern that P50 masks but P99 reveals (Question 83).
set -euo pipefail

SVC="http://latency-simulator.default.svc.cluster.local"

for i in $(seq 1 200); do
  if (( i % 20 == 0 )); then
    # 5% of requests: severely slow (simulated 5-second delay)
    kubectl run "load-slow-$i" --rm -i --restart=Never --image=curlimages/curl -- \
      curl -s -o /dev/null "$SVC/delay/5" &
  else
    # 95% of requests: fast
    kubectl run "load-fast-$i" --rm -i --restart=Never --image=curlimages/curl -- \
      curl -s -o /dev/null "$SVC/delay/0" &
  fi
  sleep 0.1
done
wait
echo "Load generation complete - query P50 vs P99 in Prometheus/Grafana now"
