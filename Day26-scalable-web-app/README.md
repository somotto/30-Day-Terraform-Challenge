# Day 26 — Scalable Web Application with Auto Scaling on AWS

Deploys a production-grade, load-balanced web application tier using three
reusable Terraform modules: EC2 Launch Template, Application Load Balancer,
and Auto Scaling Group with CloudWatch-driven scaling policies.

## Architecture

```
Internet
   │
   ▼
[ALB] ──── HTTP :80 ──── [Target Group]
                               │
                    ┌──────────┴──────────┐
                    ▼                     ▼
              [EC2 Instance]       [EC2 Instance]
              (AZ us-east-1a)     (AZ us-east-1b)
                    └──────────┬──────────┘
                               │
                          [ASG web]
                               │
                    ┌──────────┴──────────┐
                    ▼                     ▼
           [CW Alarm cpu-high]   [CW Alarm cpu-low]
           scale-out @ 70% CPU   scale-in @ 30% CPU
```

## Project Structure

```
Day26-scalable-web-app/
├── modules/
│   ├── ec2/          # Launch Template + instance security group
│   ├── alb/          # ALB, target group, HTTP listener, request-count alarm
│   └── asg/          # ASG, scaling policies, CPU alarms, CloudWatch dashboard
├── envs/
│   └── dev/
│       ├── backend.tf
│       ├── provider.tf
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── terraform.tfvars

```

## Module Data Flow

```
module.ec2.launch_template_id      ──► module.asg (launch_template_id)
module.ec2.launch_template_version ──► module.asg (launch_template_version)
module.alb.target_group_arn        ──► module.asg (target_group_arns)
module.asg.asg_name                ──► CloudWatch alarms (AutoScalingGroupName dimension)
```

## Deploy

```bash
cd envs/dev

vim terraform.tfvars

terraform init
terraform validate
terraform plan
terraform apply

terraform output alb_dns_name
```

Open the ALB DNS name in your browser — you should see:

> Deployed with Terraform — environment: dev

## Auto Scaling Behaviour

| Condition | Action |
|-----------|--------|
| Average CPU ≥ 70% for 4 min (2 × 2-min periods) | Add 1 instance (cooldown 300 s) |
| Average CPU ≤ 30% for 4 min | Remove 1 instance (cooldown 300 s) |
| ALB RequestCountPerTarget ≥ 1000 in 60 s | CloudWatch alarm fires (informational — wire to scale-out policy if desired) |

`health_check_type = "ELB"` means the ASG uses the ALB health check result to
decide whether an instance is healthy. Without it, the ASG only checks that the
EC2 instance is running (EC2 status check), which can leave unhealthy app
instances in rotation.

## CloudWatch Dashboard

After apply, open the AWS Console → CloudWatch → Dashboards →
`web-asg-dev` to see CPU utilization graphed against the 70 % / 30 % thresholds
alongside the live instance count.

## Cleanup

```bash
terraform destroy
```

`force_delete = true` is set automatically for non-production environments so
the ASG terminates immediately without waiting for instance drain.
