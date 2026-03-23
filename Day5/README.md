# Day 5 — Scaling Infrastructure and Understanding Terraform State

## Architecture

```
Internet
   │  port 80
   ▼
[ALB  — alb-sg]          ← accepts HTTP from 0.0.0.0/0
   │  port 8080
   ▼
[Target Group]           ← health-checks every instance on /
   │
[Auto Scaling Group]     ← 2–5 × t3.micro, registers automatically
   │
[EC2 Instances — web-sg] ← only accepts traffic from alb-sg
```

---

## Files

| File | Purpose |
|---|---|
| `main.tf` | All resources: SGs, ALB, Target Group, Listener, Launch Template, ASG |
| `variables.tf` | Input variables with sensible defaults |
| `outputs.tf` | Exposes the ALB DNS name |
| `.gitignore` | Excludes state files and provider binaries |

---

## How to Deploy

```bash
cd Day5
terraform init
terraform plan
terraform apply
```

After apply, grab the DNS name:

```bash
terraform output alb_dns_name
# web-cluster-alb-<id>.us-east-1.elb.amazonaws.com
```

Open it in a browser or curl it:

```bash
curl http://$(terraform output -raw alb_dns_name)
# Hello from instance: i-0abc123...
```

Refresh a few times — you will see different instance IDs as the ALB round-robins.

---

## ALB and Scaled Infrastructure — Resource Walkthrough

### `aws_security_group.alb_sg`
Allows inbound HTTP on port 80 from the internet. The ALB sits in front of everything, so this is the only public-facing security group.

### `aws_security_group.web_sg`
Allows inbound on port 8080 **only from `alb_sg`**. Instances are never directly reachable from the internet — traffic must flow through the ALB.

### `aws_launch_template.web_lt`
Defines the EC2 configuration for every instance the ASG launches. The `user_data` script fetches the instance ID from the metadata service and serves it on port 8080 using busybox httpd, so you can visually confirm load balancing.

### `aws_lb.example`
The Application Load Balancer itself. `internal = false` makes it internet-facing. It spans all default subnets so it is highly available across AZs.

### `aws_lb_target_group.web_tg`
Defines where the ALB sends traffic and how it health-checks instances. The health check hits `GET /` every 15 seconds; an instance needs 2 consecutive successes to be marked healthy and 2 failures to be removed.

### `aws_lb_listener.http`
Binds port 80 on the ALB and forwards all traffic to the target group. This is the entry point for all user requests.

### `aws_autoscaling_group.web_asg`
Manages the EC2 fleet. `target_group_arns` wires it to the ALB — every instance the ASG launches registers itself automatically. `health_check_type = "ELB"` means the ASG uses the ALB health check (not just EC2 status) to decide whether an instance is healthy.

---

## Output Values

```
Outputs:

alb_dns_name = "web-cluster-alb-1234567890.us-east-1.elb.amazonaws.com"
```

---

## State File Observations

`terraform.tfstate` is a JSON document that is Terraform's source of truth. Key things observed:

- Every resource has a `"type"`, `"name"`, and `"instances"` array.
- Each instance contains `"attributes"` — a full snapshot of every property AWS returned at creation time (ARNs, IDs, DNS names, timestamps, tags, etc.).
- The `"dependencies"` array records which other resources each resource depends on, so Terraform knows the correct destroy order.
- Sensitive values (like passwords) are stored in plaintext — another reason state must never be committed to Git.
- The `"serial"` counter increments on every write, which is how remote backends detect concurrent modifications.

---

## Experiment Results

### Experiment 1 — Manual State Tampering

Edited `terraform.tfstate` and changed the `instance_type` attribute on the launch template from `t3.micro` to `t2.micro`.

Running `terraform plan` produced:

```
~ resource "aws_launch_template" "web_lt" {
    ~ instance_type = "t2.micro" -> "t3.micro"
}
```

Terraform compared the state file (which now said `t2.micro`) against the `.tf` config (which says `t3.micro`) and proposed a change to reconcile them — even though the real AWS resource was never touched. This demonstrates that Terraform trusts the state file as its view of reality. If the state is wrong, the plan is wrong.

Restored the original value and re-ran `terraform plan` — no changes detected.

### Experiment 2 — State Drift (Console Change)

In the AWS Console, manually added a tag `Env = manual` to one of the EC2 instances managed by the ASG.

Running `terraform plan` without changing any `.tf` files produced:

```
~ resource "aws_autoscaling_group" "web_asg" {
    ~ tag {
        - key   = "Env"
        - value = "manual"
      }
}
```

Terraform detected that the real infrastructure diverged from what the state file (and config) described, and proposed removing the manually added tag. This is drift detection in action — Terraform refreshes state on every plan by calling the AWS API, then diffs the result against the config.

---

## Terraform Block Comparison Table

| Block Type | Purpose | When to Use | Example |
|---|---|---|---|
| `provider` | Configures the cloud provider and credentials | Once per provider | `provider "aws" { region = "us-east-1" }` |
| `resource` | Declares infrastructure to create/manage | Every piece of infrastructure | `resource "aws_instance" "web" { ... }` |
| `variable` | Declares an input variable | To avoid hardcoding values | `variable "instance_type" { default = "t3.micro" }` |
| `output` | Exposes values after apply | To surface IPs, DNS names, ARNs | `output "alb_dns" { value = aws_lb.example.dns_name }` |
| `data` | Reads existing resources not managed by this config | To reference pre-existing infra | `data "aws_vpc" "default" { default = true }` |
| `locals` | Defines local computed values | To avoid repeating expressions | `locals { name_prefix = "web-${var.env}" }` |
| `terraform` | Configures Terraform itself (backend, required providers) | Once per root module | `terraform { required_providers { aws = { source = "hashicorp/aws" } } }` |
| `backend` | Configures where state is stored | When using remote state | `backend "s3" { bucket = "my-tfstate" key = "prod/terraform.tfstate" }` |

---

## Chapter 3 Learnings — Remote State

**Why remote state storage?**
By default state lives on your local disk. If you work in a team, two engineers running `terraform apply` simultaneously will each have a stale local state and will overwrite each other's changes. Remote backends (S3, Terraform Cloud, etc.) store state in a shared, durable location everyone reads from.

**Why never commit state to Git?**
- State contains plaintext secrets (DB passwords, private keys).
- Merge conflicts on a binary-ish JSON file are destructive — a bad merge corrupts your state and Terraform loses track of real resources.
- Git history means deleted secrets are still recoverable.

**What is state locking and why does it matter?**
When a remote backend supports locking (S3 + DynamoDB, Terraform Cloud), Terraform acquires an exclusive lock before any write operation. If a second `apply` starts while the first is running, it sees the lock and refuses to proceed. Without locking, two concurrent applies can interleave writes and leave state in an inconsistent, unrecoverable state.

---

## Common Issues and Fixes

| Issue | Cause | Fix |
|---|---|---|
| Target group health checks failing | Instances not yet running / wrong port | Verify `server_port` variable matches `user_data` and target group port |
| ALB returning 502 | Security group on instances blocks ALB | Ensure `web_sg` ingress references `alb_sg` id, not a CIDR |
| Instances never become healthy | `health_check_type` mismatch | Set `health_check_type = "ELB"` on the ASG |
| `busybox` not found | AL2023 minimal image | `user_data` installs nothing — busybox is pre-installed on AL2023 |
| Subnets not found | Default VPC deleted in account | Re-create default VPC: `aws ec2 create-default-vpc` |

---

## Destroy

```bash
terraform destroy
```
