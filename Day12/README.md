# Day 12: Zero-Downtime Deployments with Terraform

## What's implemented

### Module: `modules/services/webserver-cluster`

Builds on Day 11 with two zero-downtime strategies:

**1. Rolling update via `create_before_destroy`**

- `aws_launch_configuration` uses `name_prefix` + `lifecycle { create_before_destroy = true }`
- `random_id.server` regenerates when `app_version` (or AMI) changes, giving the ASG a unique name each deployment
- `min_elb_capacity = var.min_size` makes Terraform wait until the new ASG has healthy instances before destroying the old one

**2. Blue/Green via listener rule swap**

- When `enable_blue_green = true`, two target groups (`blue`, `green`) are created
- An `aws_lb_listener_rule` forwards to whichever slot `active_environment` points to
- Switching is a single atomic API call — no downtime window

---

## Zero-Downtime Rolling Update (dev)

```bash
cd live/dev/services/webserver-cluster
terraform init
terraform apply          # deploys v1

# In a second terminal — keep this running throughout:
while true; do curl -s http://; echo; sleep 2; done

# Back in the first terminal — edit main.tf: app_version = "v2"
terraform apply          # watch the loop: v1 → v2, no errors


  <head><title>webservers-dev [dev] v1</title></head>
  <body>
    <h1>Hello World v1</h1>
    <p>Cluster: webservers-dev</p>
    <p>Environment: dev</p>
    <p>Instance ID: i-08fe427f70cf2eb1c</p>
    <p>Availability Zone: us-east-1c</p>
  </body>
</html>

<!DOCTYPE html>
<html>
  <head><title>webservers-dev [dev] v2</title></head>
  <body>
    <h1>Hello World v2</h1>
    <p>Cluster: webservers-dev</p>
    <p>Environment: dev</p>
    <p>Instance ID: i-00c435c4cf516ceac</p>
    <p>Availability Zone: us-east-1c</p>
  </body>
</html>
```


## Blue/Green Switch (production)

```bash
cd live/production/services/webserver-cluster
terraform init
terraform apply          # blue is live (v1)

# Switch to green (v2) — single API call, no downtime:
# Edit main.tf: active_environment = "green"
terraform apply

<!DOCTYPE html>
<html>
  <head><title>webservers-prod [production] v1</title></head>
  <body>
    <h1>Hello World v1</h1>
    <p>Cluster: webservers-prod</p>
    <p>Environment: production</p>
    <p>Instance ID: i-02d0b5c6bc9abb7c9</p>
    <p>Availability Zone: us-east-1d</p>
  </body>
</html>

<!DOCTYPE html>
<html>
  <head><title>webservers-prod [production] v2</title></head>
  <body>
    <h1>Hello World v2</h1>
    <p>Cluster: webservers-prod</p>
    <p>Environment: production</p>
    <p>Instance ID: i-0442bb974ab0c65dc</p>
    <p>Availability Zone: us-east-1a</p>
  </body>
</html>

# Roll back instantly:
# Edit main.tf: active_environment = "blue"
terraform apply
```

## Why the default causes downtime

| Default behaviour | `create_before_destroy` |
|---|---|
| Destroy old ASG → instances terminated | Create new ASG → wait for healthy instances |
| Create new ASG → instances spin up | Destroy old ASG → traffic already on new |
| **Downtime window exists** | **No downtime window** |

The ASG naming problem: AWS rejects two ASGs with the same name. The `random_id` keyed on `app_version` ensures each deployment gets a unique name, making `create_before_destroy` viable.
