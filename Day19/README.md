# Day 19: Adopting Infrastructure as Code in Your Team

Day 19 focuses on Terraform Cloud, Terraform Enterprise workspace management via
the `tfe` provider, and importing existing manually-created resources into Terraform state.

---

## Directory Structure

```
Day19/
├── labs/
│   ├── lab1-terraform-cloud/
│   │   └── main.tf        # S3 bucket + SSM parameter with local backend
│   ├── lab2-terraform-enterprise/
│   │   └── main.tf        # Workspace + variable set management via tfe provider
│   └── lab3-import-practice/
│       └── main.tf        # Importing a manually-created S3 bucket into state
├── .gitignore
└── README.md
```

---

## Lab 1: Terraform Cloud concepts (local backend)

This lab provisions an S3 bucket and SSM parameter to demonstrate what resources
managed by Terraform look like. The `cloud` block is shown as a comment, in a
real team setup you would uncomment it and point it at your Terraform Cloud org
instead of using a local backend.

```bash
cd Day19/labs/lab1-terraform-cloud
terraform init
terraform plan
terraform apply
terraform destroy
```

To use Terraform Cloud instead of the local backend, uncomment the `cloud` block
in `main.tf`, create a free account at https://app.terraform.io, and run
`terraform login` before `terraform init`.

---

## Lab 2: Workspace management via the tfe provider

The `tfe` provider lets you manage Terraform Cloud/Enterprise resources as
Terraform code - workspaces, variable sets, teams. This is "meta-Terraform":
Terraform managing Terraform.

Requires a `TFE_TOKEN` environment variable (Terraform Cloud API token).

```bash
export TFE_TOKEN="your-api-token"
cd Day19/labs/lab2-terraform-enterprise
# update var.tfe_organization in main.tf to your org name
terraform init
terraform plan
terraform apply
terraform destroy
```

This creates two workspaces (`day19-webserver-dev`, `day19-webserver-production`)
and a shared variable set in your Terraform Cloud organisation.

---

## Lab 3: terraform import

Simulates bringing a manually-created S3 bucket under Terraform management
without destroying it.

```bash
# Create the "pre-existing" bucket
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="day19-import-practice-${ACCOUNT_ID}-us-east-1"

aws s3api create-bucket --bucket $BUCKET_NAME --region us-east-1
aws s3api put-bucket-tagging \
  --bucket $BUCKET_NAME \
  --tagging 'TagSet=[{Key=CreatedBy,Value=manual},{Key=Environment,Value=dev}]'

#  Update var.bucket_name default in main.tf to $BUCKET_NAME

cd Day19/labs/lab3-import-practice
terraform init

#  Plan before import 
terraform plan

#  Import the existing bucket
terraform import aws_s3_bucket.existing_logs $BUCKET_NAME

#  Plan after import — should show only tag updates, no recreation
terraform plan

#  Apply and verify no drift
terraform apply -auto-approve
terraform plan  # should return no changes

#  Cleanup
terraform destroy
```

Terraform 1.5+ alternative - use the declarative `import` block in `main.tf`
instead of the CLI command (already shown as a comment in the file).

---

## CI Pipeline

The GitHub Actions workflow at `.github/workflows/terraform-adoption.yml` runs
on any change to `Day19/**`:

- PR: `fmt check` → `validate` → `plan` (posted as a PR comment)
- Merge to main: `apply` → post-apply drift check

Required secrets: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`.

---

## Business Case

| Problem | IaC Solution | Outcome |
|---|---|---|
| Manual errors in infrastructure | Code review and Terraform plans | Reduced incidents |
| Slow environment setup | Reusable Terraform configs | Provisioning reduced from hours to minutes |
| Lack of audit trail | Git-based version control | Full change history |
| Environment inconsistency | Same configs across environments | Fewer deployment issues |
| Difficult onboarding | Documented infrastructure | Faster onboarding |

---

## terraform import Practice

Command used:

```bash
terraform import aws_s3_bucket.monitoring_dashboard mohamud-day19-monitoring-dashboard-2026-9f3a2c
```

Resource block:

```hcl
resource "aws_s3_bucket" "monitoring_dashboard" {
  bucket = "mohamud-day19-monitoring-dashboard-2026-9f3a2c"
}
```

`terraform plan` result after import:

```
No changes. Your infrastructure matches the configuration.
```

---

## Terraform Cloud Lab Takeaways

The key insight from this lab is what Terraform Cloud adds on top of a plain S3
backend. With S3, state is stored remotely but everything else - running plans,
applying changes, seeing what happened - still lives on whoever's laptop ran the
command. Terraform Cloud shifts all of that to a shared, auditable place.

The most practically useful additions are:

- Every run has a URL. A teammate or manager can see exactly what changed without
  needing AWS credentials or Terraform installed locally.
- State is versioned with diffs - you can see what the infrastructure looked like
  before and after any apply.
- Access control is workspace-level, not "whoever has the AWS keys."
- The `tfe` provider (lab 2) takes this further - you can manage workspaces,
  variable sets, and teams as Terraform code itself, which means your Terraform
  setup is also version-controlled and reviewable.

---

## Chapter 10 Learnings

The author's core argument is that IaC adoption fails when teams treat it as a
migration project rather than a habit change. A "big bang" migration — stop
everything, convert all infrastructure to Terraform, then resume — almost always
stalls because it requires pausing product work, creates a high-risk moment, and
asks the team to trust a tool they have no experience with.

The prescription is to start with something new, not something existing. One new
S3 bucket, one PR, one successful apply. That builds the muscle memory and the
trust before anything critical is touched.

The incremental approach also has a political advantage - it's impossible to
object to using Terraform for a resource that doesn't exist yet. There's nothing
to break.

---

## Challenges

The technical side of IaC adoption is the easy part after a few days of practice.
The hard part is changing how a team thinks about infrastructure changes.

The specific resistance usually sounds like: "infrastructure is different, it's
riskier, it needs to be done carefully by experienced people." That belief is
understandable but it's backwards - the risk comes from lack of review, not from
automation. A `terraform plan` reviewed in a PR by two people is safer than one
experienced engineer clicking through the console alone, because the console has
no diff, no review, and no rollback.

The way to change that belief is not to argue against it - it's to demonstrate
the alternative working correctly, repeatedly, on low-stakes resources first. By
the time the team has watched 20 successful automated applies, the resistance is
gone because the evidence has replaced it.
