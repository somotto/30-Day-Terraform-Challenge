# Day 7 — Terraform State Isolation: Workspaces vs File Layouts

## What This Covers

Two approaches to isolating Terraform state across environments (dev / staging / production):

1. **Bootstrap** — creates the S3 bucket that all other modules use for remote state
2. **Workspaces** — single config directory, multiple state files in the same backend
3. **File Layouts** — separate directory per environment, each with its own backend config
4. **Remote State Data Source** — sharing outputs across independent state files

---

## Project Structure

```
Day7/
├── bootstrap/                # Run first — creates the S3 state bucket
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
│
├── workspaces/               # Approach 1: workspace-based isolation
│   ├── backend.tf            # single backend, workspaces prefix the key automatically
│   ├── main.tf               # uses terraform.workspace for conditional behaviour
│   ├── variables.tf
│   └── outputs.tf
│
└── environments/             # Approach 2: file layout isolation
    ├── dev/
    │   ├── backend.tf        # key = environments/dev/terraform.tfstate
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── staging/
    │   ├── backend.tf        # key = environments/staging/terraform.tfstate
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── production/
    │   ├── backend.tf        # key = environments/production/terraform.tfstate
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    └── app/                  # Demonstrates terraform_remote_state data source
        ├── backend.tf
        ├── main.tf           # reads vpc_id and subnet_id from env layer state
        ├── variables.tf
        └── outputs.tf
```

---

## Step 0 — Bootstrap (run once before anything else)

Day7 manages its own S3 bucket independently. The bootstrap module creates it with versioning and encryption enabled. S3 bucket names are globally unique — pick a name and use it consistently across all backend configs.

```bash
cd Day7/bootstrap
terraform init
terraform apply -var="state_bucket_name=day7-terraform-state-<your-unique-suffix>"
```

Once applied, the output will print the bucket name. That name is already set to `day7-terraform-state` as the default in all backend configs — update it if you used a different suffix.

---

## Approach 1 — Workspaces

### Setup

```bash
cd Day7/workspaces
terraform init

terraform workspace new dev
terraform workspace new staging
terraform workspace new production

terraform workspace list
#   default
# * dev
#   staging
#   production

terraform workspace select dev
terraform apply

terraform workspace select staging
terraform apply

terraform workspace select production
terraform apply
```

### How it works

`terraform.workspace` is a built-in string returning the active workspace name. The `instance_type` variable is a `map(string)` keyed by workspace — so each environment gets a different instance size from the same code:

```hcl
variable "instance_type" {
  type = map(string)
  default = {
    dev        = "t2.micro"
    staging    = "t2.small"
    production = "t2.medium"
  }
}

resource "aws_instance" "web" {
  instance_type = var.instance_type[terraform.workspace]
  tags = {
    Name        = "web-${terraform.workspace}"
    Environment = terraform.workspace
  }
}
```

### State file paths in S3

Terraform prefixes the backend key automatically per workspace:

| Workspace  | S3 Key                                         |
|------------|------------------------------------------------|
| dev        | `env:/dev/workspaces/terraform.tfstate`        |
| staging    | `env:/staging/workspaces/terraform.tfstate`    |
| production | `env:/production/workspaces/terraform.tfstate` |

---

## Approach 2 — File Layouts

Each environment is a completely independent Terraform root module with its own backend config pointing to a unique S3 key.

### Setup

```bash
cd Day7/environments/dev
terraform init
terraform apply

cd ../staging
terraform init
terraform apply

cd ../production
terraform init
terraform apply
```

### Backend key paths

```hcl
# dev/backend.tf
key = "environments/dev/terraform.tfstate"

# staging/backend.tf
key = "environments/staging/terraform.tfstate"

# production/backend.tf
key = "environments/production/terraform.tfstate"
```

Each key is unique — a `terraform destroy` in dev has zero effect on staging or production state.

---

## Remote State Data Source

The `app/` layer reads outputs from whichever environment's state you point it at, without duplicating resource definitions or hard-coding IDs.

```hcl
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "day7-terraform-state"
    key    = "environments/${var.environment}/terraform.tfstate"
    region = "us-east-1"
  }
}

resource "aws_instance" "app" {
  # subnet_id and vpc_id come directly from the env layer's outputs
  subnet_id              = data.terraform_remote_state.network.outputs.subnet_id
  vpc_security_group_ids = [aws_security_group.app_sg.id]
}
```

### Setup

Apply the env layer first, then the app layer:

```bash
cd Day7/environments/dev
terraform apply   # must exist before app layer can read its state

cd ../app
terraform init
terraform apply -var="environment=dev"
```

---

## Workspaces vs File Layouts — Comparison

| Concern                    | Workspaces                                    | File Layouts                                    |
|----------------------------|-----------------------------------------------|-------------------------------------------------|
| Code isolation             | None — all envs share the same `.tf` files    | Full — each env has its own directory           |
| Accidental wrong-env apply | High risk — easy to forget `workspace select` | Low risk — you must `cd` into the right dir     |
| Backend config duplication | None — one backend block                      | Repeated per environment                        |
| Different configs per env  | Awkward — requires conditionals everywhere    | Natural — just change the files                 |
| Team scale                 | Gets messy fast                               | Scales cleanly                                  |
| Production recommendation  | No                                            | Yes                                             |

**Recommendation:** Use file layouts for anything real. The extra directory overhead is worth the safety and explicitness. Workspaces are fine for short-lived experiments where you want to test the same config against a throwaway environment.

---

## State Locking

`use_lockfile = true` enables S3 native locking (replaces the deprecated `dynamodb_table` parameter). Each workspace and each file layout environment writes to a different S3 key, so each gets its own independent lock. A `terraform apply` in dev and staging can run concurrently without conflict.

---

## Chapter 3 Key Learnings

- `terraform_remote_state` solves the problem of sharing infrastructure outputs (VPC IDs, subnet IDs, etc.) between independent configurations without coupling them into a monolithic state file.
- It only exposes values declared as `output` blocks — if the upstream config doesn't output something, you can't read it.
- It creates a runtime dependency: if the upstream state doesn't exist yet, the apply fails. Always apply the network/env layer before the app layer.
- Workspaces were designed for testing, not for managing fundamentally different environments. File layouts are the production-grade pattern.

---

## Challenges

- Workspace naming collisions: resource names (e.g. security group names) must include `${terraform.workspace}` as a suffix to avoid conflicts when multiple workspaces share the same AWS account.
- `terraform init` must be run in each file layout directory before the first apply.
- The bootstrap bucket must exist before any other module can run `terraform init` — always run bootstrap first.
- `dynamodb_table` is deprecated in newer AWS provider versions; use `use_lockfile = true` instead.
