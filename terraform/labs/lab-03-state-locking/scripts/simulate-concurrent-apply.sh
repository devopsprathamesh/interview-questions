#!/usr/bin/env bash
# Launches two `terraform apply` runs against the SAME state, a few seconds apart,
# so the second one races the first one's held lock. Run from the lab-03 directory.
set -euo pipefail

echo "==> Launching first apply in the background (run_marker=A, ~45s artificial delay)..."
terraform apply -auto-approve -var="run_marker=A" > /tmp/lab03-run-a.log 2>&1 &
PID_A=$!

sleep 5
echo "==> First apply should now hold the lock. Launching second apply (run_marker=B)..."
set +e
terraform apply -auto-approve -var="run_marker=B" > /tmp/lab03-run-b.log 2>&1
RESULT_B=$?
set -e

echo ""
echo "==> Second apply exit code: ${RESULT_B} (non-zero is EXPECTED - it should fail on the lock)"
echo "==> Second apply output:"
grep -A3 "Error acquiring the state lock" /tmp/lab03-run-b.log || cat /tmp/lab03-run-b.log

echo ""
echo "==> Waiting for the first apply to finish..."
wait "${PID_A}"
echo "==> First apply completed. Its output:"
tail -20 /tmp/lab03-run-a.log

echo ""
echo "==> Now retry the second apply - it should succeed once the lock is released:"
echo "    terraform apply -auto-approve -var=run_marker=B"
