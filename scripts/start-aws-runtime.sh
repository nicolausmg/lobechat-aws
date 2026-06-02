#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <app-hostname>"
  echo "Example: $0 1-2-3-4.sslip.io"
}

if [[ $# -ne 1 ]]; then
  usage
  exit 1
fi

APP_HOST="$1"
PUBLIC_APP_URL="https://${APP_HOST}"
PUBLIC_AUTH_URL="https://auth.${APP_HOST}"

if [[ ! -f .env ]]; then
  echo ".env is missing. Render it from Secrets Manager before starting." >&2
  exit 1
fi

jq \
  --arg app_url "${PUBLIC_APP_URL}" \
  --arg auth_url "${PUBLIC_AUTH_URL}" \
  '(.applications[] | select(.name == "lobechat")) |=
    (.redirectUris = [$app_url + "/api/auth/callback/casdoor"] | .origin = $auth_url)' \
  config/init_data.json > config/init_data.json.tmp
mv config/init_data.json.tmp config/init_data.json

sed -i.bak -E "s#^origin = .*#origin = ${PUBLIC_AUTH_URL}#" config/casdoor-app.conf

docker compose --profile proxy up -d --build
scripts/connect-minio-mcp.sh

echo "LobeChat: ${PUBLIC_APP_URL}"
echo "Casdoor: ${PUBLIC_AUTH_URL}"
