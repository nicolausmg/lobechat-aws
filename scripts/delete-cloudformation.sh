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

: "${AWS_PROFILE:?Set AWS_PROFILE in deploy/.env.local}"
: "${AWS_REGION:?Set AWS_REGION in deploy/.env.local}"
: "${STACK_NAME:?Set STACK_NAME in deploy/.env.local}"

echo "This deletes the CloudFormation stack ${STACK_NAME} and its EC2, EBS, and Elastic IP resources."
read -r -p "Type DELETE to continue: " confirmation
if [[ "${confirmation}" != "DELETE" ]]; then
  echo "Deletion cancelled."
  exit 1
fi

aws cloudformation delete-stack --region "${AWS_REGION}" --stack-name "${STACK_NAME}"
echo "Stack deletion requested. Secrets Manager secrets are retained for deliberate cleanup."
