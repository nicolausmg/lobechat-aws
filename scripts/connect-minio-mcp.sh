#!/usr/bin/env bash
set -euo pipefail

MCPHUB_URL=${MCPHUB_URL:-http://127.0.0.1:47008}
MCPHUB_USERNAME=${MCPHUB_USERNAME:-admin}
MCPHUB_PASSWORD=${MCPHUB_PASSWORD:-admin123}
MCP_ENDPOINT="${MCPHUB_URL}/mcp/pickstar-2002-minio-mcp"

if [[ ! -f .env ]]; then
  echo ".env is missing. Render it before connecting the MinIO MCP server." >&2
  exit 1
fi

set -a
source .env
set +a
: "${MINIO_ROOT_USER:?MINIO_ROOT_USER is required}"
: "${MINIO_ROOT_PASSWORD:?MINIO_ROOT_PASSWORD is required}"

tmp_dir=$(mktemp -d)
trap 'rm -rf "${tmp_dir}"' EXIT

for _ in $(seq 1 24); do
  if curl -fsS --max-time 5 "${MCPHUB_URL}/health" >/dev/null; then
    break
  fi
  sleep 5
done

token=$(
  curl -fsS -X POST "${MCPHUB_URL}/api/auth/login" \
    -H 'Content-Type: application/json' \
    -d "{\"username\":\"${MCPHUB_USERNAME}\",\"password\":\"${MCPHUB_PASSWORD}\"}" |
    jq -er '.token'
)

for _ in $(seq 1 24); do
  if curl -fsS -H "x-auth-token: ${token}" "${MCPHUB_URL}/api/servers" |
    jq -e '.data[] | select(.name == "pickstar-2002-minio-mcp") | .status == "connected"' >/dev/null; then
    break
  fi
  sleep 5
done
curl -fsS -H "x-auth-token: ${token}" "${MCPHUB_URL}/api/servers" |
  jq -e '.data[] | select(.name == "pickstar-2002-minio-mcp") | .status == "connected"' >/dev/null

curl -fsSN -D "${tmp_dir}/headers" -o /dev/null -X POST "${MCP_ENDPOINT}" \
  -H "Authorization: Bearer ${token}" \
  -H 'Accept: application/json, text/event-stream' \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"minio-connect","version":"1"}}}'
session_id=$(awk 'tolower($1)=="mcp-session-id:" {gsub("\r", "", $2); print $2}' "${tmp_dir}/headers")
: "${session_id:?MCPHub did not return an MCP session ID}"

curl -fsS -o /dev/null -X POST "${MCP_ENDPOINT}" \
  -H "Authorization: Bearer ${token}" \
  -H 'Accept: application/json, text/event-stream' \
  -H 'Content-Type: application/json' \
  -H "mcp-session-id: ${session_id}" \
  -d '{"jsonrpc":"2.0","method":"notifications/initialized"}'

payload=$(
  jq -cn \
    --arg user "${MINIO_ROOT_USER}" \
    --arg password "${MINIO_ROOT_PASSWORD}" \
    '{jsonrpc:"2.0",id:2,method:"tools/call",params:{name:"pickstar-2002-minio-mcp-connect_minio",arguments:{endPoint:"minio",port:9000,accessKey:$user,secretKey:$password}}}'
)
curl -fsSN -X POST "${MCP_ENDPOINT}" \
  -H "Authorization: Bearer ${token}" \
  -H 'Accept: application/json, text/event-stream' \
  -H 'Content-Type: application/json' \
  -H "mcp-session-id: ${session_id}" \
  -d "${payload}" |
  sed -n 's/^data: //p' |
  jq -e '.result | select(.isError != true)' >/dev/null

echo "MinIO MCP connected."
