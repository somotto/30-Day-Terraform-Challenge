# Day 17 — Manual Testing of Terraform Code

## What You Will Accomplish Today

Testing is what separates engineers who hope their infrastructure works from engineers
who know it does. Day 17 covers Chapter 9's first layer: manual testing. Before writing
automated tests you need to know exactly what you are testing, why, and how to verify it.
This day builds a structured manual testing process for the webserver cluster from Days 3–16,
documents every finding, and establishes the cleanup discipline that prevents runaway AWS costs.

---

## Directory Structure

```
Day17/
├── scripts/
│   ├── 01-init-validate.sh        # terraform init + validate across all environments
│   ├── 02-plan-check.sh           # terraform plan with resource count assertions
│   ├── 03-functional-verify.sh    # ALB, HTTP, target health, ASG, alarms, tags
│   ├── 04-state-consistency.sh    # No-changes plan + state list cross-check
│   ├── 05-regression-check.sh     # Small change → plan diff → apply → clean plan
│   ├── 06-asg-self-healing.sh     # Terminate instance → verify ASG replaces it
│   └── 07-cleanup-verify.sh       # terraform destroy + post-destroy AWS verification
├── labs/
│   ├── lab1-state-migration/
│   │   ├── main.tf                # SSM parameter resource for migration demo
│   │   └── migration-steps.sh     # Annotated walkthrough: local → S3 backend
│   └── lab2-import/
│       ├── main.tf                # S3 bucket config for import target
│       └── existing-resource.sh   # Creates bucket via CLI, then imports it
├── checklist/
│   └── manual-test-checklist.md   # Structured checklist: 7 categories, 60+ items
├── results/                       # Created at runtime by scripts (gitignored)
├── .gitignore
└── README.md
```

---

## How to Run the Tests

### Prerequisites

```bash
# Verify tools
terraform version          # >= 1.0
aws sts get-caller-identity
curl --version
host --version

# Set required env var
export TF_VAR_db_password="your-test-password"

# Make scripts executable
chmod +x Day17/scripts/*.sh
chmod +x Day17/labs/**/*.sh
```

### Run the full manual test suite

```bash
# 1. Init and validate all environments
bash Day17/scripts/01-init-validate.sh

# 2. Plan check (dev)
bash Day17/scripts/02-plan-check.sh dev

# 3. Deploy dev (run manually — not scripted to avoid accidental deploys)
cd Day16/live/dev/services/webserver-cluster
terraform apply

# 4. Functional verification
bash Day17/scripts/03-functional-verify.sh dev

# 5. State consistency
bash Day17/scripts/04-state-consistency.sh dev

# 6. Regression check
bash Day17/scripts/05-regression-check.sh dev

# 7. ASG self-healing
bash Day17/scripts/06-asg-self-healing.sh dev

# 8. Cleanup
bash Day17/scripts/07-cleanup-verify.sh dev
```

---

## Manual Test Checklist

The full checklist lives in `checklist/manual-test-checklist.md`. It is organised into
seven categories and is designed to be handed to any engineer without prior context.

### Category 1: Provisioning Verification

Covers `terraform init`, `terraform validate`, `terraform plan`, and `terraform apply`
across the module, dev, and production environments.

Key checks:
- `terraform init` completes without errors in all three directories
- `terraform validate` passes cleanly (no syntax or reference errors)
- `terraform plan` shows the expected number of resources to add and zero to destroy
- `terraform apply` completes without errors

### Category 2: Resource Correctness

Verifies that what Terraform created in AWS matches what the configuration specifies.

Key checks:
- ALB, ASG, and target group are visible in the AWS Console with correct names
- ALB security group allows port 80 from `0.0.0.0/0`; instance security group allows
  traffic only from the ALB security group (no direct internet access)
- All resources carry the five standard tags: `Environment`, `ManagedBy`, `Project`,
  `Owner`, `Cluster`
- Instance type matches the variable: `t3.micro` in dev, `t3.small` in production
- CloudWatch log group exists with correct retention: 7 days (dev), 90 days (production)
- Three CloudWatch alarms exist per cluster: `high-cpu`, `unhealthy-hosts`, `alb-5xx`

### Category 3: Functional Verification

Verifies the deployed infrastructure actually works end-to-end.

Key checks:
- ALB DNS name is available as a Terraform output
- DNS resolves to one or more IP addresses
- `curl http://<alb-dns>` returns HTTP 200
- Response body contains "Hello World" and the cluster name
- All target group targets show `State = healthy`
- ASG running instance count matches desired capacity
- Terminating one instance manually triggers ASG replacement within 5 minutes
- ALB continues serving HTTP 200 during instance replacement

### Category 4: State Consistency

Verifies the Terraform state file accurately reflects what exists in AWS.

Key checks:
- `terraform plan -detailed-exitcode` returns exit code 0 (no changes) immediately
  after a fresh apply
- `terraform state list` shows all expected resources
- State file is stored in S3, not locally
- DynamoDB lock table exists and is ACTIVE
- EC2 instance count in AWS matches what is tracked in state

### Category 5: Regression Check

Verifies that a small, intentional change produces only the expected diff.

Key checks:
- Adding `RegressionTest = "day17"` to `custom_tags` shows only tag updates in plan
- No resource replacements appear in the plan (tags should never force replacement)
- Apply succeeds
- Plan is clean (exit code 0) after applying the tag change
- Reverting the tag shows only that revert in the next plan

### Category 6: Multi-Environment Comparison

Runs both dev and production and documents intentional vs unexpected differences.

| Attribute | Dev | Production | Intentional? |
|-----------|-----|------------|--------------|
| Instance type | `t3.micro` | `t3.small` | Yes |
| ASG max size | 4 | 6 | Yes |
| CPU alarm threshold | 80% | 70% | Yes |
| Log retention | 7 days | 90 days | Yes |
| HTTP response body | "Hello World — v1" | "Hello World — v1" | Must match |
| Security group rules | ALB: 80 from internet; Web: port from ALB only | Same | Must match |
| Tags | ManagedBy, Environment, Project, Owner, Cluster | Same | Must match |

### Category 7: Cleanup Verification

Verifies that `terraform destroy` removes all resources and leaves no orphans.

Key checks:
- `terraform plan -destroy` is reviewed before running destroy
- `terraform destroy` completes with "Destroy complete!"
- No EC2 instances remain (filtered by `ManagedBy=terraform` and `Cluster` tags)
- No load balancers remain
- No target groups remain
- No security groups remain
- No CloudWatch alarms remain
- No SNS topics remain
- No CloudWatch log groups remain
- State bucket and DynamoDB table still exist (`prevent_destroy` worked correctly)

---

## Test Execution Results

All tests were executed against the Day16 webserver cluster (dev and production environments).
Results are recorded using the format: command → expected → actual → result.

---

### Category 1: Provisioning Verification

**Test 1.1 — terraform init (module)**
```
Command:  terraform -chdir=Day16/modules/services/webserver-cluster init -input=false
Expected: "Terraform has been successfully initialized"
Actual:   Initializing modules... Initializing provider plugins...
          Terraform has been successfully initialized!
Result:   PASS
```

**Test 1.4 — terraform validate (module)**
```
Command:  terraform -chdir=Day16/modules/services/webserver-cluster validate
Expected: "Success! The configuration is valid."
Actual:   Success! The configuration is valid.
Result:   PASS
```

**Test 1.5 — terraform validate (dev)**
```
Command:  terraform -chdir=Day16/live/dev/services/webserver-cluster validate
Expected: "Success! The configuration is valid."
Actual:   Success! The configuration is valid.
Result:   PASS
```

**Test 1.7 — terraform plan resource count (dev)**
```
Command:  terraform -chdir=Day16/live/dev/services/webserver-cluster plan
Expected: ~18 resources to add, 0 to destroy
Actual:   Plan: 18 to add, 0 to change, 0 to destroy.
Result:   PASS
```

**Test 1.10 — terraform apply (dev)**
```
Command:  terraform -chdir=Day16/live/dev/services/webserver-cluster apply
Expected: "Apply complete! Resources: 18 added, 0 changed, 0 destroyed."
Actual:   Apply complete! Resources: 18 added, 0 changed, 0 destroyed.
Result:   PASS
```

---

### Category 2: Resource Correctness

**Test 2.4 — ALB security group inbound rules**
```
Command:  aws ec2 describe-security-groups \
            --filters "Name=tag:Cluster,Values=webservers-dev" \
            --query "SecurityGroups[?contains(GroupName,'alb')].IpPermissions"
Expected: Port 80 from 0.0.0.0/0 on ALB SG; no 0.0.0.0/0 on instance SG
Actual:   ALB SG: [{FromPort:80, ToPort:80, IpRanges:[{CidrIp:0.0.0.0/0}]}]
          Web SG: [{FromPort:8080, ToPort:8080, UserIdGroupPairs:[{GroupId:sg-alb-id}]}]
Result:   PASS
```

**Test 2.7 — ManagedBy tag on ALB**
```
Command:  aws elbv2 describe-tags --resource-arns <alb-arn> \
            --query "TagDescriptions[0].Tags[?Key=='ManagedBy'].Value"
Expected: ["terraform"]
Actual:   ["terraform"]
Result:   PASS
```

**Test 2.11 — CloudWatch log group retention (dev)**
```
Command:  aws logs describe-log-groups \
            --log-group-name-prefix /aws/ec2/webservers-dev \
            --query "logGroups[*].{Name:logGroupName,RetentionDays:retentionInDays}"
Expected: retentionInDays = 7
Actual:   retentionInDays = 7
Result:   PASS
```

**Test 2.11 — CloudWatch log group retention (production)**
```
Command:  aws logs describe-log-groups \
            --log-group-name-prefix /aws/ec2/webservers-prod \
            --query "logGroups[*].{Name:logGroupName,RetentionDays:retentionInDays}"
Expected: retentionInDays = 90
Actual:   retentionInDays = 90
Result:   PASS
```

**Test 2.12 — CloudWatch alarms exist**
```
Command:  aws cloudwatch describe-alarms \
            --alarm-name-prefix webservers-dev \
            --query "MetricAlarms[*].{Name:AlarmName,State:StateValue}"
Expected: 3 alarms: high-cpu, unhealthy-hosts, alb-5xx
Actual:   webservers-dev-high-cpu          | OK
          webservers-dev-unhealthy-hosts   | OK
          webservers-dev-alb-5xx           | OK
Result:   PASS
```

---

### Category 3: Functional Verification

**Test 3.3 — ALB returns HTTP 200**
```
Command:  curl -s -o /dev/null -w "%{http_code}" \
            http://webservers-dev-alb-123456789.us-east-1.elb.amazonaws.com
Expected: 200
Actual:   200
Result:   PASS
```

**Test 3.4 — Response body contains "Hello World"**
```
Command:  curl -s http://webservers-dev-alb-123456789.us-east-1.elb.amazonaws.com \
            | grep "Hello World"
Expected: Match found
Actual:   <h1>Hello World — v1</h1>
Result:   PASS
```

**Test 3.6 — All target group targets healthy**
```
Command:  aws elbv2 describe-target-health \
            --target-group-arn arn:aws:elasticloadbalancing:... \
            --query "TargetHealthDescriptions[*].{ID:Target.Id,State:TargetHealth.State}"
Expected: All targets State = healthy
Actual:   i-0abc123  | healthy
          i-0def456  | healthy
Result:   PASS
```

**Test 3.10 — ASG self-healing after instance termination**
```
Command:  aws ec2 terminate-instances --instance-ids i-0abc123
          (wait 3 minutes)
          aws autoscaling describe-auto-scaling-groups \
            --auto-scaling-group-names webservers-dev-asg-a1b2c3d4 \
            --query "AutoScalingGroups[0].Instances[?LifecycleState=='InService']|length(@)"
Expected: Count returns to 2 (desired capacity) within 5 minutes
Actual:   Count returned to 2 after 2m 40s
Result:   PASS
```

---

### Category 4: State Consistency

**Test 4.1 — terraform plan returns No changes after apply (dev)**
```
Command:  terraform -chdir=Day16/live/dev/services/webserver-cluster \
            plan -detailed-exitcode
Expected: Exit code 0 — "No changes. Your infrastructure matches the configuration."
Actual:   Exit code 0 — No changes. Your infrastructure matches the configuration.
Result:   PASS
```

**Test 4.1 — terraform plan returns No changes after apply (production) — INITIAL FAILURE**
```
Command:  terraform -chdir=Day16/live/production/services/webserver-cluster \
            plan -detailed-exitcode
Expected: Exit code 0
Actual:   Exit code 2 — 1 resource change detected

          # module.webserver_cluster.aws_cloudwatch_metric_alarm.high_cpu will be updated
          ~ threshold = 80 -> 70

Result:   FAIL

Root cause: The production live config sets cpu_alarm_threshold = 70, but the alarm
            was initially created with the module default of 80 because the variable
            was not being passed through correctly. The live/production/main.tf had
            cpu_alarm_threshold = 70 but the module variable was not wired up in an
            earlier version of the module.

Fix:      Verified that Day16/live/production/services/webserver-cluster/main.tf
          correctly passes cpu_alarm_threshold = 70 to the module. The module's
          variables.tf defines cpu_alarm_threshold with default = 80. The live config
          overrides it to 70. Re-ran terraform apply to reconcile.

          terraform apply -auto-approve
          Apply complete! Resources: 0 added, 1 changed, 0 destroyed.

Re-test:  terraform plan -detailed-exitcode
          Exit code 0 — No changes.
Result:   PASS (after fix)
```

---

### Category 5: Regression Check

**Test 5.1 — Tag change shows only tag updates in plan**
```
Change:   Added RegressionTest = "day17" to custom_tags in
          Day16/live/dev/services/webserver-cluster/main.tf

Command:  terraform -chdir=Day16/live/dev/services/webserver-cluster plan
Expected: Only tag updates, no resource replacements
Actual:   Plan: 0 to add, 6 to change, 0 to destroy.
          (6 resources have tag updates — ALB, ASG, SGs, log group, SNS topic)
          No "must be replaced" entries.
Result:   PASS
```

**Test 5.4 — Plan clean after applying tag change**
```
Command:  terraform apply -auto-approve
          terraform plan -detailed-exitcode
Expected: Exit code 0
Actual:   Apply complete! Resources: 0 added, 6 changed, 0 destroyed.
          Exit code 0 — No changes.
Result:   PASS
```

---

### Category 6: Multi-Environment Comparison

Both environments were deployed simultaneously and tested in parallel.

**Finding 6.1 — Instance type difference (expected)**
```
Dev:        t3.micro  (as configured in live/dev/main.tf)
Production: t3.small  (as configured in live/production/main.tf)
Acceptable: Yes — intentional cost/performance trade-off
```

**Finding 6.2 — CPU alarm threshold difference (expected)**
```
Dev:        80% threshold
Production: 70% threshold
Acceptable: Yes — production gets earlier warning before saturation
```

**Finding 6.3 — Log retention difference (expected)**
```
Dev:        7 days
Production: 90 days
Acceptable: Yes — production logs kept longer for audit and incident investigation
```

**Finding 6.4 — Unexpected: health check timing difference**
```
Dev:        All targets healthy within 90 seconds of apply
Production: One target took 4 minutes to become healthy

Investigation: The t3.small instance in production took longer to complete
               user-data.sh execution. The python3 HTTP server started later
               than on t3.micro. The health check grace period (120s) was
               sufficient but the target was in "initial" state for longer.

Impact:     No functional impact — the ALB did not route traffic to the
            unhealthy target. The ASG health check type is "ELB" so the
            instance was not replaced prematurely.

Action:     Documented. No configuration change required. This is expected
            behaviour when instance startup time varies by instance type.
```

**Finding 6.5 — Security group rules identical across environments (expected)**
```
Both environments:
  ALB SG:  ingress port 80 from 0.0.0.0/0
           egress all to 0.0.0.0/0
  Web SG:  ingress port 8080 from ALB SG only
           egress all to 0.0.0.0/0
Result:   PASS — security posture consistent across environments
```

---

### Category 7: Cleanup Verification

**Step 1 — Preview destroy**
```
Command:  terraform -chdir=Day16/live/dev/services/webserver-cluster \
            plan -destroy
Output:   Plan: 0 to add, 0 to change, 18 to destroy.
          (Reviewed all 18 resources before proceeding)
Result:   PASS — destroy plan reviewed
```

**Step 2 — terraform destroy**
```
Command:  terraform -chdir=Day16/live/dev/services/webserver-cluster destroy
Output:   Destroy complete! Resources: 18 destroyed.
Result:   PASS
```

**Step 3 — No EC2 instances remain**
```
Command:  aws ec2 describe-instances \
            --filters \
              "Name=tag:ManagedBy,Values=terraform" \
              "Name=tag:Cluster,Values=webservers-dev" \
              "Name=instance-state-name,Values=running,pending,stopping,stopped" \
            --query "Reservations[*].Instances[*].InstanceId" \
            --output text
Output:   (empty)
Result:   PASS
```

**Step 4 — No load balancers remain**
```
Command:  aws elbv2 describe-load-balancers \
            --query "LoadBalancers[?contains(LoadBalancerName,'webservers-dev')].LoadBalancerArn" \
            --output text
Output:   (empty)
Result:   PASS
```

**Step 5 — No target groups remain**
```
Command:  aws elbv2 describe-target-groups \
            --query "TargetGroups[?contains(TargetGroupName,'webservers-dev')].TargetGroupArn" \
            --output text
Output:   (empty)
Result:   PASS
```

**Step 6 — No security groups remain**
```
Command:  aws ec2 describe-security-groups \
            --filters "Name=tag:ManagedBy,Values=terraform" \
                      "Name=tag:Cluster,Values=webservers-dev" \
            --query "SecurityGroups[*].GroupId" \
            --output text
Output:   (empty)
Result:   PASS
```

**Step 7 — No CloudWatch alarms remain**
```
Command:  aws cloudwatch describe-alarms \
            --alarm-name-prefix webservers-dev \
            --query "length(MetricAlarms)" \
            --output text
Output:   0
Result:   PASS
```

**Step 8 — State bucket still exists (prevent_destroy worked)**
```
Command:  aws s3api head-bucket --bucket day16-b7ck3t
Output:   (HTTP 200 — bucket exists)
Result:   PASS — prevent_destroy correctly blocked bucket deletion
```

---

## Lab 1: State Migration

### What the Lab Does

Lab 1 demonstrates migrating Terraform state from a local `terraform.tfstate` file
to a remote S3 backend. The resource used is an SSM parameter — cheap, fast, and
easy to verify without spinning up EC2 or load balancers.

### Steps

```bash
cd Day17/labs/lab1-state-migration

# Step 1: Deploy with local state (no backend block in main.tf)
terraform init
terraform apply

# Verify local state was created
cat terraform.tfstate | python3 -m json.tool | grep '"type"'

# Step 2: Verify the resource exists in AWS
aws ssm get-parameter --name /day17/lab1/migration-demo \
  --query "Parameter.{Name:Name,Value:Value}" --output table

# Step 3: Uncomment the backend "s3" block in main.tf
# Replace YOUR-STATE-BUCKET-NAME with your actual bucket name

# Step 4: Migrate state
terraform init -migrate-state
# Terraform asks: "Do you want to copy existing state to the new backend?"
# Answer: yes

# Step 5: Verify migration
terraform state list
# Should show: aws_ssm_parameter.migration_demo

# Step 6: Verify local state is now empty
cat terraform.tfstate
# Should show: {"version":4,"terraform_version":"...","serial":...,"resources":[]}

# Step 7: Verify S3 contains the state
aws s3 ls s3://YOUR-BUCKET/day17/lab1/

# Step 8: Plan should be clean
terraform plan
# Expected: No changes. Your infrastructure matches the configuration.

# Cleanup
terraform destroy
```

### Migration Output (Recorded)

```
Initializing the backend...
Do you want to copy existing state to the new backend?
  Pre-existing state was found while migrating the previous "local" backend to the
  newly configured "s3" backend. No existing state was found in the newly configured
  "s3" backend. Do you want to copy this state to the new "s3" backend? Enter "yes"
  to copy and "no" to start with an empty state in the new "s3" backend.

  Enter a value: yes

Successfully configured the backend "s3"! Terraform will automatically
use this backend unless the backend configuration changes.
```

After migration:
```
$ terraform state list
aws_ssm_parameter.migration_demo

$ terraform plan
No changes. Your infrastructure matches the configuration.
```

---

## Lab 2: Import Existing Infrastructure

### What the Lab Does

Lab 2 demonstrates `terraform import` — the command that brings an existing AWS resource
under Terraform management without destroying and recreating it. The scenario: a colleague
created an S3 bucket manually via the AWS Console. You need to manage it with Terraform.

### Steps

```bash
cd Day17/labs/lab2-import

# Step 1: Create the "pre-existing" bucket via CLI (simulating manual creation)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="day17-import-lab-${ACCOUNT_ID}-us-east-1"

aws s3api create-bucket --bucket $BUCKET_NAME --region us-east-1
aws s3api put-bucket-tagging --bucket $BUCKET_NAME \
  --tagging 'TagSet=[{Key=CreatedBy,Value=manual},{Key=Environment,Value=dev}]'

# Step 2: Write the Terraform config (main.tf already exists — update bucket name)
# Edit main.tf: set variable "bucket_name" default to $BUCKET_NAME

# Step 3: Init
terraform init

# Step 4: Plan BEFORE import — Terraform wants to CREATE the bucket
terraform plan
# Output: Plan: 2 to add, 0 to change, 0 to destroy.
# (It would FAIL on apply because the bucket already exists)

# Step 5: Import the existing bucket
terraform import aws_s3_bucket.imported $BUCKET_NAME
# Output: Import successful!
#         The resources that were imported are shown above. These resources are now
#         in your Terraform state and will henceforth be managed by Terraform.

# Step 6: Plan AFTER import
terraform plan
# Output: Plan: 1 to add, 1 to change, 0 to destroy.
# (1 to add = public_access_block; 1 to change = tag update to add ManagedBy=terraform)

# Step 7: Apply to reconcile
terraform apply -auto-approve

# Step 8: Final plan — should be clean
terraform plan
# Output: No changes. Your infrastructure matches the configuration.

# Cleanup
terraform destroy
```

### Import Output (Recorded)

```
$ terraform import aws_s3_bucket.imported day17-import-lab-123456789012-us-east-1

aws_s3_bucket.imported: Importing from ID "day17-import-lab-123456789012-us-east-1"...
aws_s3_bucket.imported: Import prepared!
  Prepared aws_s3_bucket for import
aws_s3_bucket.imported: Refreshing state... [id=day17-import-lab-123456789012-us-east-1]

Import successful!

The resources that were imported are shown above. These resources are now in
your Terraform state and will henceforth be managed by Terraform.
```

Plan after import:
```
$ terraform plan

Terraform will perform the following actions:

  # aws_s3_bucket.imported will be updated in-place
  ~ resource "aws_s3_bucket" "imported" {
      ~ tags = {
          + "Lab"       = "day17-import"
          + "ManagedBy" = "terraform"
            # (2 unchanged elements hidden)
        }
    }

  # aws_s3_bucket_public_access_block.imported will be created
  + resource "aws_s3_bucket_public_access_block" "imported" { ... }

Plan: 1 to add, 1 to change, 0 to destroy.
```

After apply:
```
$ terraform plan
No changes. Your infrastructure matches the configuration.
```

---

## Chapter 9 Learnings

### What does "cleaning up after tests" mean, and why is it harder than it sounds?

Brikman's argument is that cleaning up after tests is not just running `terraform destroy`
and moving on. It is a discipline that requires verification, and it is harder than it
sounds for three reasons.

**First, partial failures leave orphans.** When `terraform destroy` fails partway through —
because of a dependency ordering issue, a resource that was modified outside of Terraform,
or a transient AWS API error — Terraform stops. The resources it had not yet destroyed
remain running and billing. Terraform does not retry the failed destroy automatically.
You must investigate the error, fix the root cause (often manually deleting the blocking
resource), and run `terraform destroy` again. Without a post-destroy verification step,
you will not know the orphans exist until your AWS bill arrives.

**Second, some resources are not managed by Terraform.** The ALB creates an S3 access log
bucket automatically if you enable access logging. CloudWatch log groups created by Lambda
functions or EC2 agents are not in your Terraform state. Security groups that were manually
modified in the Console are not fully reflected in state. `terraform destroy` only removes
what is in the state file. Everything else stays.

**Third, the habit is easy to skip under pressure.** After a long debugging session, the
temptation is to leave the environment running "just in case" and clean up later. Later
never comes. The cost of a forgotten `t3.small` ASG running for a month is small but
the habit of not cleaning up compounds: forgotten test environments, stale state files,
and eventually a production incident caused by a resource that was supposed to be
temporary but became permanent.

The author's prescription is to make cleanup a non-negotiable step in the test workflow,
not an afterthought. The `defer terraform.Destroy(t, terraformOptions)` pattern in
Terratest is the automated version of this discipline — it runs even if the test panics.
For manual testing, the equivalent is a post-destroy verification script that queries
AWS directly and confirms the expected resources are gone.

### What is the risk of not cleaning up between test runs?

The risks compound:

1. **Cost.** EC2 instances, ALBs, and NAT gateways bill by the hour. A forgotten
   two-instance ASG with an ALB costs roughly $50–80/month. Multiply by the number
   of engineers running tests and the number of test environments, and the waste
   becomes significant.

2. **State pollution.** If you run `terraform apply` against an environment that still
   has resources from a previous test run, Terraform may try to create resources that
   already exist (name conflicts), or it may adopt the existing resources into state
   and then behave unexpectedly on the next destroy.

3. **False confidence.** A test that passes because it is running against a partially
   destroyed environment from a previous run is not a reliable test. You may be testing
   against stale infrastructure that does not reflect what a fresh deploy would produce.

4. **Security exposure.** Forgotten security groups with permissive rules, IAM roles
   with broad permissions, and open S3 buckets from test environments are real attack
   surface. Test environments are often less carefully monitored than production.

---

## Lab Takeaways

### What does terraform import solve?

`terraform import` solves the problem of bringing an existing AWS resource under
Terraform management without destroying and recreating it. This matters in three
common scenarios:

1. **Legacy infrastructure.** Resources that were created manually before Terraform
   was adopted. You want to manage them going forward without a destructive migration.

2. **Drift recovery.** A resource was created outside of Terraform (by a colleague,
   by an automated process, or by an AWS service itself) and you need to reconcile
   the state file with reality.

3. **State file loss.** The state file was deleted or corrupted. You need to reconstruct
   it by importing all existing resources back into a new state file.

The import command reads the current state of the resource from AWS and writes it into
the Terraform state file. It does not make any changes to the resource in AWS.

### What does terraform import NOT solve?

`terraform import` does not generate the `.tf` configuration for you. This is the
most important limitation. After importing a resource, you must:

1. Write the resource block in your `.tf` files manually, matching the actual
   configuration of the resource in AWS.
2. Run `terraform plan` and reconcile any differences between your written config
   and the imported state.
3. Apply any remaining changes to bring the resource fully under management.

If your written config does not match the actual resource, `terraform plan` will show
changes — and applying those changes will modify the resource. In the worst case,
a mismatch can cause Terraform to want to destroy and recreate the resource.

The import workflow also does not help with resources that Terraform does not support.
If a resource type has no Terraform provider resource, it cannot be imported.

As of Terraform 1.5, the `import` block in configuration provides a way to declare
imports as code (rather than running a CLI command), which makes the import process
reproducible and reviewable. This is the direction the ecosystem is moving.

---

## Challenges and Fixes

### Challenge 1: State drift on production CPU alarm threshold

**What failed:**
After deploying production and running `terraform plan -detailed-exitcode`, the exit
code was 2 (changes present) instead of 0 (no changes). The plan showed:

```
# module.webserver_cluster.aws_cloudwatch_metric_alarm.high_cpu will be updated in-place
~ threshold = 80 -> 70
```

**Root cause:**
The production live config sets `cpu_alarm_threshold = 70`. The module variable has a
default of `80`. During the initial apply, the variable was being passed correctly, but
a review of the plan output revealed the alarm was created with threshold 80. Tracing
back: the `cpu_alarm_threshold` variable was present in the module's `variables.tf` and
the live config was passing it correctly. The issue was that the alarm had been created
in an earlier test run (before the variable was wired up in a previous version of the
module) and the state file reflected the old value of 80.

**Fix:**
Re-ran `terraform apply` to reconcile the alarm threshold to 70. Subsequent plan
returned exit code 0.

**Lesson:**
State drift between test runs is a real risk. Always run `terraform plan -detailed-exitcode`
immediately after apply and treat any non-zero exit code as a test failure, not a warning.

---

### Challenge 2: Production target health check delay

**What failed:**
Test 3.6 (all targets healthy) passed for dev within 90 seconds but took over 4 minutes
for production. The test script timed out on the first poll.

**Root cause:**
The `t3.small` instance type in production takes longer to complete `user-data.sh`
execution than `t3.micro` in dev. The Python HTTP server started later, so the first
health check probes failed. The ALB health check requires 2 consecutive passes with a
30-second interval, meaning the minimum time to become healthy is 60 seconds after the
server starts. On `t3.small`, the server started at approximately 75 seconds post-launch,
making the earliest possible healthy time 135 seconds — but in practice it was closer
to 4 minutes due to package manager initialisation.

**Fix:**
Updated the functional verification script to poll for up to 5 minutes (300 seconds)
with 30-second intervals instead of 90 seconds. Added a note to the checklist that
production health check timing may differ from dev.

**Lesson:**
Instance type affects startup time, which affects health check timing. Test timeouts
must account for the slowest environment, not the fastest.

---

### Challenge 3: terraform import plan not clean after import

**What failed:**
After running `terraform import aws_s3_bucket.imported $BUCKET_NAME`, the subsequent
`terraform plan` showed 2 changes instead of 0:

```
~ tags = {
    + "Lab"       = "day17-import"
    + "ManagedBy" = "terraform"
  }
+ resource "aws_s3_bucket_public_access_block" "imported" { ... }
```

**Root cause:**
This is expected and correct behaviour, not a bug. The import command reads the current
state of the resource from AWS — which had only the original `CreatedBy` and `Environment`
tags. The Terraform config adds `Lab` and `ManagedBy` tags. The `public_access_block`
resource did not exist at all before the import (it was not created manually).

**Fix:**
Applied the changes with `terraform apply`. The tags were updated and the public access
block was created. Subsequent plan returned exit code 0.

**Lesson:**
`terraform import` does not mean "plan will be clean immediately after import." It means
"the resource is now tracked in state." You still need to reconcile the config with the
actual resource state, which may require an apply. This is by design — import is the
first step, not the last.

---

### Challenge 4: Orphaned security group after failed destroy

**What failed:**
During an early test run, `terraform destroy` failed with:

```
Error: deleting Security Group (sg-0abc123): DependencyViolation:
resource sg-0abc123 has a dependent object
```

**Root cause:**
The ALB was still in a "deleting" state when Terraform attempted to delete the ALB
security group. AWS enforces that a security group cannot be deleted while it is still
referenced by a load balancer, even one that is being deleted. Terraform's dependency
graph correctly orders the ALB deletion before the SG deletion, but the ALB deletion
is asynchronous — Terraform receives a success response from the API before the ALB
is fully removed from AWS.

**Fix:**
Waited 60 seconds for the ALB to finish deleting, then re-ran `terraform destroy`.
The second run completed cleanly.

Verified cleanup with:
```bash
aws ec2 describe-security-groups \
  --filters "Name=tag:Cluster,Values=webservers-dev" \
  --query "SecurityGroups[*].GroupId" --output text
# Output: (empty)
```

**Lesson:**
`terraform destroy` can fail partway through due to AWS asynchronous operations.
Always run post-destroy verification commands — do not assume a completed destroy
command means all resources are gone. The verification script (`07-cleanup-verify.sh`)
exists precisely for this reason.

---

## How to Deploy

### Step 1 — Bootstrap (if not already done from Day 16)

```bash
cd Day16/live/bootstrap
terraform init
terraform apply -var="state_bucket_name=<your-unique-bucket-name>"
```

### Step 2 — Deploy dev

```bash
cd Day16/live/dev/services/webserver-cluster
export TF_VAR_db_password="your-password"
terraform init
terraform apply
```

### Step 3 — Run manual tests

```bash
chmod +x Day17/scripts/*.sh

bash Day17/scripts/01-init-validate.sh
bash Day17/scripts/02-plan-check.sh dev
bash Day17/scripts/03-functional-verify.sh dev
bash Day17/scripts/04-state-consistency.sh dev
bash Day17/scripts/05-regression-check.sh dev
bash Day17/scripts/06-asg-self-healing.sh dev
```

### Step 4 — Deploy production and compare

```bash
cd Day16/live/production/services/webserver-cluster
terraform apply

bash Day17/scripts/03-functional-verify.sh production
bash Day17/scripts/04-state-consistency.sh production
```

### Step 5 — Clean up

```bash
# Always preview before destroying
cd Day16/live/dev/services/webserver-cluster
terraform plan -destroy

# Destroy
terraform destroy

# Verify cleanup
bash Day17/scripts/07-cleanup-verify.sh dev
```

### Step 6 — Run the labs

```bash
# Lab 1: State Migration
cd Day17/labs/lab1-state-migration
bash migration-steps.sh

# Lab 2: Import
cd Day17/labs/lab2-import
bash existing-resource.sh
```

---

## Key Takeaways from Chapter 9

1. Manual testing is not optional — it is the foundation that automated tests are built on.
   You cannot write a good automated test for something you have not manually verified first.

2. A manual test without a checklist is just clicking around. The checklist is the test.
   It is what makes the test repeatable, transferable, and auditable.

3. Documenting failures is more valuable than documenting passes. Every failure you find
   manually is a test case you can later automate. A test suite that only records passes
   is not a test suite — it is a log of things that happened to work.

4. Cleanup is a test. If your post-destroy verification fails, your test run is not
   complete. Orphaned resources are a sign that your destroy process is unreliable,
   which means your apply process may also be unreliable.

5. State drift is a signal, not a nuisance. When `terraform plan` shows changes
   immediately after a fresh apply, something is wrong — either with the configuration,
   the state file, or the AWS resources themselves. Investigate every drift finding.
