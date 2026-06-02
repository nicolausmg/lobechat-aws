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
LOCAL_ENV="deploy/.env.local"
RUNTIME_SECRETS="deploy/local/runtime-secrets.env"
AWS_REGION="${AWS_REGION:-eu-west-1}"
ACME_EMAIL="${ACME_EMAIL:-admin@example.com}"

if [[ ! -f "${LOCAL_ENV}" ]]; then
  echo "${LOCAL_ENV} is missing." >&2
  exit 1
fi

set -a
source "${LOCAL_ENV}"
set +a

if [[ ! -f "${RUNTIME_SECRETS}" ]]; then
  umask 077
  cat > "${RUNTIME_SECRETS}" <<EOF
KEY_VAULTS_SECRET=$(openssl rand -base64 32)
NEXT_AUTH_SECRET=$(openssl rand -base64 32)
POSTGRES_PASSWORD=$(openssl rand -base64 32)
MINIO_ROOT_PASSWORD=$(openssl rand -base64 32)
MCPHUB_ADMIN_PASSWORD=$(openssl rand -base64 32)
EOF
fi

set -a
source "${RUNTIME_SECRETS}"
set +a

cat > .env <<EOF
KEY_VAULTS_SECRET=${KEY_VAULTS_SECRET}
NEXT_AUTH_SECRET=${NEXT_AUTH_SECRET}

HOST_DOMAIN=${APP_HOST}
PUBLIC_APP_HOST=${APP_HOST}
PUBLIC_AUTH_HOST=auth.${APP_HOST}
PUBLIC_S3_HOST=s3.${APP_HOST}
PUBLIC_APP_URL=https://${APP_HOST}
PUBLIC_AUTH_URL=https://auth.${APP_HOST}
PUBLIC_S3_URL=https://s3.${APP_HOST}
ACME_EMAIL=${ACME_EMAIL}

LOBECHAT_PORT=47000
CASDOOR_PORT=47002
POSTGRES_PORT=47003
MINIO_PORT=47005
MINIO_CONSOLE_PORT=47006
VLLM_PORT=47007
MCPHUB_PORT=47008
QDRANT_PORT=47010
QDRANT_GRPC_PORT=47011
HAYHOOKS_PORT=47012
HAYHOOKS_MCP_PORT=47013

AUTH_CASDOOR_ID=a387a4892ee19b1a2249
AUTH_CASDOOR_SECRET=dbf205949d704de81b0b5b3603174e23fbecc354

S3_BUCKET=lobe
S3_ENDPOINT=http://minio:9000
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}

OPENROUTER_API_KEY=${OPENROUTER_API_KEY}
OPENAI_API_KEY=${OPENAI_API_KEY:-}
HF_TOKEN=
VLLM_MODEL_ID=oriolrius/myemoji-gemma-3-270m-it
VLLM_API_KEY=sk-local

MCPHUB_ADMIN_USER=admin
MCPHUB_ADMIN_PASSWORD=${MCPHUB_ADMIN_PASSWORD}
OPENAPI_MCP_HEADERS=${OPENAPI_MCP_HEADERS:-}

SSH_HOST=127.0.0.1
SSH_PORT=22
SSH_USERNAME=ubuntu
SSH_PRIVATE_KEY_FILE=/app/ssh/id_rsa
SSH_ALLOWED_COMMANDS=ls,cat,head,tail,grep,find,ps,df,du,uptime,whoami,pwd,echo,curl
SSH_ALLOWED_PATHS=/home,/tmp,/var/log
SSH_COMMANDS_BLACKLIST=rm,mv,dd,mkfs,fdisk,format,shutdown,reboot
SSH_ARGUMENTS_BLACKLIST=-rf,-fr,--force

AWS_REGION=${AWS_REGION}
AWS_DEFAULT_REGION=${AWS_REGION}
EOF

chmod 600 .env
echo "Rendered .env for https://${APP_HOST} from local gitignored runtime secrets."
