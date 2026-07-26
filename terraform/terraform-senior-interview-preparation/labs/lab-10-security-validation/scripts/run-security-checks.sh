#!/usr/bin/env bash
# Runs the full Lab 10 validation chain against a target directory.
# Usage: ./run-security-checks.sh ../insecure-fixture
set -euo pipefail

TARGET_DIR="${1:?Usage: $0 <directory>}"
FAILED=0

echo "== terraform fmt -check =="
terraform fmt -check -recursive "$TARGET_DIR" || FAILED=1

echo "== terraform validate =="
(cd "$TARGET_DIR" && terraform init -backend=false -input=false >/dev/null && terraform validate) || FAILED=1

echo "== tflint =="
tflint --chdir="$TARGET_DIR" --config="$(pwd)/.tflint.hcl" || FAILED=1

echo "== checkov =="
checkov -d "$TARGET_DIR" --compact || FAILED=1

echo "== secret scan (gitleaks) =="
gitleaks detect --source "$TARGET_DIR" --no-git -v || FAILED=1

if [ "$FAILED" -ne 0 ]; then
  echo ""
  echo "One or more checks failed. Fix the findings and re-run."
  exit 1
fi

echo ""
echo "All checks passed."
