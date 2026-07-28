#!/usr/bin/env bash
# State recovery procedure for the S3 backend built in this lab.
# Usage: ./state-recovery.sh <bucket-name> <state-key>
# Lists all versions of a state object and helps restore a specific one.
set -euo pipefail

BUCKET="${1:?Usage: $0 <bucket-name> <state-key>}"
KEY="${2:?Usage: $0 <bucket-name> <state-key>}"

echo "==> Listing all versions of s3://${BUCKET}/${KEY}"
aws s3api list-object-versions \
  --bucket "${BUCKET}" \
  --prefix "${KEY}" \
  --query 'Versions[].{VersionId:VersionId,LastModified:LastModified,IsLatest:IsLatest,Size:Size}' \
  --output table

echo ""
echo "==> To inspect a specific version before restoring, run:"
echo "    aws s3api get-object --bucket ${BUCKET} --key ${KEY} --version-id <VERSION_ID> /tmp/candidate.json"
echo "    python3 -m json.tool /tmp/candidate.json > /dev/null && echo 'valid JSON'"
echo "    python3 -c \"import json; print(json.load(open('/tmp/candidate.json'))['lineage'])\""
echo ""
echo "==> To restore a specific version as current (only after confirming it's correct):"
echo "    aws s3api copy-object --bucket ${BUCKET} \\"
echo "      --copy-source '${BUCKET}/${KEY}?versionId=<VERSION_ID>' \\"
echo "      --key ${KEY}"
echo ""
echo "==> Never restore a version without first confirming its lineage matches what"
echo "    this environment expects (see docs/state-management.md section on lineage)."
