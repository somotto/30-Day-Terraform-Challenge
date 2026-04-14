# Day 22: Integrated CI/CD Pipeline with Sentinel Policies

Day 22 wires together everything from the challenge into a single, production-grade
pipeline: immutable plan artifact promotion, Sentinel policy enforcement, and a
full GitHub Actions workflow that gates every apply.

---

## Directory Structure

```
Day22/
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
├── sentinel/
│   ├── allowed-instance-types.sentinel
│   ├── cost-check.sentinel
│   └── require-terraform-tag.sentinel
├── test/
│   ├── webserver_cluster_test.go
│   ├── go.mod
│   └── go.sum
├── .gitignore
└── README.md
```

---

## What Changed from Day 21

| Area | Day 21 | Day 22 |
|---|---|---|
| `app_version` default | `v4` | `v5` |
| Sentinel policies | none | 3 policies (instance types, cost, tags) |
| CI pipeline | lint + unit + integration | validate + plan artifact + apply-dev + apply-prod + integration |
| Plan promotion | regenerated per env | immutable artifact promoted dev → prod |
| Unit test | 10 runs | 12 runs (+ `validate_managed_by_tag`, `validate_allowed_instance_type`) |
| Integration test assertion | `v4` in body | `v5` + `Sentinel: compliant` in body |

---

## Sentinel Policies

### `allowed-instance-types.sentinel` (hard-mandatory)

Blocks any `aws_instance` or `aws_launch_template` that uses an instance type
outside the `t2.*`, `t3.*`, `t3a.*` families. Prevents accidental deployment of
expensive instance families without a cost-approval PR.

### `require-terraform-tag.sentinel` (hard-mandatory)

Every taggable resource must carry `ManagedBy = "terraform"`. The module sets
this automatically via `local.common_tags`. Resources without a tags API
(inline policies, listener rules, etc.) are explicitly exempted.

### `cost-check.sentinel` (soft-mandatory)

Blocks applies where the estimated monthly cost delta exceeds $50 (dev/staging)
or $200 (production). Uses `tfrun.cost_estimate.delta_monthly_cost` — the net
change, not the total workspace cost.

---

## CI/CD Pipeline

```
validate ──► plan ──► apply-dev (push to main) ──► apply-prod (workflow_dispatch)
                 └──► integration-tests (push to main)
```

| Job | Trigger | What it does |
|---|---|---|
| `validate` | every PR + push | fmt check, init -backend=false, validate, `terraform test` |
| `plan` | after validate | real init + plan, uploads `ci.tfplan` artifact |
| `apply-dev` | push to main | downloads artifact, applies to dev |
| `apply-prod` | manual dispatch | downloads same artifact, applies to production |
| `integration-tests` | push to main | Terratest: deploy, assert, destroy |

The key pattern: `ci.tfplan` is produced once in `plan` and promoted through
environments. It is never regenerated — what was reviewed is exactly what gets
applied.

---

## Running Locally

```bash
# Unit tests 
cd Day22/modules/services/webserver-cluster
terraform init
terraform test

# Deploy to dev
cd Day22/live/dev/services/webserver-cluster
terraform init
terraform plan
terraform apply

# Integration tests 
cd Day22/test
go mod download
go test -v -timeout 30m -run TestWebserverCluster ./...

# Validation tests 
go test -v -timeout 5m -run TestWebserverClusterValidation ./...
```

---

## Module Variables

| Variable | Default | Description |
|---|---|---|
| `cluster_name` | required | Lowercase alphanumeric + hyphens |
| `environment` | required | `dev`, `staging`, or `production` |
| `app_version` | `v5` | Rendered into HTML; bump triggers zero-downtime replacement |
| `instance_type` | `t3.micro` | t3 family only (Sentinel enforced) |
| `min_size` | `1` | ASG minimum |
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
| `request_count_alarm_arn` | High request-count alarm ARN |
