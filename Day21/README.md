# Day 21: The Seven-Step Workflow — Adding a Request-Count Alarm

Day 21 walks through the complete seven-step infrastructure workflow using a
concrete, minimal change: adding a fourth CloudWatch alarm (`high_request_count`)
to the webserver-cluster module and bumping `app_version` to `v4`.

---

## Directory Structure

```
Day21/
├── live/
│   ├── dev/services/webserver-cluster/
│   │   └── main.tf
│   └── production/services/webserver-cluster/
│       └── main.tf
├── modules/
│   └── services/webserver-cluster/
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       ├── user-data.sh
│       └── webserver_cluster_test.tftest.hcl
├── test/
│   ├── webserver_cluster_test.go
│   ├── go.mod
│   └── go.sum
├── .gitignore
└── README.md
```

---

## What Changed from Day 20

| Area | Day 20 | Day 21 |
|---|---|---|
| `app_version` default | `v3` | `v4` |
| CloudWatch alarms | 3 (high-cpu, unhealthy-hosts, alb-5xx) | 4 (+ high-request-count) |
| New variable | — | `request_count_alarm_threshold` |
| New output | — | `request_count_alarm_arn` |
| New unit test | — | `validate_request_count_alarm` |
| Integration test assertion | 12 outputs | 13 outputs (+ `request_count_alarm_arn`) |

---

## The Seven-Step Workflow

### Step 1 — Write the new code

Add the `request_count_alarm_threshold` variable, the
`aws_cloudwatch_metric_alarm.high_request_count` resource, and the
`request_count_alarm_arn` output. Bump `app_version` default to `v4`.

```hcl
# modules/services/webserver-cluster/variables.tf
variable "request_count_alarm_threshold" {
  description = "ALB request count per minute that triggers the high-traffic alarm."
  type        = number
  default     = 1000
}
```

```hcl
# modules/services/webserver-cluster/main.tf
resource "aws_cloudwatch_metric_alarm" "high_request_count" {
  alarm_name          = "${var.cluster_name}-high-request-count"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "RequestCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = var.request_count_alarm_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.example.arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}
```

### Step 2 — Run unit tests locally

```bash
cd Day21/modules/services/webserver-cluster
terraform init
terraform test
```

Expected output:

```
webserver_cluster_test.tftest.hcl... in progress
  run "validate_cluster_name"... pass
  run "validate_instance_type"... pass
  run "validate_server_port"... pass
  run "validate_asg_sizing"... pass
  run "validate_environment_tag"... pass
  run "validate_log_retention"... pass
  run "validate_alb_listener"... pass
  run "validate_cpu_alarm"... pass
  run "validate_request_count_alarm"... pass
  run "validate_app_version_v4"... pass
webserver_cluster_test.tftest.hcl... tearing down
webserver_cluster_test.tftest.hcl... pass

Success! 10 passed, 0 failed.
```

### Step 3 — Deploy to dev

```bash
cd Day21/live/dev/services/webserver-cluster
terraform init
terraform plan
terraform apply
```

Verify:

```bash
ALB=$(terraform output -raw alb_dns_name)
curl http://$ALB
# <h1>Hello World — <span class="badge">v4</span></h1>
```

### Step 4 — Run integration tests against dev

```bash
cd Day21/test
go mod download
go test -v -timeout 30m -run TestWebserverClusterIntegration ./...
```

The test deploys an isolated cluster, asserts all 13 outputs are present
(including `request_count_alarm_arn`), polls the ALB for HTTP 200 with
"Hello World" and "v4", then destroys everything.

### Step 5 — Open a pull request

Push the branch. The CI pipeline runs automatically:

1. `lint` — `terraform fmt -check` on modules and live configs
2. `unit-tests` — `terraform test` (plan-only, needs read-only AWS credentials)
3. `integration-tests` — Terratest (push to main only)

### Step 6 — Merge and promote to production

```bash
cd Day21/live/production/services/webserver-cluster
terraform init
terraform plan
terraform apply
```

Zero-downtime: `random_id.server` uses `app_version` as a keeper, so bumping
to `v4` generates a new ASG name. `create_before_destroy = true` and
`min_elb_capacity = min_size` ensure the new ASG is healthy before the old
one is destroyed.

### Step 7 — Verify and monitor

```bash
PROD_ALB=$(terraform output -raw alb_dns_name)
curl http://$PROD_ALB
# <h1>Hello World — <span class="badge">v4</span></h1>

aws cloudwatch describe-alarms \
  --alarm-name-prefix "webservers-prod" \
  --query "MetricAlarms[*].{Name:AlarmName,State:StateValue}"
```

---

## Module Variables

| Variable | Default | Description |
|---|---|---|
| `cluster_name` | required | Lowercase alphanumeric + hyphens |
| `environment` | required | `dev`, `staging`, or `production` |
| `app_version` | `v4` | Rendered into HTML; bump triggers zero-downtime replacement |
| `instance_type` | `t3.micro` | t2 or t3 family only |
| `min_size` | `1` | ASG minimum; also sets `min_elb_capacity` |
| `max_size` | `2` | ASG maximum |
| `cpu_alarm_threshold` | `80` | High-CPU alarm threshold (%) |
| `request_count_alarm_threshold` | `1000` | ALB requests/min that triggers the traffic alarm |
| `log_retention_days` | `30` | CloudWatch log group retention |
| `alarm_email` | `""` | SNS email subscription; leave empty to skip |
| `secret_source` | `none` | `ssm`, `secretsmanager`, or `none` |
| `secret_ref` | `""` | SSM parameter name or Secrets Manager ARN |

## Module Outputs

| Output | Description |
|---|---|
| `alb_dns_name` | ALB DNS name |
| `alb_arn` | ALB ARN |
| `asg_name` | ASG name (includes random suffix) |
| `instance_role_name` | IAM role name on instances |
| `instance_profile_name` | IAM instance profile name |
| `sns_topic_arn` | SNS topic for alarm notifications |
| `log_group_name` | CloudWatch log group (`/aws/ec2/<cluster_name>`) |
| `web_sg_id` | Security group on EC2 instances |
| `alb_sg_id` | Security group on the ALB |
| `high_cpu_alarm_arn` | High-CPU alarm ARN |
| `unhealthy_hosts_alarm_arn` | Unhealthy-hosts alarm ARN |
| `alb_5xx_alarm_arn` | ALB 5xx alarm ARN |
| `request_count_alarm_arn` | High request-count alarm ARN (new in Day 21) |

---

## CI/CD Pipeline

```
lint ──────────────────────────────────────────────────────────────────► pass/fail
unit-tests ────────────────────────────────────────────────────────────► pass/fail
integration-tests (push to main only, needs unit-tests + lint) ───────► pass/fail
```

The `integration-tests` job sets `terraform_wrapper: false` — required because
the wrapper injects extra output that breaks Terratest's stdout parser.

---

## Running Tests Locally

```bash
# Unit tests (plan-only, needs read-only AWS credentials)
cd Day21/modules/services/webserver-cluster
terraform init && terraform test

# Integration tests (deploys real AWS resources)
cd Day21/test
go mod download
go test -v -timeout 30m -run TestWebserverClusterIntegration ./...

# Validation tests (plan-only, no real resources)
go test -v -timeout 5m -run TestWebserverClusterValidation ./...
```
