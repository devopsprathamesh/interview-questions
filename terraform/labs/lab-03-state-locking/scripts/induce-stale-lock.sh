#!/usr/bin/env bash
# Simulates a crashed process that never released its lock, then walks through
# the safe recovery procedure. Requires the lock table name (from Lab 2's bootstrap).
set -euo pipefail

TABLE="${1:?Usage: $0 <dynamodb-lock-table-name> <bucket-name>}"
BUCKET="${2:?Usage: $0 <dynamodb-lock-table-name> <bucket-name>}"
LOCK_PATH="${BUCKET}/lab-03/terraform.tfstate"
FAKE_LOCK_ID="simulated-crash-$(date +%s)"

echo "==> Inserting a fake, stale lock item (simulating a killed process)..."
aws dynamodb put-item --table-name "${TABLE}" --item '{
  "LockID": {"S": "'"${LOCK_PATH}"'"},
  "Info": {"S": "{\"ID\":\"'"${FAKE_LOCK_ID}"'\",\"Who\":\"simulated@crashed-runner\",\"Created\":\"2020-01-01T00:00:00Z\",\"Operation\":\"OperationTypeApply\"}"}
}'

echo "==> Attempting a plan - this should fail with a lock error:"
set +e
terraform plan 2>&1 | tee /tmp/lab03-lock-error.log
set -e

echo ""
echo "==> In a REAL incident, you would now confirm the 'Who' process is genuinely"
echo "    dead (check CI job status / process list) BEFORE force-unlocking."
echo "    In this drill, we know it's simulated, so:"
echo ""
echo "    terraform force-unlock ${FAKE_LOCK_ID}"
echo ""
echo "==> Run that command now, then re-run 'terraform plan' to confirm recovery."
