#!/usr/bin/env bash
# Starts Floci and exports the local AWS environment into the current shell.
# Must be sourced, not executed, so the exported variables survive:
#   source scripts/setup-floci-env.sh
set -euo pipefail

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "This script must be sourced, not executed:" >&2
  echo "  source scripts/setup-floci-env.sh" >&2
  exit 1
fi

if ! command -v floci >/dev/null 2>&1; then
  echo "floci CLI not found. Install it first — see ../README.md#install" >&2
  return 1
fi

floci start

eval "$(floci env)"

echo "Floci environment exported:"
echo "  AWS_ENDPOINT_URL=${AWS_ENDPOINT_URL:-<not set>}"
echo "  AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-<not set>}"
echo "Run ./scripts/verify-floci.sh to confirm the emulator answers requests."
