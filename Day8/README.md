# Day 8 — Building Reusable Infrastructure with Terraform Modules

## Directory Structure

```
Day8/
├── modules/
│   └── services/
│       └── webserver-cluster/
│           ├── main.tf        # All resource definitions
│           ├── variables.tf   # Every configurable input
│           ├── outputs.tf     # Everything a caller might need
│           └── README.md      # Module usage docs
└── live/
    ├── dev/
    │   └── services/
    │       └── webserver-cluster/
    │           └── main.tf    # Calls module with dev values
    └── production/
        └── services/
            └── webserver-cluster/
                └── main.tf    # Calls module with production values
```

---

## Module Code

### variables.tf

```hcl
variable "cluster_name" {
  description = "The name to use for all cluster resources"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for the cluster instances"
  type        = string
  default     = "t3.micro"
}

variable "min_size" {
  description = "Minimum number of EC2 instances in the ASG"
  type        = number
}

variable "max_size" {
  description = "Maximum number of EC2 instances in the ASG"
  type        = number
}

variable "server_port" {
  description = "Port the web server listens on for HTTP traffic"
  type        = number
  default     = 8080
}

variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}
```

**Why each variable exists:**
- `cluster_name` — required, no default. Every resource name is prefixed with this so the module can be instantiated in dev and production in the same account without name collisions.
- `instance_type` — defaults to `t3.micro` . Dev uses the default; production overrides to `t3.micro`.
- `min_size` / `max_size` — required, no defaults. These are environment-specific business decisions — the module should not assume them.
- `server_port` — defaults to `8080`. Kept as a variable so the module is not tied to a specific port if reused for a different app.
- `region` — defaults to `us-east-1`. Callers can override for multi-region deployments.

### outputs.tf

```hcl
output "alb_dns_name" {
  value       = aws_lb.example.dns_name
  description = "The domain name of the load balancer"
}

output "asg_name" {
  value       = aws_autoscaling_group.example.name
  description = "The name of the Auto Scaling Group"
}

output "alb_arn" { ... }
output "target_group_arn" { ... }
output "web_sg_id" { ... }
```

---

## Calling Configurations

### dev (live/dev/services/webserver-cluster/main.tf)

```hcl
module "webserver_cluster" {
  source = "../../../../modules/services/webserver-cluster"

  cluster_name  = "webservers-dev"
  instance_type = "t3.micro"
  min_size      = 2
  max_size      = 4
}
```

### production (live/production/services/webserver-cluster/main.tf)

```hcl
module "webserver_cluster" {
  source = "../../../../modules/services/webserver-cluster"

  cluster_name  = "webservers-production"
  instance_type = "t3.micro"
  min_size      = 4
  max_size      = 10
}
```

Same module. Different inputs. Zero code duplication.

---

## Deployment Steps

```bash
# From the dev calling configuration directory
cd Day8/live/dev/services/webserver-cluster
terraform init
terraform apply

# Confirm the cluster is reachable
terraform output alb_dns_name
curl http://<alb_dns_name>

# Tear down when done
terraform destroy
```

---

## Module Design Decisions

**What is exposed as input variables vs kept internal:**
- Exposed: `cluster_name`, `instance_type`, `min_size`, `max_size`, `server_port`, `region` — these are the knobs that differ between environments or callers.
- Internal: VPC/subnet lookups, AMI resolution, security group rules, health check parameters, listener port (always 80). These are implementation details the caller should not need to care about.

**What outputs are defined and why:**
- `alb_dns_name` — the primary output; callers need this to reach the cluster.
- `asg_name` — needed if a caller wants to attach scaling policies or reference the ASG elsewhere.
- `alb_arn` / `target_group_arn` — needed if a caller wants to add HTTPS listeners or additional rules.
- `web_sg_id` — needed if a caller wants to add extra ingress rules (e.g., allow SSH from a bastion).

**What breaks without a required variable:**
- Missing `cluster_name`: Terraform errors at plan time — `Error: No value for required variable`. All resource names would be empty strings, causing AWS API errors.
- Missing `min_size` / `max_size`: Same — plan fails immediately before any API call is made.

---

## Refactoring Observations

Refactoring Days 3–5 into a module required:
1. Removing the `provider` block — modules must not declare providers; the caller owns that.
2. Replacing every hardcoded name (`"web-cluster-alb"`, `"web-cluster-sg"`) with `"${var.cluster_name}-alb"` etc.
3. Deciding what to expose vs keep internal — the health check thresholds stayed internal; `min_size`/`max_size` moved to variables.
4. Adding outputs that were missing in the original flat configs.

What stayed the same: the resource logic, the user_data script, the ALB→TG→listener wiring.

---

## Chapter 4 Learnings

**Root module vs child module:**
A root module is the working directory where you run `terraform apply` — it owns the provider and backend config. A child module is called via a `module` block; it receives inputs and returns outputs but has no provider of its own.

**What `terraform init` does with a new module source:**
It downloads or copies the module source into `.terraform/modules/` and records it in `.terraform/modules/modules.json`. You must re-run `init` every time you add or change a `source` path.

**Module outputs in state:**
Module outputs are stored under `module.<name>.output.<output_name>` in the state file. They are accessible to the root module as `module.<name>.<output_name>` and are tracked like any other resource attribute.

---

## Challenges and Fixes

| Problem | Fix |
|---------|-----|
| Relative `source` path wrong after nesting | Counted directory levels carefully — `../../../../modules/...` from `live/dev/services/webserver-cluster/` |
| ALB name too long (32-char AWS limit) | Kept `cluster_name` values short (`webservers-dev`, `webservers-production`) |
| Module outputs not accessible in root | Added `output` blocks in the calling `main.tf` that reference `module.webserver_cluster.<output>` |
| Provider block inside module | Removed it — provider belongs in the root calling config only |

---

