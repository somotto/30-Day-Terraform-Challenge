# Day 13: Managing Secrets in Terraform

## What's implemented

Builds on Day 12 by adding proper secrets management. Secrets never appear in `.tf` files, are encrypted at rest, and are injected into instances at boot via IAM — not via Terraform state.

### Three approaches demonstrated

**1. AWS Secrets Manager** (`modules/secrets-manager`)
- Stores arbitrary JSON secrets (e.g. DB credentials) encrypted with KMS
- Instances retrieve secrets at runtime via the AWS SDK — the value never touches Terraform state
- Rotation-ready: `aws_secretsmanager_secret_rotation` stub included

**2. SSM Parameter Store** (`modules/ssm-parameter`)
- `SecureString` parameters encrypted with KMS
- Cheaper than Secrets Manager for simple key/value secrets
- Read by instances via `aws-ssm` at boot, or by other Terraform configs via `data "aws_ssm_parameter"`

**3. Passing secrets via environment variables** (live configs)
- `TF_VAR_db_password` — never written to disk, never in `.tf` files
- Shown in the dev live config as the escape hatch when you can't use a managed store

---

## Structure

```
Day13/
├── modules/
│   ├── secrets-manager/        # Secrets Manager secret + IAM policy
│   └── ssm-parameter/          # SSM SecureString + IAM policy
└── live/
    ├── dev/
    │   └── services/
    │       └── webserver-cluster/   # Extends Day12 dev — reads secret from SSM at boot
    └── production/
        └── services/
            └── webserver-cluster/   # Extends Day12 prod — reads secret from Secrets Manager at boot
```

---

## Usage

### Dev — SSM SecureString

Terraform creates an SSM SecureString parameter and an IAM policy, then wires the policy onto the instance role. The instance fetches the value at boot — the secret never appears in the plan or state.

```bash
cd Day13/live/dev/services/webserver-cluster
terraform init

# Set the secret via env var — never write it to a .tf file or .tfvars
export TF_VAR_db_password="dev-secret-123"

terraform apply
```

After `apply`, verify the instance fetched the secret:

```bash
# Check the SSM parameter was created
aws ssm get-parameter \
  --name "/webservers-dev/db_password" \
  --with-decryption \
  --query "Parameter.Value" \
  --output text

# Hit the ALB — the page shows the fetched secret value (demo only)
curl http://$(terraform output -raw alb_dns_name)
```

To rotate the secret without redeploying instances:

```bash
export TF_VAR_db_password="dev-secret-new"
terraform apply   # updates the SSM parameter only; instances pick it up on next boot
```

---

### Production — Secrets Manager

Terraform creates a Secrets Manager secret (JSON-encoded) and an IAM policy, then wires the policy onto the instance role. The instance fetches the value at boot using the secret ARN — the value never touches Terraform state.

```bash
cd Day13/live/production/services/webserver-cluster
terraform init

# Set the secret via env var
export TF_VAR_db_password="prod-secret-456"

terraform apply
```

After `apply`, verify the secret was created:

```bash
# Retrieve the secret value directly
aws secretsmanager get-secret-value \
  --secret-id "prod/webservers-prod/db_password" \
  --query "SecretString" \
  --output text

# Hit the ALB
curl http://$(terraform output -raw alb_dns_name)
```

To update the secret value:

```bash
export TF_VAR_db_password="prod-secret-new"
terraform apply   # updates the Secrets Manager version; instances pick it up on next boot
```

To tear down (note: Secrets Manager enforces a 7-day recovery window by default):

```bash
terraform destroy

# Force-delete the secret immediately if needed
aws secretsmanager delete-secret \
  --secret-id "prod/webservers-prod/db_password" \
  --force-delete-without-recovery
```

---

## Why not just use `variable` + `tfvars`?

| Approach | Secret in state? | Secret in plan? | Rotation support |
|---|---|---|---|
| `variable` in `.tf` | Yes (if passed to resource) | Yes | No |
| `TF_VAR_*` env var | Yes (if passed to resource) | Yes | No |
| SSM SecureString | No — read at runtime | No | Manual |
| Secrets Manager | No — read at runtime | No | Automatic |

The key insight: **inject the secret name/ARN into the instance, not the secret value**. The instance fetches the value itself using its IAM role.
