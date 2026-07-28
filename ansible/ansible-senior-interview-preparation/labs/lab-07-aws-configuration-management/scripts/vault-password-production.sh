#!/bin/bash
# Same pattern as Lab 4 - dynamic vault password, never a committed plaintext file.
if [ -n "$LAB_VAULT_PW_PROD" ]; then
  echo "$LAB_VAULT_PW_PROD"
else
  echo "ERROR: LAB_VAULT_PW_PROD not set" >&2
  exit 1
fi
