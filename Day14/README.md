# Day 14: Working with Multiple Providers — Part 1

## What's implemented

Demonstrates Terraform's provider system in depth: how providers are installed, versioned, and configured — then applies that knowledge with multi-region deployments using provider aliases.

### Two scenarios demonstrated

**1. Multi-region S3 replication** (`live/multi-region/`)
- Primary bucket in `us-east-1` (default provider)
- Replica bucket in `us-west-2` (aliased provider)
- S3 replication rule configured between them via an IAM role
- Shows how `provider = aws.<alias>` routes API calls to the correct region

**2. Multi-account setup** (`live/multi-account/`)
- Two aliased providers each assuming a different IAM role in a different account
- Deploys an S3 bucket per account using `assume_role`
- If you don't have two accounts, `terraform plan` still shows the configuration intent

---

## Structure

```
Day14/
├── modules/
│   └── s3-bucket/              # Reusable S3 bucket module (provider-agnostic)
└── live/
    ├── multi-region/           # S3 replication across us-east-1 and us-west-2
    └── multi-account/          # S3 buckets across two AWS accounts via assume_role
```

---

## Usage

### Multi-region S3 replication

```bash
cd Day14/live/multi-region
terraform init
terraform apply
```

Verify replication is active:

```bash
# Upload a test object to the primary bucket
aws s3 cp /etc/hostname s3://$(terraform output -raw primary_bucket_name)/test.txt


aws s3 ls s3://$(terraform output -raw replica_bucket_name)/
```

---

### Multi-account

```bash
cd Day14/live/multi-account

# Export role ARNs for the two accounts
export TF_VAR_production_role_arn="arn:aws:iam::111111111111:role/TerraformDeployRole"
export TF_VAR_staging_role_arn="arn:aws:iam::222222222222:role/TerraformDeployRole"

terraform init
terraform plan   
terraform apply  
```

---

## Key concepts

### Provider installation (`terraform init`)

When you run `terraform init`, Terraform:
1. Reads the `required_providers` block
2. Resolves the version constraint against the Terraform Registry
3. Downloads the provider binary into `.terraform/providers/`
4. Records the exact version and checksums in `.terraform.lock.hcl`

### Version constraint operators

| Operator | Meaning |
|---|---|
| `= 5.0.0` | Exactly 5.0.0 — no flexibility |
| `>= 5.0` | Any version at or above 5.0 |
| `~> 5.0` | >= 5.0, < 6.0 (patch/minor updates only) |
| `~> 5.47` | >= 5.47, < 6.0 |
| `>= 5.0, < 6.0` | Explicit range — same as `~> 5.0` |

`~> 5.0` is the recommended pattern: you get bug fixes and new resources but no breaking major-version changes.

### The `.terraform.lock.hcl` file

Records the exact provider version selected plus cryptographic hashes of the binary. Commit this file — it ensures every team member and CI system uses the identical provider binary regardless of when they run `terraform init`.

### Provider aliases

A single provider block with no alias is the *default* provider for that type. Any additional block for the same provider type must have a unique `alias`. Resources reference the alias explicitly with `provider = aws.<alias>`. Resources that omit `provider` use the default.

### `assume_role` for multi-account

Each provider block can include an `assume_role` argument. Terraform calls `sts:AssumeRole` before making any API calls for that provider, so resources land in the target account without needing separate AWS credentials per account.