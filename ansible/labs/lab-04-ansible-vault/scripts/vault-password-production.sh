#!/bin/bash
# Separate script, separate password, separate scope from dev - never shared.
if [ -n "$LAB_VAULT_PW_PROD" ]; then
  echo "$LAB_VAULT_PW_PROD"
else
  echo "ERROR: LAB_VAULT_PW_PROD not set" >&2
  exit 1
fi
