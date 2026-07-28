#!/usr/bin/env bash
# Simulates manual, out-of-band drift against Lab 1's S3 bucket by changing a
# tag directly via the AWS CLI, bypassing Terraform entirely.
# Usage: ./simulate-drift.sh <bucket-name>
set -euo pipefail

BUCKET="${1:?Usage: $0 <bucket-name>}"

echo "Current tags:"
aws s3api get-bucket-tagging --bucket "$BUCKET" 2>/dev/null || echo "(none)"

echo ""
echo "Applying an out-of-band tag change (simulating a manual console edit)..."
aws s3api put-bucket-tagging --bucket "$BUCKET" --tagging '{
  "TagSet": [
    {"Key": "Environment", "Value": "MANUALLY-CHANGED-OUTSIDE-TERRAFORM"},
    {"Key": "Project", "Value": "tf-core-lab"}
  ]
}'

echo ""
echo "Drift injected. Now run: terraform plan"
echo "Expect it to show the Environment tag reverting to its configured value."
echo "See docs/state-management.md section 11 for the full decision framework"
echo "(revert / adopt-into-config / ignore / import) before deciding what to do."
