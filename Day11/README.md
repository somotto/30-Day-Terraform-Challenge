# Day 11: Mastering Terraform Conditionals — Smarter, More Flexible Deployments

## Structure

```
Day11/
├── modules/services/webserver-cluster/
│   ├── main.tf        # resources + conditional data sources
│   ├── variables.tf   # inputs with validation block
│   ├── outputs.tf     # safe conditional output references
│   └── user-data.sh
└── live/
    ├── dev/services/webserver-cluster/main.tf
    └── production/services/webserver-cluster/main.tf
```

---

## Locals-Centralised Conditional Logic

All conditional decisions live in `locals {}`. Resource blocks only reference
locals — no raw ternary operators scattered in resource arguments.

```hcl
locals {
  is_production = var.environment == "production"

  instance_type    = local.is_production ? "t3.small" : "t3.micro"
  min_cluster_size = local.is_production ? 3 : 1
  max_cluster_size = local.is_production ? 10 : 3
  enable_monitoring  = local.is_production ? true : var.enable_detailed_monitoring
  enable_autoscaling = local.is_production ? true : var.enable_autoscaling
  deletion_policy    = local.is_production ? "Retain" : "Delete"
}
```

This is better than scattering ternaries across resource blocks because every
conditional decision is visible in one place. When a threshold changes, you
update one line in locals rather than hunting through every resource.

---

## Conditional Resource Creation

```hcl
resource "aws_autoscaling_policy" "scale_out" {
  count = local.enable_autoscaling ? 1 : 0
  ...
}

resource "aws_cloudwatch_metric_alarm" "high_cpu_alert" {
  count = local.enable_monitoring ? 1 : 0
  ...
}
```

Dev plan (autoscaling and monitoring disabled):
```
# aws_autoscaling_policy.scale_out — not created (count = 0)
# aws_autoscaling_policy.scale_in  — not created (count = 0)
# aws_cloudwatch_metric_alarm.high_cpu       — not created (count = 0)
# aws_cloudwatch_metric_alarm.low_cpu        — not created (count = 0)
# aws_cloudwatch_metric_alarm.high_cpu_alert — not created (count = 0)

Plan: 8 to add, 0 to change, 0 to destroy.
```

Production plan (autoscaling and monitoring forced on by `is_production`):
```
# aws_autoscaling_policy.scale_out[0]              — will be created
# aws_autoscaling_policy.scale_in[0]               — will be created
# aws_cloudwatch_metric_alarm.high_cpu[0]          — will be created
# aws_cloudwatch_metric_alarm.low_cpu[0]           — will be created
# aws_cloudwatch_metric_alarm.high_cpu_alert[0]    — will be created

Plan: 13 to add, 0 to change, 0 to destroy.
```

---

## Safe Output References

```hcl
# Wrong — errors at plan time when count = 0 (index out of range):
output "scale_out_policy_arn" {
  value = aws_autoscaling_policy.scale_out[0].arn
}

# Correct — ternary guard mirrors the resource's count condition:
output "scale_out_policy_arn" {
  value = local.enable_autoscaling ? aws_autoscaling_policy.scale_out[0].arn : null
}

output "high_cpu_alert_arn" {
  value = local.enable_monitoring ? aws_cloudwatch_metric_alarm.high_cpu_alert[0].arn : null
}
```

Without the guard, Terraform throws `Invalid index` at plan time even though
the resource simply doesn't exist. The guard returns `null` cleanly instead.

---

## Environment-Aware Module

The `environment` variable drives all decisions. Dev and production calling
configs pass only `environment` — the module handles the rest.

| Decision          | dev       | production |
|-------------------|-----------|------------|
| instance_type     | t3.micro  | t3.small  |
| min_cluster_size  | 1         | 3          |
| max_cluster_size  | 3         | 10         |
| autoscaling       | false     | true       |
| monitoring        | false     | true       |
| deletion_policy   | Delete    | Retain     |

---

## Input Validation Block

```hcl
variable "environment" {
  description = "Deployment environment: dev, staging, or production"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be dev, staging, or production."
  }
}
```

Passing an invalid value:
```
$ terraform plan -var="environment=prod"

╷
│ Error: Invalid value for variable
│
│ Environment must be dev, staging, or production.
╵
```

Fires at plan time before any API calls — bad inputs are caught immediately
with a clear message.

---

## Conditional Data Source Pattern

```hcl
# Greenfield — use the account's default VPC
data "aws_vpc" "default" {
  count   = var.use_existing_vpc ? 0 : 1
  default = true
}

# Brownfield — look up an existing VPC by tag
data "aws_vpc" "existing" {
  count = var.use_existing_vpc ? 1 : 0
  tags  = { Name = "existing-vpc" }
}

locals {
  vpc_id = var.use_existing_vpc ? data.aws_vpc.existing[0].id : data.aws_vpc.default[0].id
}
```

`use_existing_vpc = false` (greenfield): module creates or uses the default VPC —
good for fresh accounts and sandbox environments.

`use_existing_vpc = true` (brownfield): module looks up a VPC already managed
by a platform team — good for enterprise accounts where networking is owned
separately.

---

## Chapter 5 Learnings

A conditional expression (`condition ? true_val : false_val`) chooses between
two values — a string, a number, an attribute. It always produces exactly one
value and is valid anywhere an expression is accepted.

Conditional resource creation (`count = condition ? 1 : 0`) controls whether
a resource exists at all. When count is 0 the resource is absent from state;
when count is 1 it exists. The result is a list, which is why you need `[0]`
to access it and a ternary guard in outputs.

You cannot use a conditional to choose between two different resource *types*.
Terraform's resource type is fixed at write time — you cannot write
`resource (condition ? "aws_instance" : "aws_s3_bucket") "x" {}`. The
workaround is to define both types with `count = condition ? 1 : 0` so exactly
one is created.

---

## Challenges and Fixes

**Index-out-of-range on outputs** — referencing `aws_autoscaling_policy.scale_out[0].arn`
directly in an output errored when `enable_autoscaling = false`. Fix: wrap
every conditional resource reference in a ternary guard that mirrors the
resource's count condition.

**Data source count guard** — `data.aws_vpc.default` with `count = 0` produces
an empty list. Referencing it without an index errors. Same fix: use the
ternary in locals — `var.use_existing_vpc ? data.aws_vpc.existing[0].id : data.aws_vpc.default[0].id`.

**Validation block** — early draft used chained `||` comparisons. Switched to
`contains([...], var.environment)` which is cleaner and easier to extend.
