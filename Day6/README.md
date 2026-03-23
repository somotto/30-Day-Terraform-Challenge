# Day 6: Understanding and Managing Terraform State

## Directory Structure

```
Day6/
├── main.tf          # Demo S3 bucket; backend block commented out for Phase 2
├── variables.tf     # region, bucket_name
├── outputs.tf       # bucket_name, bucket_arn
├── .gitignore       # Excludes state files and .terraform/ from Git
└── bootstrap/
    ├── main.tf      # S3 state bucket + versioning + encryption + DynamoDB lock table
    ├── variables.tf # region, state_bucket_name
    └── outputs.tf   # state_bucket_name, dynamodb_table_name
```

---

## Step 1: Deploy Demo Infrastructure and Inspect Local State

### Deploy

```bash
cd Day6/
terraform init
terraform apply -var="bucket_name=your-unique-demo-bucket-name"
terraform state list
```

### Inspect State

```bash
# List all resources Terraform is tracking
terraform state list

# Inspect full attributes of the S3 bucket
terraform state show aws_s3_bucket.demo
```

### Sample `terraform state list` output

```
aws_s3_bucket.demo
```

### Sample `terraform state show aws_s3_bucket.demo` output

```
# aws_s3_bucket.demo:
resource "aws_s3_bucket" "demo" {
    acceleration_status         = null
    arn                         = "arn:aws:s3:::day6-demo-bucket"
    bucket                      = "day6-demo-bucket"
    bucket_domain_name          = "day6-demo-bucket.s3.amazonaws.com"
    bucket_namespace            = "global"
    bucket_prefix               = null
    bucket_region               = "us-east-1"
    bucket_regional_domain_name = "day6-demo-bucket.s3.us-east-1.amazonaws.com"
    force_destroy               = false
    hosted_zone_id              = "Z3AQBSFYJSTF"
    id                          = "day6-demo-bucket"
    object_lock_enabled         = false
    policy                      = null
    region                      = "us-east-1"
    request_payer               = "BucketOwner"
    tags                        = {
        "Environment" = "learning"
        "Name"        = "day6-demo-bucket"
    }
    tags_all                    = {
        "Environment" = "learning"
        "Name"        = "day6-demo-bucket"
    }
    ...
}
```

### State File Observations

Opening `terraform.tfstate` reveals it is a JSON file containing:
- `version` — state file format version
- `terraform_version` — the Terraform CLI version that last wrote it
- `resources` — an array where each entry records:
  - `type` and `name` (e.g. `aws_s3_bucket`, `demo`)
  - `provider` — the provider that manages it
  - `instances[].attributes` — every single attribute AWS returned: ARN, bucket name, region, hosted zone ID, tags, etc.
  - `instances[].dependencies` — other resources this one depends on

What was surprising: Terraform stores far more than what you declared. Every attribute AWS returns — including ones you never set — is recorded. This is how Terraform detects drift: it compares the stored attributes against what AWS reports on the next plan.

After `terraform destroy`, the `resources` array becomes empty `[]` but the file still exists on disk.

---

## Step 2: Bootstrap Remote State Infrastructure

This solves the **bootstrap problem**: you cannot use Terraform to create the backend that Terraform itself needs. The solution is to apply the bootstrap module first with local state, then configure the backend in the root module.

```bash
cd Day6/bootstrap/
terraform init
terraform apply -var="state_bucket_name=your-unique-terraform-state-bucket"
```

This creates:
- An S3 bucket with versioning and AES-256 encryption
- A DynamoDB table `terraform-state-locks` for state locking

---

## Step 3: Configure Remote Backend

After bootstrap completes, edit `Day6/main.tf` and uncomment the `terraform` backend block:

```hcl
# terraform {
#   backend "s3" {
#     bucket         = "day6-demo-bucket"
#     key            = "global/s3/terraform.tfstate"
#     region         = "us-east-1"
#     dynamodb_table = "terraform-state-locks"
#     encrypt        = true
#   }
# }
```

**Every argument explained:**
- `bucket` — the S3 bucket name where state will be stored
- `key` — the object path inside the bucket; acts like a folder/filename
- `region` — must match the region where the S3 bucket was created
- `dynamodb_table` — the DynamoDB table Terraform uses to acquire a lock before writing state
- `encrypt` — ensures state is encrypted in transit (complements the bucket's server-side encryption)

---

## Step 4: Migrate State to Remote Backend

```bash
cd Day6/
terraform init -migrate-state
```

Terraform detects the new backend and prompts:

```
Initializing the backend...
Do you want to copy existing state to the new backend?
  Pre-existing state was found while migrating the previous "local" backend to the
  newly configured "s3" backend. No existing state was found in the newly configured
  "s3" backend. Do you want to copy this state to the new backend?
  Enter a value: yes

Successfully configured the backend "s3"! Terraform will automatically
use this backend unless the backend configuration changes.
```

After confirming, the state file appears in S3 at:
`s3://your-unique-terraform-state-bucket/global/s3/terraform.tfstate`

Verify in the AWS Console: S3 → your bucket → global/s3/ → terraform.tfstate (versioned, encrypted).

Run `terraform plan` — it should report **No changes**, confirming the migrated state matches live infrastructure.

---

## Step 5: State Locking Test

Open two terminals in `Day6/`.

**Terminal 1:**
```bash
terraform apply
```

**Terminal 2 (while Terminal 1 is running):**
```bash
terraform plan
```

**Error from Terminal 2:**
```
morty@morty:~/30-Day-Terraform-Challenge/Day6$ terraform plan
Acquiring state lock. This may take a few moments...
╷
│ Error: Error acquiring the state lock
│ 
│ Error message: operation error DynamoDB: PutItem, https response error
│ StatusCode: 400, RequestID:
│ DUTS4EVOH1II39316V8MKHQRSJVVO5AEMVJF66Q9ASUAAJG,
│ ConditionalCheckFailedException: The conditional request failed
│ Lock Info:
│   ID:        91c79107-9ac8-83e1-5361-fc393b03869c
│   Path:      day6-demo-bucket/global/s3/terraform.tfstate
│   Operation: OperationTypeApply
│   Who:       morty@morty
│   Version:   1.14.7
│   Created:   2026-03-23 20:38:35.24958657 +0000 UTC
│   Info:      
│ 
│ 
│ Terraform acquires a state lock to protect the state from being written
│ by multiple users at the same time. Please resolve the issue above and try
│ again. For most commands, you can disable locking with the "-lock=false"
│ flag, but this is not recommended.
╵
```

**Why this matters:** Without locking, two engineers running `terraform apply` simultaneously could both read the same state, make conflicting changes, and write back corrupted state — leaving your infrastructure in an unknown, broken condition. The DynamoDB lock table ensures only one operation writes state at a time.

---

## Chapter 3 Learnings

**Why should `terraform.tfstate` never be committed to Git?**
State files contain sensitive data in plaintext — database passwords, private keys, API tokens — because Terraform records every attribute AWS returns, including secrets. Committing state to Git exposes these secrets to anyone with repo access and in the commit history forever. Git also has no locking mechanism, so two people pushing state simultaneously will corrupt it.

**What is the bootstrap problem and how do you solve it?**
You cannot use Terraform to create the S3 bucket and DynamoDB table that Terraform needs as its backend — because Terraform needs the backend to exist before it can store state. The solution: apply the bootstrap module first using local state (no backend block), then configure the backend block in your root module and run `terraform init -migrate-state` to move the local state into S3.

**What does state locking prevent?**
State locking prevents two concurrent Terraform operations from reading and writing state simultaneously. Without it, a race condition can cause one operation to overwrite the other's changes, resulting in state that no longer matches real infrastructure — a very difficult situation to recover from.

**What does enabling versioning on the S3 bucket protect you from?**
Versioning keeps every previous version of the state file. If state gets corrupted, accidentally deleted, or a bad apply leaves things in a broken state, you can restore a previous known-good version from S3. It is your state file's undo history.

---

## Lab Takeaways

**Output values in state:** Outputs are stored in the state file under a top-level `outputs` key, separate from `resources`. They record the value, type, and whether the output is sensitive. Unlike resource attributes (which mirror every AWS attribute), outputs only store what you explicitly declared in `outputs.tf`. Terraform uses stored output values to share data between modules via `terraform_remote_state` data sources.

**Key practical skills gained:**
- Reading and interpreting a raw `terraform.tfstate` JSON file
- Using `terraform state list` and `terraform state show` for inspection
- Provisioning remote state infrastructure (bootstrap pattern)
- Configuring an S3 backend with DynamoDB locking
- Migrating local state to a remote backend with zero data loss
- Observing and understanding state lock errors in a team scenario
