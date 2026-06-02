#!/usr/bin/env bash
set -euo pipefail

LOCAL_ENV="deploy/.env.local"

if [[ ! -f "${LOCAL_ENV}" ]]; then
  echo "${LOCAL_ENV} is missing." >&2
  exit 1
fi

set -a
source "${LOCAL_ENV}"
set +a

AWS_REGION="${AWS_REGION:-eu-west-1}"
SECRET_PREFIX="${SECRET_PREFIX:-/lobechat-final}"

echo "This permanently deletes the LobeChat final-project secrets from AWS Secrets Manager."
read -r -p "Type DELETE-SECRETS to continue: " confirmation
if [[ "${confirmation}" != "DELETE-SECRETS" ]]; then
  echo "Secret deletion cancelled."
  exit 1
fi

for name in \
  key-vaults-secret \
  next-auth-secret \
  postgres-password \
  minio-root-password \
  mcphub-admin-password \
  openrouter-api-key \
  openapi-mcp-headers; do
  aws secretsmanager delete-secret \
    --region "${AWS_REGION}" \
    --secret-id "${SECRET_PREFIX}/${name}" \
    --force-delete-without-recovery >/dev/null 2>&1 || true
done

echo "Secrets Manager cleanup requested."
