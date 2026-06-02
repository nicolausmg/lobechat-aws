#!/usr/bin/env bash
set -euo pipefail

LOCAL_ENV="deploy/.env.local"

if [[ ! -f "${LOCAL_ENV}" ]]; then
  echo "Run scripts/prepare-local-deploy.sh first." >&2
  exit 1
fi

read -r -s -p "OpenAI API key: " openai_api_key
echo

if [[ -z "${openai_api_key}" ]]; then
  echo "OpenAI API key cannot be empty." >&2
  exit 1
fi

awk -v key="${openai_api_key}" '
  BEGIN { updated = 0 }
  /^OPENAI_API_KEY=/ { print "OPENAI_API_KEY=" key; updated = 1; next }
  { print }
  END { if (!updated) print "OPENAI_API_KEY=" key }
' "${LOCAL_ENV}" > "${LOCAL_ENV}.tmp"

chmod 600 "${LOCAL_ENV}.tmp"
mv "${LOCAL_ENV}.tmp" "${LOCAL_ENV}"

echo "Stored the OpenAI API key in ${LOCAL_ENV}."
