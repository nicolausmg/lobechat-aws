# AWS Deployment

The practical deployment uses one CloudFormation stack and a local, gitignored
configuration file. The stack creates a dedicated VPC, public subnet, internet
gateway, routes, security group, EC2 key pair, Ubuntu 24.04 EC2 instance,
encrypted gp3 root volume, and Elastic IP.

The preferred Ubuntu lookup is Canonical's public SSM parameter. The course
sandbox role currently denies `ssm:GetParameters`, including public parameters.
The deployment wrapper therefore resolves the latest Ubuntu 24.04 x86_64 gp3
AMI at runtime with `ec2:DescribeImages`, restricted to Canonical's official
owner ID, and passes that value into CloudFormation. No AMI ID is hardcoded.

The preferred path creates secrets in AWS Secrets Manager immediately before
stack deployment. The course sandbox role may deny both Secrets Manager and SSM
writes. In that case, set `SECRET_BACKEND=local`: generated runtime secrets stay
in the gitignored `deploy/local/` directory and the rendered `.env` file is
copied to the EC2 instance over SSH.

## Prepare locally

```bash
scripts/prepare-local-deploy.sh
scripts/set-openrouter-key.sh
scripts/set-openai-key.sh
```

Review `deploy/.env.local`, then validate the template:

```bash
scripts/validate-cloudformation.sh
```

## Deploy

This creates paid AWS resources and requires an explicit `DEPLOY` confirmation:

```bash
scripts/deploy-cloudformation.sh
```

After the first Casdoor login, register the evidence-chat MCP plugins for the
new LobeChat user:

```bash
scripts/register-mcp-plugin.sh
MCP_SERVER=playwright PLUGIN_IDENTIFIER=mcphub-playwright scripts/register-mcp-plugin.sh
MCP_SERVER=pickstar-2002-minio-mcp PLUGIN_IDENTIFIER=mcphub-minio scripts/register-mcp-plugin.sh
```

## Delete the stack

This deletes the EC2 instance, EBS volume, Elastic IP, and networking resources.
Secrets Manager secrets are intentionally retained until they are reviewed:

```bash
scripts/delete-cloudformation.sh
```

After review, remove the retained secrets with a separate explicit confirmation:

```bash
scripts/delete-secretsmanager-secrets.sh
```
