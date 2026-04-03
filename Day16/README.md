# Day 16 — Building Production-Grade Infrastructure

## What Changed and Why

Days 3–15 produced infrastructure that worked. Day 16 is about infrastructure that is
*production-ready*: auditable, observable, safe to hand to a team under pressure, and
defensible against the failure modes that actually kill production systems.

---

## Directory Structure

```
Day16/
├── modules/
│   ├── services/
│   │   └── webserver-cluster/   # Core reusable module
│   │       ├── main.tf
│   │       ├── variables.tf     # All inputs with validation blocks
│   │       ├── outputs.tf       # All outputs documented
│   │       ├── user-data.sh
│   │       └── README.md
│   └── state-bucket/            # Remote state bootstrap module
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── README.md
├── live/
│   ├── bootstrap/               # Run once to create the state bucket
│   │   ├── main.tf
│   │   └── variables.tf
│   ├── dev/services/webserver-cluster/main.tf
│   └── production/services/webserver-cluster/main.tf
├── test/
│   ├── webserver_cluster_test.go  # Terratest suite
│   └── go.mod
├── .gitignore
└── README.md
```

---

## Production-Grade Checklist Audit

### Code Structure

| Item | Status | Notes |
|------|--------|-------|
| Small, single-purpose modules | ✅ | `webserver-cluster` and `state-bucket` are separate modules |
| Clear, minimal interfaces with typed, described inputs | ✅ | Every variable has `type`, `description`, and where applicable `validation` |
| All outputs defined and documented | ✅ | `outputs.tf` has `description` on every output |
| No hardcoded values in resource blocks | ✅ | All values flow through variables or `locals` |
| `locals` used to centralise repeated expressions | ✅ | `common_tags` locals block used everywhere |

### Reliability

| Item | Status | Notes |
|------|--------|-------|
| ASG health checks point to ELB, not EC2 | ✅ | `health_check_type = "ELB"` |
| `create_before_destroy` on replaceable resources | ✅ | Set on SGs, launch template, ASG |
| `name_prefix` instead of `name` on mutable resources | ✅ | SGs and launch template use `name_prefix` |
| `prevent_destroy` on critical resources | ✅ | S3 state bucket and DynamoDB lock table |

### Security

| Item | Status | Notes |
|------|--------|-------|
| No secrets in `.tf` files or state | ✅ | Secrets via `TF_VAR_*` env vars only |
| Sensitive variables marked `sensitive = true` | ✅ | `db_password` in live configs |
| Remote state with encryption | ✅ | `state-bucket` module enables AES256 SSE |
| IAM least-privilege | ✅ | Instance role only gets CloudWatch metrics + explicit secret policies |
| No `0.0.0.0/0` on instance security group | ✅ | Instance SG only allows traffic from ALB SG |

### Observability

| Item | Status | Notes |
|------|--------|-------|
| Consistent tagging on all resources | ✅ | `common_tags` merged onto every resource |
| CloudWatch alarms for critical metrics | ✅ | High CPU, unhealthy hosts, ALB 5xx |
| Log groups with retention periods | ✅ | `/aws/ec2/<cluster_name>` with configurable retention |

### Maintainability

| Item | Status | Notes |
|------|--------|-------|
| Every module has a README with usage examples | ✅ | Both modules have full README |
| Provider versions pinned | ✅ | `~> 5.0` and `~> 3.0` in all `required_providers` |
| `.terraform.lock.hcl` committed | ✅ | Not in `.gitignore` |
| `.gitignore` excludes state, `.terraform/`, `*.tfvars` | ✅ | See `.gitignore` |

---

## Top 3 Refactors

### 1. Centralised Tagging with `common_tags`

**Before (Day 13):**
```hcl
locals {
  base_tags = merge(
    {
      Cluster     = var.cluster_name
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.custom_tags
  )
}
```
Tags were inconsistent — `Cluster` instead of a standard key, no `Project` or `Owner`.
Some resources got tags, some didn't.

**After (Day 16):**
```hcl
locals {
  common_tags = merge(
    {
      Environment = var.environment
      ManagedBy   = "terraform"
      Project     = var.project_name
      Owner       = var.team_name
      Cluster     = var.cluster_name
    },
    var.custom_tags
  )
}

resource "aws_lb" "example" {
  # ...
  tags = merge(local.common_tags, { Name = "${var.cluster_name}-alb" })
}

resource "aws_cloudwatch_log_group" "app" {
  # ...
  tags = merge(local.common_tags, { Name = "${var.cluster_name}-logs" })
}
```
Every resource now carries the same five base tags. Cost allocation, compliance queries,
and `aws resourcegroupstaggingapi` searches all work consistently.

---

### 2. `prevent_destroy` on State Infrastructure

**Before:** No lifecycle rules on the S3 state bucket.

**After:**
```hcl
resource "aws_s3_bucket" "state" {
  bucket = var.bucket_name
  tags   = merge(local.common_tags, { Name = var.bucket_name })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_dynamodb_table" "state_lock" {
  # ...
  lifecycle {
    prevent_destroy = true
  }
}
```
Without `prevent_destroy`, running `terraform destroy` in the bootstrap directory
would delete the state bucket — taking every environment's state history with it.
Terraform will now refuse to destroy these resources and print an explicit error,
forcing a deliberate override.

---

### 3. Input Validation on Every Constrained Variable

**Before (Day 13):**
```hcl
variable "environment" {
  type        = string
  description = "Deployment environment: dev or production"

  validation {
    condition     = contains(["dev", "production"], var.environment)
    error_message = "Environment must be dev or production."
  }
}
```
Only two environments, no instance type validation, no port range check.

**After (Day 16):**
```hcl
variable "environment" {
  type        = string
  description = "Deployment environment. Controls instance sizing and alarm thresholds."

  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be dev, staging, or production."
  }
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type. Must be a t2 or t3 family type."
  default     = "t3.micro"

  validation {
    condition     = can(regex("^t[23]\\.", var.instance_type))
    error_message = "Instance type must be a t3 family type (e.g. t3.micro, t3.small)."
  }
}

variable "server_port" {
  type    = number
  default = 8080

  validation {
    condition     = var.server_port >= 1024 && var.server_port <= 65535
    error_message = "server_port must be between 1024 and 65535."
  }
}
```
Validation fires at `terraform plan` time — before any AWS API calls. Passing
`instance_type = "m5.large"` now produces:

```
│ Error: Invalid value for variable
│   on variables.tf line 42, in variable "instance_type":
│   42:   validation {
│ Instance type must be a t3 family type (e.g. t3.micro, t3.small).
```

---

## Tagging Implementation

`common_tags` is defined once in `locals` and merged onto every resource:

```hcl
locals {
  common_tags = merge(
    {
      Environment = var.environment
      ManagedBy   = "terraform"
      Project     = var.project_name
      Owner       = var.team_name
      Cluster     = var.cluster_name
    },
    var.custom_tags
  )
}
```

Applied to an ALB:
```hcl
resource "aws_lb" "example" {
  name = "${var.cluster_name}-alb"
  # ...
  tags = merge(local.common_tags, { Name = "${var.cluster_name}-alb" })
}
```

Applied to a CloudWatch log group:
```hcl
resource "aws_cloudwatch_log_group" "app" {
  name              = "/aws/ec2/${var.cluster_name}"
  retention_in_days = var.log_retention_days
  tags              = merge(local.common_tags, { Name = "${var.cluster_name}-logs" })
}
```

Applied to ASG instances via `propagate_at_launch`:
```hcl
dynamic "tag" {
  for_each = local.common_tags
  content {
    key                 = tag.key
    value               = tag.value
    propagate_at_launch = true
  }
}
```

---

## Lifecycle Rules

### `prevent_destroy` — state bucket and DynamoDB lock table

```hcl
resource "aws_s3_bucket" "state" {
  bucket = var.bucket_name

  lifecycle {
    prevent_destroy = true
  }
}
```

Without this: `terraform destroy` in the bootstrap directory deletes the bucket.
Every environment loses its state. Recovery requires manually reconstructing state
from AWS resources using `terraform import` — hours of work, high error risk.

### `create_before_destroy` — security groups and launch template

```hcl
resource "aws_security_group" "alb_sg" {
  name_prefix = "${var.cluster_name}-alb-sg-"
  # ...
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_launch_template" "example" {
  name_prefix = "${var.cluster_name}-lt-"
  # ...
  lifecycle {
    create_before_destroy = true
  }
}
```

Without this: Terraform destroys the old SG before creating the new one.
During that window, the ASG has no valid security group and new instances fail
to launch. With `create_before_destroy`, the new SG exists and is attached
before the old one is removed — zero downtime.

---

## CloudWatch Alarms

Three alarms are created for every cluster:

```hcl
# 1. High CPU — fires when average CPU > threshold for 4 consecutive minutes
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${var.cluster_name}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = var.cpu_alarm_threshold  # 80 in dev, 70 in production
  treat_missing_data  = "notBreaching"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.example.name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

# 2. Unhealthy hosts — fires immediately when any target fails health checks
resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${var.cluster_name}-unhealthy-hosts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  # ...
}

# 3. ALB 5xx errors — fires when error rate spikes
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.cluster_name}-alb-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  treat_missing_data  = "notBreaching"
  # ...
}
```

**Threshold rationale:**
- CPU at 80% (dev) / 70% (production): gives headroom to scale before saturation.
  Two evaluation periods (4 minutes total) avoids false positives from short spikes.
- Unhealthy hosts at 0: any unhealthy target is immediately actionable.
- 5xx at 10/minute: filters noise from single transient errors while catching real incidents.

**When an alarm fires:** SNS publishes to the `alerts` topic. If `alarm_email` is set,
an email subscription is created. In production, point this at PagerDuty or OpsGenie
via an HTTPS subscription.

---

## Input Validation Examples

```hcl
variable "environment" {
  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be dev, staging, or production."
  }
}

variable "instance_type" {
  validation {
    condition     = can(regex("^t[23]\\.", var.instance_type))
    error_message = "Instance type must be a t3 family type (e.g. t3.micro, t3.small)."
  }
}

variable "log_retention_days" {
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365], var.log_retention_days)
    error_message = "log_retention_days must be a valid CloudWatch retention value (e.g. 7, 14, 30, 90, 365)."
  }
}
```

Passing `environment = "prod"` (a common typo) produces:
```
│ Error: Invalid value for variable
│ Environment must be dev, staging, or production.
```

Passing `instance_type = "m5.large"`:
```
│ Error: Invalid value for variable
│ Instance type must be a t2 or t3 family type (e.g. t3.micro, t2.small).
```

Validation fires at `plan` time — no AWS resources are created or billed.

---

## Terratest

```go
func TestWebserverClusterDev(t *testing.T) {
    t.Parallel()

    terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
        TerraformDir: "../modules/services/webserver-cluster",
        Vars: map[string]interface{}{
            "cluster_name":  "test-cluster",
            "environment":   "dev",
            "instance_type": "t3.micro",
            "min_size":      1,
            "max_size":      2,
        },
    })

    // defer runs even if the test panics — no orphaned resources
    defer terraform.Destroy(t, terraformOptions)

    terraform.InitAndApply(t, terraformOptions)

    albDnsName := terraform.Output(t, terraformOptions, "alb_dns_name")
    url := fmt.Sprintf("http://%s", albDnsName)

    // Poll every 10s for up to 5 minutes — ALBs need time to register targets
    http_helper.HttpGetWithRetry(t, url, nil, 200, "Hello World", 30, 10*time.Second)
}
```

**What it deploys:** A real ASG + ALB in AWS using the module under test.

**What it asserts:** The ALB DNS name returns HTTP 200 with "Hello World" in the body —
proving the full stack (ASG, launch template, target group, health checks) works end-to-end.

**Why `defer terraform.Destroy`:** Go's `defer` runs when the function returns, even on
panic. Without it, a test failure mid-run leaves real AWS resources running and billing.
`defer` guarantees cleanup regardless of how the test exits.

**To run:**
```bash
cd Day16/test
go mod tidy
go test -v -run TestWebserverClusterDev -timeout 30m
```

---

## Chapter 8 Learnings

**Most important item not previously considered:** `treat_missing_data = "notBreaching"` on
CloudWatch alarms. Without this, an alarm with no data (e.g. the ASG scaled to zero, or
the metric stopped publishing) transitions to `ALARM` state and pages the on-call team
for a non-event. Setting it to `notBreaching` means silence is treated as healthy.

**Biggest gap between existing code and production-grade:** Observability was entirely
absent before Day 16. The cluster could have been silently failing health checks,
running at 95% CPU, or returning 500s to every user — and nothing would have fired.
Production-grade infrastructure is not just about what gets deployed; it's about what
gets *noticed* when something goes wrong.

---

## Challenges and Fixes

**Tag propagation on ASG:** The `dynamic "tag"` block iterates `local.common_tags` to
propagate tags to instances at launch. The `for_each` on a `map(string)` works cleanly,
but the `tag` block inside an ASG resource is different from the `tags` argument on most
resources — it requires `propagate_at_launch = true` explicitly on each entry.

**`prevent_destroy` and CI/CD:** `prevent_destroy` blocks `terraform destroy` in
pipelines too. The bootstrap module must be excluded from any automated destroy jobs,
or the pipeline needs a separate step that removes the lifecycle block before destroying.
Document this in your runbooks.

**Validation regex escaping:** In HCL, the regex string `"^t[23]\\."` requires double
backslash because HCL processes the string escape first, then passes `^t[23]\.` to the
regex engine. Single backslash `"^t[23]\."` causes a HCL parse error.

---

## How to Deploy

### Step 1 — Bootstrap remote state (run once)

```bash
cd Day16/live/bootstrap
terraform init
terraform apply -var="state_bucket_name=<your-unique-bucket-name>"
```

### Step 2 — Enable remote backend

Copy the output values into the `backend "s3"` blocks in `live/dev` and `live/production`,
then uncomment them and run `terraform init` to migrate state.

### Step 3 — Deploy dev

```bash
cd Day16/live/dev/services/webserver-cluster
terraform init
terraform apply
```

### Step 4 — Deploy production

```bash
cd Day16/live/production/services/webserver-cluster
terraform init
terraform apply
```

### Step 5 — Run tests (requires Go and AWS credentials)

```bash
cd Day16/test
go mod tidy
go test -v -timeout 30m
```

---

## How to Test the Live Environments

These steps verify the deployed infrastructure is actually working — not just that
Terraform applied without errors.

### Prerequisites

- AWS CLI installed and configured (`aws configure` or `AWS_PROFILE` set)
- `curl` and `jq` available in your shell
- The cluster is deployed (Steps 1–4 above completed)

---

### 1. Get the ALB DNS name

After `terraform apply` completes, the ALB DNS name is printed as an output.
If you need it again without re-applying:

```bash
# dev
cd Day16/live/dev/services/webserver-cluster
terraform output alb_dns_name

# production
cd Day16/live/production/services/webserver-cluster
terraform output alb_dns_name
```

Save it to a variable for the steps below:

```bash
ALB_DNS=$(terraform output -raw alb_dns_name)
echo $ALB_DNS
```

---

### 2. Check the ALB returns HTTP 200

```bash
curl -s -o /dev/null -w "%{http_code}" http://$ALB_DNS
```

Expected output: `200`

If you get `000` or a connection refused, the ALB is still registering targets —
wait 60–90 seconds and retry. ALBs need at least one healthy target before they
start serving traffic.

---

### 3. Check the HTML response body

```bash
curl -s http://$ALB_DNS
```

Expected output: an HTML page containing `Hello World` and the cluster name.

```bash
# Assert "Hello World" is in the response
curl -s http://$ALB_DNS | grep -q "Hello World" && echo "PASS" || echo "FAIL"
```

---

### 4. Verify target group health

All registered targets should show `healthy`. If any show `initial` wait another
30 seconds — the health check needs two consecutive passes.

```bash
# Get the target group ARN from Terraform output
TG_ARN=$(aws elbv2 describe-target-groups \
  --query "TargetGroups[?contains(TargetGroupName, 'webservers-dev')].TargetGroupArn" \
  --output text)

# Check health of all targets
aws elbv2 describe-target-health \
  --target-group-arn $TG_ARN \
  --query "TargetHealthDescriptions[*].{ID:Target.Id,Port:Target.Port,State:TargetHealth.State}" \
  --output table
```

Expected: every row shows `State = healthy`.

---

### 5. Verify the ASG has the right number of instances

```bash
ASG_NAME=$(cd Day16/live/dev/services/webserver-cluster && terraform output -raw asg_name)

aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names $ASG_NAME \
  --query "AutoScalingGroups[0].{Min:MinSize,Max:MaxSize,Desired:DesiredCapacity,Running:Instances[?LifecycleState=='InService']|length(@)}" \
  --output table
```

Expected: `Running` matches `Desired`, and `Desired` is between `Min` and `Max`.

---

### 6. Verify CloudWatch alarms exist and are in OK state

```bash
aws cloudwatch describe-alarms \
  --alarm-name-prefix "webservers-dev" \
  --query "MetricAlarms[*].{Name:AlarmName,State:StateValue}" \
  --output table
```

Expected: three alarms (`high-cpu`, `unhealthy-hosts`, `alb-5xx`) all in `OK` state.

If any alarm is in `INSUFFICIENT_DATA`, it means the metric hasn't published yet —
this is normal for a freshly deployed cluster and resolves within a few minutes.

---

### 7. Verify the CloudWatch log group exists

```bash
LOG_GROUP=$(cd Day16/live/dev/services/webserver-cluster && terraform output -raw log_group_name)

aws logs describe-log-groups \
  --log-group-name-prefix $LOG_GROUP \
  --query "logGroups[*].{Name:logGroupName,RetentionDays:retentionInDays}" \
  --output table
```

Expected: the log group appears with the correct retention period (7 days for dev, 90 for production).

---

### 8. Verify resource tagging

Spot-check that the `common_tags` are applied correctly on the ALB:

```bash
ALB_ARN=$(aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?contains(LoadBalancerName, 'webservers-dev')].LoadBalancerArn" \
  --output text)

aws elbv2 describe-tags \
  --resource-arns $ALB_ARN \
  --query "TagDescriptions[0].Tags" \
  --output table
```

Expected tags: `Environment`, `ManagedBy = terraform`, `Project`, `Owner`, `Cluster`, `Name`.

---

### 9. Simulate a failure — manually mark a target unhealthy

This tests that the `unhealthy-hosts` alarm fires correctly.

```bash
# Get an instance ID from the target group
INSTANCE_ID=$(aws elbv2 describe-target-health \
  --target-group-arn $TG_ARN \
  --query "TargetHealthDescriptions[0].Target.Id" \
  --output text)

# Deregister it from the target group
aws elbv2 deregister-targets \
  --target-group-arn $TG_ARN \
  --targets Id=$INSTANCE_ID

echo "Waiting 90 seconds for alarm to fire..."
sleep 90

aws cloudwatch describe-alarms \
  --alarm-names "webservers-dev-unhealthy-hosts" \
  --query "MetricAlarms[0].StateValue" \
  --output text
```

Expected: `ALARM`

Re-register the instance to restore the cluster:

```bash
PORT=$(aws elbv2 describe-target-groups \
  --target-group-arns $TG_ARN \
  --query "TargetGroups[0].Port" \
  --output text)

aws elbv2 register-targets \
  --target-group-arn $TG_ARN \
  --targets Id=$INSTANCE_ID,Port=$PORT
```

---

### 10. Tear down (dev only — never destroy production without a plan)

```bash
cd Day16/live/dev/services/webserver-cluster
terraform destroy
```

Confirm the ALB is gone:

```bash
curl -s -o /dev/null -w "%{http_code}" http://$ALB_DNS
```

Expected: `000` (connection refused — no server exists).

> **Note:** Do not run `terraform destroy` in `live/bootstrap` — the `prevent_destroy`
> lifecycle rule will block it, but the state bucket and DynamoDB table should be
> treated as permanent infrastructure.
