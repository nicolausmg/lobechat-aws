#!/usr/bin/env bash
set -euo pipefail

LOCAL_ENV="deploy/.env.local"

if [[ ! -f "${LOCAL_ENV}" ]]; then
  echo "Run scripts/prepare-local-deploy.sh first." >&2
  exit 1
fi

read -r -s -p "OpenRouter API key: " openrouter_api_key
echo

if [[ -z "${openrouter_api_key}" ]]; then
  echo "OpenRouter API key cannot be empty." >&2
  exit 1
fi

awk -v key="${openrouter_api_key}" '
  /^OPENROUTER_API_KEY=/ { print "OPENROUTER_API_KEY=" key; next }
  { print }
' "${LOCAL_ENV}" > "${LOCAL_ENV}.tmp"

chmod 600 "${LOCAL_ENV}.tmp"
mv "${LOCAL_ENV}.tmp" "${LOCAL_ENV}"

echo "Stored the OpenRouter API key in ${LOCAL_ENV}."
