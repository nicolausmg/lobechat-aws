#!/usr/bin/env bash
set -euo pipefail

LOCAL_ENV="deploy/.env.local"
PRIVATE_KEY="deploy/local/lobechat-final.pem"
PUBLIC_KEY="${PRIVATE_KEY}.pub"
TEMPLATE="deploy/cloudformation.yml"

if [[ ! -f "${LOCAL_ENV}" || ! -f "${PRIVATE_KEY}" || ! -f "${PUBLIC_KEY}" ]]; then
  echo "Run scripts/prepare-local-deploy.sh first." >&2
  exit 1
fi

set -a
source "${LOCAL_ENV}"
set +a

: "${AWS_PROFILE:?Set AWS_PROFILE in deploy/.env.local}"
: "${AWS_REGION:?Set AWS_REGION in deploy/.env.local}"
: "${STACK_NAME:?Set STACK_NAME in deploy/.env.local}"
: "${PROJECT_NAME:?Set PROJECT_NAME in deploy/.env.local}"
: "${INSTANCE_TYPE:?Set INSTANCE_TYPE in deploy/.env.local}"
: "${ROOT_VOLUME_SIZE:?Set ROOT_VOLUME_SIZE in deploy/.env.local}"
: "${ACME_EMAIL:?Set ACME_EMAIL in deploy/.env.local}"
: "${SECRET_BACKEND:?Set SECRET_BACKEND in deploy/.env.local}"
: "${OPENROUTER_API_KEY:?Set OPENROUTER_API_KEY in deploy/.env.local}"

MY_IP="${SSH_ALLOWED_IP:-$(curl -fsS https://checkip.amazonaws.com | tr -d '\n')}"
SSH_ALLOWED_CIDR="${MY_IP}/32"
SSH_PUBLIC_KEY="$(<"${PUBLIC_KEY}")"
UBUNTU_AMI="$(aws ec2 describe-images \
  --region "${AWS_REGION}" \
  --owners 099720109477 \
  --filters \
    Name=architecture,Values=x86_64 \
    Name=name,Values='ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*' \
    Name=root-device-type,Values=ebs \
    Name=state,Values=available \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
  --output text)"

if [[ -z "${UBUNTU_AMI}" || "${UBUNTU_AMI}" == "None" ]]; then
  echo "Could not resolve the latest Canonical Ubuntu 24.04 x86_64 gp3 AMI." >&2
  exit 1
fi

echo "This command creates paid AWS resources:"
echo "  - one ${INSTANCE_TYPE} EC2 instance"
echo "  - one ${ROOT_VOLUME_SIZE} GiB gp3 EBS root volume"
echo "  - one public IPv4 Elastic IP"
if [[ "${SECRET_BACKEND}" == "secretsmanager" ]]; then
  echo "  - Secrets Manager secrets"
else
  echo "  - local gitignored runtime secrets copied over SSH"
fi
echo
read -r -p "Type DEPLOY to continue: " confirmation
if [[ "${confirmation}" != "DEPLOY" ]]; then
  echo "Deployment cancelled."
  exit 1
fi

if [[ "${SECRET_BACKEND}" == "secretsmanager" ]]; then
  scripts/put-secretsmanager-secrets.sh
elif [[ "${SECRET_BACKEND}" != "local" ]]; then
  echo "SECRET_BACKEND must be secretsmanager or local." >&2
  exit 1
fi

aws cloudformation deploy \
  --template-file "${TEMPLATE}" \
  --stack-name "${STACK_NAME}" \
  --region "${AWS_REGION}" \
  --parameter-overrides \
    ProjectName="${PROJECT_NAME}" \
    UbuntuAmi="${UBUNTU_AMI}" \
    InstanceType="${INSTANCE_TYPE}" \
    RootVolumeSize="${ROOT_VOLUME_SIZE}" \
    SshAllowedCidr="${SSH_ALLOWED_CIDR}" \
    SshPublicKey="${SSH_PUBLIC_KEY}" \
  --tags Project="${PROJECT_NAME}"

PUBLIC_IP="$(aws cloudformation describe-stacks \
  --region "${AWS_REGION}" \
  --stack-name "${STACK_NAME}" \
  --query 'Stacks[0].Outputs[?OutputKey==`ElasticIp`].OutputValue' \
  --output text)"

APP_HOST="$(aws cloudformation describe-stacks \
  --region "${AWS_REGION}" \
  --stack-name "${STACK_NAME}" \
  --query 'Stacks[0].Outputs[?OutputKey==`AppHostname`].OutputValue' \
  --output text)"

echo "Waiting for SSH and cloud-init on ${PUBLIC_IP}..."
until ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 -i "${PRIVATE_KEY}" "ubuntu@${PUBLIC_IP}" \
  "test -f /var/lib/cloud/lobechat-bootstrap-complete"; do
  sleep 10
done

rsync -az \
  --exclude .env \
  --exclude .git \
  --exclude data \
  --exclude deploy/.env.local \
  --exclude deploy/local \
  -e "ssh -i ${PRIVATE_KEY}" \
  ./ "ubuntu@${PUBLIC_IP}:~/lobechat-aws/"

if [[ "${SECRET_BACKEND}" == "secretsmanager" ]]; then
  ACME_EMAIL="${ACME_EMAIL}" scripts/render-env-from-secretsmanager.sh "${APP_HOST}"
else
  ACME_EMAIL="${ACME_EMAIL}" scripts/render-env-local.sh "${APP_HOST}"
fi
scp -i "${PRIVATE_KEY}" .env "ubuntu@${PUBLIC_IP}:~/lobechat-aws/.env"
ssh -i "${PRIVATE_KEY}" "ubuntu@${PUBLIC_IP}" \
  "cd ~/lobechat-aws && scripts/start-aws-runtime.sh '${APP_HOST}'"

echo "Deployment started: https://${APP_HOST}"
