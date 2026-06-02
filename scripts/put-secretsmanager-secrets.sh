#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-eu-west-1}"
SECRET_PREFIX="${SECRET_PREFIX:-/lobechat-final}"

if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then
  echo "OPENROUTER_API_KEY is required in the environment." >&2
  exit 1
fi

random_secret() {
  openssl rand -base64 32
}

ensure_secret() {
  local name="$1"
  local value="$2"
  local full_name="${SECRET_PREFIX}/${name}"

  if aws secretsmanager describe-secret --region "${AWS_REGION}" --secret-id "${full_name}" >/dev/null 2>&1; then
    return
  fi

  aws secretsmanager create-secret \
    --region "${AWS_REGION}" \
    --name "${full_name}" \
    --secret-string "${value}" >/dev/null
}

put_secret() {
  local name="$1"
  local value="$2"
  local full_name="${SECRET_PREFIX}/${name}"

  if aws secretsmanager describe-secret --region "${AWS_REGION}" --secret-id "${full_name}" >/dev/null 2>&1; then
    aws secretsmanager update-secret \
      --region "${AWS_REGION}" \
      --secret-id "${full_name}" \
      --secret-string "${value}" >/dev/null
    return
  fi

  aws secretsmanager create-secret \
    --region "${AWS_REGION}" \
    --name "${full_name}" \
    --secret-string "${value}" >/dev/null
}

ensure_secret key-vaults-secret "$(random_secret)"
ensure_secret next-auth-secret "$(random_secret)"
ensure_secret postgres-password "$(random_secret)"
ensure_secret minio-root-password "$(random_secret)"
ensure_secret mcphub-admin-password "$(random_secret)"
put_secret openrouter-api-key "${OPENROUTER_API_KEY}"

if [[ -n "${OPENAI_API_KEY:-}" ]]; then
  put_secret openai-api-key "${OPENAI_API_KEY}"
fi

if [[ -n "${OPENAPI_MCP_HEADERS:-}" ]]; then
  put_secret openapi-mcp-headers "${OPENAPI_MCP_HEADERS}"
fi

echo "Stored secrets under ${SECRET_PREFIX} in ${AWS_REGION}."
