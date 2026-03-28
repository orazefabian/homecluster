#!/bin/bash
set -euo pipefail

# Create the headplane-cookie-secret Kubernetes Secret.
#
# The cookie_secret must be exactly 32 characters.
# `openssl rand -base64 24` produces exactly 32 base64 characters (24 bytes * 4/3 = 32, no padding).
#
# If you previously created the secret with `openssl rand -hex 32` (which produces 64 characters),
# run this script to recreate the secret with the correct length.

NAMESPACE="halo"
SECRET_NAME="headplane-cookie-secret"

# Write the secret to a temp file to avoid exposing it in process listings (ps).
TMPFILE=$(mktemp)
chmod 600 "${TMPFILE}"
trap 'rm -f "${TMPFILE}"' EXIT

openssl rand -base64 24 > "${TMPFILE}"

kubectl create secret generic "${SECRET_NAME}" \
  --namespace="${NAMESPACE}" \
  --from-file=cookie-secret="${TMPFILE}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Secret '${SECRET_NAME}' created/updated in namespace '${NAMESPACE}' with a 32-character cookie secret."
