#!/bin/bash
# Dynamic vault password fetch - never a committed plaintext file (Lab 4 pattern).
if [ -n "$LAB_VAULT_PW_PROD" ]; then
  echo "$LAB_VAULT_PW_PROD"
else
  echo "ERROR: LAB_VAULT_PW_PROD not set" >&2
  exit 1
fi
