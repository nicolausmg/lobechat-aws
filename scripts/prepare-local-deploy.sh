#!/usr/bin/env bash
set -euo pipefail

LOCAL_DIR="deploy/local"
PRIVATE_KEY="${LOCAL_DIR}/lobechat-final.pem"
PUBLIC_KEY="${PRIVATE_KEY}.pub"

mkdir -p "${LOCAL_DIR}"
chmod 700 "${LOCAL_DIR}"

if [[ ! -f deploy/.env.local ]]; then
  cp deploy/.env.local.example deploy/.env.local
  chmod 600 deploy/.env.local
  echo "Created deploy/.env.local. Add the deployment settings before running deploy-cloudformation.sh."
fi

if [[ ! -f "${PRIVATE_KEY}" ]]; then
  ssh-keygen -q -t ed25519 -N "" -C "lobechat-final" -f "${PRIVATE_KEY}"
  chmod 600 "${PRIVATE_KEY}"
  echo "Created deployment SSH key at ${PRIVATE_KEY}."
fi

echo "Local deployment files are ready."
