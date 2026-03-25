# Day 10: Terraform Loops and Conditionals — Dynamic Infrastructure at Scale

## Directory Structure

```
Day10/
├── iam/
│   └── main.tf                          # count, for_each, for expressions on IAM users
└── modules/
    └── services/
        └── webserver-cluster/
            ├── main.tf                  # Module: conditionals + for_each + dynamic blocks
            ├── variables.tf
            ├── outputs.tf
            └── user-data.sh
└── live/
    ├── dev/
    │   └── services/
    │       └── webserver-cluster/
    │           └── main.tf              # Dev caller: autoscaling on, t3.micro via conditional
    └── production/
        └── services/
            └── webserver-cluster/
                └── main.tf              # Prod caller: autoscaling on, t3.small via conditional
```

---

## Concepts

### 1. `count` — identical copies

Creates N identical resources. `count.index` gives the zero-based position.

```hcl
resource "aws_iam_user" "count_example" {
  count = var.user_count
  name  = "day10-count-user-${count.index}"
}
```

**The fragility problem:** if you use `count` with a list and remove an element from the middle, Terraform renumbers every subsequent index and destroys/recreates those resources. This is why `for_each` exists.

---

### 2. `for_each` with a set — safe removal

Each resource is keyed by its string value, not a numeric index. Removing one entry only destroys that one resource.

```hcl
resource "aws_iam_user" "set_example" {
  for_each = var.user_names_set   # set(string)
  name     = "day10-set-${each.value}"
}
```

---

### 3. `for_each` with a map — per-item configuration

`each.key` is the map key, `each.value` is the value object. Lets you give each resource different configuration.

```hcl
resource "aws_iam_user" "map_example" {
  for_each = var.users   # map(object({ department = string, admin = bool }))
  name     = "day10-map-${each.key}"

  tags = {
    Department = each.value.department
    Admin      = tostring(each.value.admin)
  }
}
```

---

### 4. Conditionals with `count`

`count = condition ? 1 : 0` is the standard pattern for optional resources. When `false`, the resource is not created at all.

```hcl
resource "aws_autoscaling_policy" "scale_out" {
  count = var.enable_autoscaling ? 1 : 0
  # ...
}
```

When referencing a conditional resource elsewhere, use index `[0]`:

```hcl
alarm_actions = [aws_autoscaling_policy.scale_out[0].arn]
```

---

### 5. Conditionals with `locals`

Keep ternary logic out of resource blocks by resolving it in `locals`. Resource blocks stay readable.

```hcl
locals {
  instance_type = var.instance_type != null ? var.instance_type : (
    var.environment == "production" ? "t3.medium" : "t3.micro"
  )
}

resource "aws_launch_template" "web_lt" {
  instance_type = local.instance_type   # clean — no ternary here
}
```

---

### 6. `for_each` on security group rules

Lets callers inject extra rules without modifying the module. The module defines the baseline; callers extend it via a map variable.

```hcl
# In the module
resource "aws_security_group_rule" "alb_extra_ingress" {
  for_each          = var.extra_alb_ingress_rules
  type              = "ingress"
  security_group_id = aws_security_group.alb_sg.id
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  protocol          = each.value.protocol
  cidr_blocks       = each.value.cidr_blocks
}
```

```hcl
# In the caller
extra_alb_ingress_rules = {
  https = {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

---

### 7. `dynamic` blocks

Collapses repeated nested blocks (like ASG `tag {}`) into a single loop. Avoids copy-paste for every tag.

```hcl
dynamic "tag" {
  for_each = local.base_tags
  content {
    key                 = tag.key
    value               = tag.value
    propagate_at_launch = true
  }
}
```

---

### 8. `for` expressions — reshaping collections

`for` expressions transform collections. They do not create resources.

```hcl
# List of uppercase names
output "upper_names" {
  value = [for name in var.user_names_set : upper(name)]
}

# Map of username → ARN
output "user_arns" {
  value = { for name, user in aws_iam_user.map_example : name => user.arn }
}

# Filter: only admin users
output "admin_users" {
  value = [for name, cfg in var.users : name if cfg.admin]
}
```

## IAM Demo (`iam/main.tf`)

Standalone file that demonstrates all loop constructs on IAM users — no module involved.

| Section | Construct | Key point |
|---------|-----------|-----------|
| 1 | `count` | Simple N copies, `count.index` |
| 2 | `count` + list | Fragile — removal renumbers indexes |
| 3 | `for_each` + set | Safe removal — keyed by value |
| 4 | `for_each` + map | Per-item config via `each.key`/`each.value` |
| 5 | `for` expressions | Outputs only — reshape, filter, transform |

---

## Deployment Steps

```bash
# IAM demo
cd Day10/iam
terraform init
terraform plan
terraform apply

# Dev cluster
cd Day10/live/dev/services/webserver-cluster
terraform init
terraform apply
terraform output alb_dns_name

# Production cluster
cd Day10/live/production/services/webserver-cluster
terraform init
terraform apply
terraform output instance_type_used 
```

---

## Challenges and Fixes

| Problem | Fix |
|---------|-----|
| `count` conditional resource referenced without index | Used `resource[0].arn` — required when `count` may be 0 or 1 |
| `for_each` on a `list` instead of `set`/`map` | Converted to `toset()` or used a `map` — `for_each` does not accept lists |
| `required_providers` in child module causing version conflict | Removed it — root module owns provider constraints |
| `dynamic` block iterator name collision | Used explicit `iterator` argument to rename the loop variable when the block label is ambiguous |
| Tags on ASG instances not propagating | Added `propagate_at_launch = true` inside each `tag` block in the `dynamic` loop |
