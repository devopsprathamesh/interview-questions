#!/bin/bash
# Diagnose which PodDisruptionBudget(s) are blocking a node drain.
set -euo pipefail

echo "=== All PodDisruptionBudgets and their current vs. desired healthy counts ==="
kubectl get pdb -A -o json | jq -r '
  .items[] |
  "\(.metadata.namespace)/\(.metadata.name): minAvailable=\(.spec.minAvailable // "n/a") maxUnavailable=\(.spec.maxUnavailable // "n/a") currentHealthy=\(.status.currentHealthy) desiredHealthy=\(.status.desiredHealthy) allowedDisruptions=\(.status.disruptionsAllowed)"
'

echo ""
echo "=== PDBs with ZERO allowed disruptions (these will block any eviction) ==="
kubectl get pdb -A -o json | jq -r '
  .items[] | select(.status.disruptionsAllowed == 0) |
  "\(.metadata.namespace)/\(.metadata.name) - BLOCKING"
'

echo ""
echo "=== Failed eviction events ==="
kubectl get events -A --field-selector reason=FailedEviction 2>/dev/null || echo "No FailedEviction events found (drain may still be in early stages)"
