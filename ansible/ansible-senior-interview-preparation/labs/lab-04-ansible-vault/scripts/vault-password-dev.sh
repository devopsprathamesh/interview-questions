#!/bin/bash
# Fetches the dev vault password dynamically - never a committed plaintext file.
# In production this would call: aws secretsmanager get-secret-value --secret-id ...
if [ -n "$LAB_VAULT_PW_DEV" ]; then
  echo "$LAB_VAULT_PW_DEV"
else
  echo "ERROR: LAB_VAULT_PW_DEV not set" >&2
  exit 1
fi
