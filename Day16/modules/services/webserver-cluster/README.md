# webserver-cluster module

A production-grade Auto Scaling Group behind an Application Load Balancer.
Includes CloudWatch alarms, a log group, SNS alerting, and a least-privilege IAM role.

## Features

- ALB with health-check-based ASG (`health_check_type = "ELB"`)
- `create_before_destroy` on all replaceable resources
- Consistent tagging via `common_tags` locals merged onto every resource
- Three CloudWatch alarms: high CPU, unhealthy hosts, ALB 5xx errors
- CloudWatch log group with configurable retention
- SNS topic for alarm notifications (optional email subscription)
- Input validation on every constrained variable
- No hardcoded values — all configuration via variables

## Usage

```hcl
module "webserver_cluster" {
  source = "../../modules/services/webserver-cluster"

  cluster_name  = "webservers-dev"
  environment   = "dev"
  project_name  = "my-project"
  team_name     = "platform-team"
  instance_type = "t3.micro"
  min_size      = 2
  max_size      = 4

  cpu_alarm_threshold = 80
  log_retention_days  = 30
  alarm_email         = "alerts@example.com"
}
```

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `cluster_name` | `string` | required | Name prefix for all resources. Lowercase alphanumeric + hyphens. |
| `environment` | `string` | required | `dev`, `staging`, or `production`. |
| `project_name` | `string` | `"terraform-challenge"` | Applied to all resource tags. |
| `team_name` | `string` | `"platform-team"` | Applied to all resource tags. |
| `instance_type` | `string` | `"t3.micro"` | Must be a `t2` or `t3` family type. |
| `min_size` | `number` | `2` | Minimum ASG instance count. |
| `max_size` | `number` | `4` | Maximum ASG instance count. |
| `server_port` | `number` | `8080` | Port the web server listens on (1024–65535). |
| `app_version` | `string` | `"v1"` | Rendered into the HTML response. |
| `cpu_alarm_threshold` | `number` | `80` | CPU % that triggers the high-CPU alarm. |
| `log_retention_days` | `number` | `30` | CloudWatch log retention in days. |
| `alarm_email` | `string` | `""` | Email for SNS alarm notifications. Leave empty to skip. |
| `secret_source` | `string` | `"none"` | `ssm`, `secretsmanager`, or `none`. |
| `secret_ref` | `string` | `""` | SSM parameter name or Secrets Manager ARN. |
| `secret_policy_arns` | `list(string)` | `[]` | IAM policy ARNs for secret access. |
| `custom_tags` | `map(string)` | `{}` | Extra tags merged onto all resources. |

## Outputs

| Name | Description |
|------|-------------|
| `alb_dns_name` | DNS name of the ALB. |
| `alb_arn` | ARN of the ALB. |
| `asg_name` | Auto Scaling Group name. |
| `instance_role_name` | IAM role name on instances. |
| `instance_profile_name` | IAM instance profile name. |
| `sns_topic_arn` | SNS topic ARN for alarm notifications. |
| `log_group_name` | CloudWatch log group name. |
| `web_sg_id` | Security group ID on EC2 instances. |
| `alb_sg_id` | Security group ID on the ALB. |

## Security notes

- Instances are only reachable through the ALB — no direct internet ingress on instance SG
- No secrets in `.tf` files; use `TF_VAR_*` env vars or a secrets module
- All sensitive variables must be marked `sensitive = true` in the calling module
- State should be stored in the `state-bucket` module with encryption enabled
