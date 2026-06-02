#!/usr/bin/env bash
set -euo pipefail

AWS_PROFILE="${AWS_PROFILE:-final-project}"
AWS_REGION="${AWS_REGION:-eu-west-1}"

aws cloudformation validate-template \
  --profile "${AWS_PROFILE}" \
  --region "${AWS_REGION}" \
  --template-body file://deploy/cloudformation.yml >/dev/null

echo "CloudFormation template is valid."
