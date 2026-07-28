#!/bin/bash
# Simulates a post-admission compromise: exec a shell inside an already-
# legitimately-running, admission-approved pod - something Pod Security
# Admission has no visibility into at all, since the pod already passed
# admission before this happens.
set -euo pipefail

echo "=== Simulating shell exec inside the hardened pod (post-admission compromise) ==="
kubectl exec -n restricted-test pod-hardened -- sh -c 'echo "simulated compromise - shell active"' || true

echo ""
echo "=== Check Falco logs for the detection (may take a few seconds) ==="
sleep 5
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=50 | grep -i "shell spawned" || \
  echo "No detection yet - Falco may still be initializing, or the custom rule needs tuning"
