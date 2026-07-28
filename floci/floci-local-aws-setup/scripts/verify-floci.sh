#!/usr/bin/env bash
# Smoke-tests a running Floci emulator: identity check, then an S3 round trip.
# Run after `source scripts/setup-floci-env.sh` (or after exporting the
# AWS_ENDPOINT_URL / AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_DEFAULT_REGION
# variables manually — see ../README.md#quickstart).
set -euo pipefail

: "${AWS_ENDPOINT_URL:?AWS_ENDPOINT_URL is not set — source scripts/setup-floci-env.sh first}"

echo "== Checking floci status =="
if command -v floci >/dev/null 2>&1; then
  floci status || true
fi

echo "== sts get-caller-identity against ${AWS_ENDPOINT_URL} =="
aws sts get-caller-identity --endpoint-url "${AWS_ENDPOINT_URL}"

bucket="floci-smoke-test-$$"

echo "== S3 round trip: mb / cp / ls / rb =="
aws s3 mb "s3://${bucket}" --endpoint-url "${AWS_ENDPOINT_URL}"
echo "hello from floci" > /tmp/floci-smoke-test.txt
aws s3 cp /tmp/floci-smoke-test.txt "s3://${bucket}/hello.txt" --endpoint-url "${AWS_ENDPOINT_URL}"
aws s3 ls "s3://${bucket}/" --endpoint-url "${AWS_ENDPOINT_URL}"
aws s3 rm "s3://${bucket}/hello.txt" --endpoint-url "${AWS_ENDPOINT_URL}"
aws s3 rb "s3://${bucket}" --endpoint-url "${AWS_ENDPOINT_URL}"
rm -f /tmp/floci-smoke-test.txt

echo "== Floci emulator looks reachable and S3-compatible =="
