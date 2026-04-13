# Day 20: Putting It All Together — The Complete Terraform Workflow

Day 20 is the capstone. Every concept from the previous 19 days remote state,
modules, workspaces, secrets management, testing, and CI/CD is combined into a
single, production-grade workflow for deploying and updating a versioned web
application cluster.

---

## Directory Structure

```
Day20/
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

## The Seven-Step Application Deployment Workflow

This is the core of Day 20. The workflow describes how to safely deploy a new
application version (`v3`) to dev, verify it, then promote to production — with
zero downtime.

### Step 1 — Write the new code

Bump `app_version` to `v3` in the module default and in both live configs. The
`random_id.server` resource uses `app_version` as a keeper, so a version change
forces a new ASG name, which triggers `create_before_destroy` — the new ASG
comes up before the old one is torn down.

```hcl
# modules/services/webserver-cluster/variables.tf
variable "app_version" {
  default = "v3"
}
```

### Step 2 — Run unit tests locally

```bash
cd Day20/modules/services/webserver-cluster
terraform init
terraform test
```

Expected output:

```
webserver_cluster_test.tftest.hcl... in progress
  run "validate_cluster_name"... pass  # asserts on name_prefix (known at plan)
  run "validate_instance_type"... pass
  run "validate_server_port"... pass
  run "validate_asg_sizing"... pass
  run "validate_environment_tag"... pass
  run "validate_log_retention"... pass
  run "validate_alb_listener"... pass
  run "validate_cpu_alarm"... pass
  run "validate_app_version_v3"... pass
webserver_cluster_test.tftest.hcl... tearing down
webserver_cluster_test.tftest.hcl... pass

Success! 9 passed, 0 failed.
```

### Step 3 — Deploy to dev

```bash
cd Day20/live/dev/services/webserver-cluster
terraform init
terraform plan
terraform apply
```

Verify the response:

```bash
ALB=$(terraform output -raw alb_dns_name)
curl http://$ALB
# <h1>Hello World — <span class="badge">v3</span></h1>
```

### Step 4 — Run integration tests against dev

```bash
cd Day20/test
go mod download
go test -v -timeout 30m -run TestWebserverClusterIntegration ./...
```

The test deploys an isolated cluster, polls the ALB until it returns HTTP 200
with "Hello World", asserts all outputs are present, then destroys everything.

### Step 5 — Open a pull request

Push the branch. The CI pipeline runs automatically:

1. `lint` — `terraform fmt -check` on modules and live configs
2. `unit-tests` — `terraform test` against the module
3. `integration-tests` — Terratest (only on merge to main, not on every PR)

### Step 6 — Merge and promote to production

After the PR is approved and merged, deploy to production:

```bash
cd Day20/live/production/services/webserver-cluster
terraform init
terraform plan
terraform apply
```

Because `min_elb_capacity = min_size`, Terraform waits until the new ASG has at
least `min_size` healthy targets registered in the ALB before it destroys the
old ASG. Traffic is never interrupted.

### Step 7 — Verify and monitor

```bash
PROD_ALB=$(terraform output -raw alb_dns_name)
curl http://$PROD_ALB
# <h1>Hello World — <span class="badge">v3</span></h1>
```

Check CloudWatch alarms:

```bash
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
| `app_version` | `v3` | Rendered into the HTML response; version bump triggers zero-downtime replacement |
| `instance_type` | `t3.micro` |  t3 family only |
| `min_size` | `2` | ASG minimum; also sets `min_elb_capacity` |
| `max_size` | `4` | ASG maximum |
| `cpu_alarm_threshold` | `80` | CloudWatch high-CPU alarm threshold (%) |
| `log_retention_days` | `30` | CloudWatch log group retention |
| `alarm_email` | `""` | SNS email subscription for alarms |
| `secret_source` | `none` | `ssm`, `secretsmanager`, or `none` |
| `secret_ref` | `""` | SSM parameter name or Secrets Manager ARN |

## Module Outputs

| Output | Description |
|---|---|
| `alb_dns_name` | ALB DNS name — open in browser to verify |
| `alb_arn` | ALB ARN |
| `asg_name` | ASG name (includes random suffix for zero-downtime replacement) |
| `instance_role_name` | IAM role name on instances |
| `instance_profile_name` | IAM instance profile name |
| `sns_topic_arn` | SNS topic for CloudWatch alarm notifications |
| `log_group_name` | CloudWatch log group (`/aws/ec2/<cluster_name>`) |
| `web_sg_id` | Security group on EC2 instances |
| `alb_sg_id` | Security group on the ALB |

---

## Zero-Downtime Deployment Mechanism

The module achieves zero-downtime version upgrades through three cooperating
mechanisms:

1. `random_id.server` uses `app_version` as a keeper. Changing `app_version`
   generates a new hex suffix, which changes the ASG name.

2. `aws_autoscaling_group.example` has `create_before_destroy = true`. Terraform
   creates the new ASG (with the new launch template) before destroying the old
   one.

3. `min_elb_capacity = var.min_size` tells Terraform to wait until the new ASG
   has at least `min_size` healthy instances registered in the target group
   before proceeding with the destroy. This is the key safety gate — it prevents
   Terraform from tearing down the old ASG while the new one is still warming up.

Without `min_elb_capacity`, Terraform would destroy the old ASG the moment the
new one exists, regardless of whether any new instances are healthy yet.

---

## CI/CD Pipeline

### File: `.github/workflows/terraform-day20.yml`

Three jobs run in order:

```
lint ──────────────────────────────────────────────────────────────────► pass/fail
unit-tests ────────────────────────────────────────────────────────────► pass/fail
integration-tests (push to main only, needs unit-tests + lint) ───────► pass/fail
```

The `lint` job runs `terraform fmt -check -recursive` on both `modules/` and
`live/`. It does not need AWS credentials.

The `unit-tests` job runs `terraform test` (plan-only). It needs read-only AWS
credentials to resolve `data "aws_vpc"`, `data "aws_subnets"`, and
`data "aws_ami"`.

The `integration-tests` job only runs on push to main (not on PRs). It runs
`go test -v -timeout 30m` which deploys a real cluster, polls the ALB, and
destroys everything via `defer terraform.Destroy`. The
`terraform_wrapper: false` setting is required — the wrapper adds extra output
that breaks Terratest's stdout parser.

---

## Running Tests Locally

### Unit tests (no real AWS resources)

```bash
cd Day20/modules/services/webserver-cluster
terraform init
terraform test
```

### Integration tests (deploys real AWS resources)

```bash
cd Day20/test
go mod download
go test -v -timeout 30m -run TestWebserverClusterIntegration ./...
```

### Validation tests (plan-only, verifies variable validation rules)

```bash
cd Day20/test
go test -v -timeout 5m -run TestWebserverClusterValidation ./...
```

---

## What Each Day Contributed to This Capstone

| Day | Concept | Where it appears in Day 20 |
|---|---|---|
| 3–5 | EC2, ASG, ALB basics | `modules/services/webserver-cluster/main.tf` |
| 6–7 | Remote state, workspaces | S3 backend block (commented, ready to enable) |
| 8–9 | Modules | `live/*/main.tf` calling the shared module |
| 10–11 | Module inputs/outputs, versioning | `variables.tf`, `outputs.tf` |
| 12 | Zero-downtime deployments | `random_id` keeper + `create_before_destroy` + `min_elb_capacity` |
| 13 | Secrets management | `secret_source` / `secret_ref` variables + IAM policy attachment |
| 14–15 | Multi-region, multi-account | Pattern established; Day 20 uses single-region for clarity |
| 16 | Terragrunt-style state isolation | Separate state per environment in `live/` |
| 17 | State migration, import | `terraform import` workflow documented |
| 18 | Automated testing | `terraform test` unit tests + Terratest integration tests |
| 19 | Team adoption, Terraform Cloud | Remote backend block ready to uncomment |
| 20 | Everything together | Seven-step workflow, CI/CD, v3 deployment |

---

## Common Issues

### `min_elb_capacity` timeout during apply

```
Error: timeout waiting for ELB capacity
```

The new ASG instances are not passing health checks within the default timeout.
Check: security group rules allow ALB → instance traffic on `server_port`,
user-data.sh started the HTTP server, and the target group health check path
returns 200.

### `terraform test` fails with credential errors

```
Error: No valid credential sources found
```

`terraform test` with `command = plan` still resolves data sources, which
requires AWS credentials. Export `AWS_ACCESS_KEY_ID` and
`AWS_SECRET_ACCESS_KEY` before running, or use an IAM role.

### Terratest panic on output parsing

```
panic: runtime error: invalid memory address or nil pointer dereference
```

Set `terraform_wrapper: false` in the `hashicorp/setup-terraform` step. The
wrapper injects extra output that Terratest cannot parse.
