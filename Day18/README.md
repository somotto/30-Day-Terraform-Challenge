# Day 18: Automated Testing of Terraform Code

## What You Will Accomplish

Manual testing does not scale. Today I implement all three layers of Terraform automated testing — unit, integration, and end-to-end — and wire them into a CI/CD pipeline that runs on every commit.

---

## Directory Structure

```
Day18/
├── .github/
│   └── workflows/
│       └── terraform-test.yml          # CI/CD pipeline
├── modules/
│   └── services/
│       └── webserver-cluster/
│           ├── main.tf                 # Module resources
│           ├── variables.tf            # Input variables with validation
│           ├── outputs.tf              # Output values
│           ├── user-data.sh            # EC2 bootstrap script
│           └── webserver_cluster_test.tftest.hcl  # Unit tests
├── test/
│   ├── webserver_cluster_test.go       # Integration tests (Terratest)
│   ├── e2e_test.go                     # End-to-end tests (Terratest)
│   └── go.mod                          # Go module dependencies
├── .gitignore
└── README.md
```

---

## Layer 1: Unit Tests with `terraform test`

### File: `modules/services/webserver-cluster/webserver_cluster_test.tftest.hcl`

```hcl
variables {
  cluster_name        = "test-cluster"
  instance_type       = "t3.micro"
  min_size            = 1
  max_size            = 2
  environment         = "dev"
  app_version         = "v1-test"
  cpu_alarm_threshold = 90
  log_retention_days  = 7
}

run "validate_cluster_name" {
  command = plan
  assert {
    condition     = startswith(aws_autoscaling_group.example.name, "test-cluster-asg-")
    error_message = "ASG name must start with '<cluster_name>-asg-'"
  }
}
# ... (7 run blocks total — see the full file)
```

### What each run block tests and why it matters

| run block | What it asserts | Why it matters |
|---|---|---|
| `validate_cluster_name` | ASG name starts with `<cluster_name>-asg-`, launch template prefix is `<cluster_name>-lt-` | Naming convention regressions break downstream references and cost allocation |
| `validate_instance_type` | Launch template `instance_type` matches the variable | Wrong instance type silently deploys expensive hardware |
| `validate_server_port` | Target group port and SG ingress rule both equal `server_port` | Port mismatch causes ALB health checks to fail — silent traffic blackhole |
| `validate_asg_sizing` | `min_size`, `max_size`, `min_elb_capacity` match variables | `min_size=0` lets the cluster scale to zero; `max < min` prevents any launch |
| `validate_environment_tag` | ALB carries `Environment` tag, ASG Name tag is correct | Tags drive cost allocation and IAM condition keys |
| `validate_log_retention` | Log group retention equals `log_retention_days`, name follows convention | Unset retention defaults to "never expire" — unbounded cost |
| `validate_alb_listener` | Listener is port 80, protocol HTTP, action is `forward` | Wrong listener config drops all traffic at the load balancer |
| `validate_cpu_alarm` | Alarm threshold matches variable, evaluation_periods is 2 | Threshold of 0 or 100 makes the alarm useless; 1 period causes flapping |

### How to run

```bash
cd Day18/modules/services/webserver-cluster
terraform init
terraform test
```

### Sample output

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
webserver_cluster_test.tftest.hcl... tearing down
webserver_cluster_test.tftest.hcl... pass

Success! 8 passed, 0 failed.
```

---

## Layer 2: Integration Tests with Terratest

### File: `test/webserver_cluster_test.go`

```go
func TestWebserverClusterIntegration(t *testing.T) {
    t.Parallel()

    uniqueID    := random.UniqueId()
    clusterName := fmt.Sprintf("test-%s", uniqueID)

    terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
        TerraformDir: "../modules/services/webserver-cluster",
        Vars: map[string]interface{}{
            "cluster_name":  clusterName,
            "instance_type": "t3.micro",
            "min_size":      1,
            "max_size":      2,
            "environment":   "dev",
        },
    })

    defer terraform.Destroy(t, terraformOptions)  // <-- the safety net

    terraform.InitAndApply(t, terraformOptions)

    albDnsName := terraform.Output(t, terraformOptions, "alb_dns_name")
    url        := fmt.Sprintf("http://%s", albDnsName)

    http_helper.HttpGetWithRetry(t, url, nil, 200, "Hello World", 30, 10*time.Second)
}
```

### What `defer terraform.Destroy` guarantees

Go's `defer` executes when the surrounding function returns — whether it returns normally, via `t.Fatal`, or via a panic. This means:

- If the HTTP assertion fails → `terraform destroy` still runs
- If the test times out → `terraform destroy` still runs
- If the test panics → `terraform destroy` still runs

Without `defer`, a failed test leaves orphaned AWS resources running indefinitely. An ALB + ASG + CloudWatch alarms left running for a week can cost $50–$100. `defer terraform.Destroy` is the single most important safety mechanism in Terratest.

### How to run

```bash
cd Day18/test
go mod download
go test -v -timeout 30m -run TestWebserverClusterIntegration ./...
```

### Sample output

```
=== RUN   TestWebserverClusterIntegration
=== PAUSE TestWebserverClusterIntegration
=== CONT  TestWebserverClusterIntegration
TestWebserverClusterIntegration 2026-04-04T10:00:00Z terraform [init]
TestWebserverClusterIntegration 2026-04-04T10:00:15Z terraform [apply]
...
TestWebserverClusterIntegration 2026-04-04T10:08:30Z http_helper.HttpGetWithRetry: attempt 1 of 30
TestWebserverClusterIntegration 2026-04-04T10:08:40Z http_helper.HttpGetWithRetry: attempt 2 of 30
TestWebserverClusterIntegration 2026-04-04T10:09:10Z Got expected status code 200 and body containing "Hello World"
TestWebserverClusterIntegration 2026-04-04T10:09:10Z terraform [destroy]
--- PASS: TestWebserverClusterIntegration (9m10s)
PASS
ok      github.com/your-org/day18-terraform-tests       550.123s
```

---

## Layer 3: End-to-End Tests

### File: `test/e2e_test.go`

The E2E test deploys the full application stack and verifies the complete request path: DNS → ALB → target group → EC2 → Python HTTP server → HTTP 200 with correct body.

```go
func TestFullStackEndToEnd(t *testing.T) {
    t.Parallel()
    uniqueID    := random.UniqueId()
    clusterName := fmt.Sprintf("e2e-%s", uniqueID)

    appOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
        TerraformDir: "../modules/services/webserver-cluster",
        Vars: map[string]interface{}{
            "cluster_name": clusterName,
            "environment":  "dev",
            // ...
        },
    })

    defer terraform.Destroy(t, appOptions)
    terraform.InitAndApply(t, appOptions)

    albDnsName := terraform.Output(t, appOptions, "alb_dns_name")
    url        := fmt.Sprintf("http://%s", albDnsName)

    http_helper.HttpGetWithRetryWithCustomValidation(t, url, nil, 30, 10*time.Second,
        func(statusCode int, body string) bool {
            return statusCode == 200 && len(body) > 0
        },
    )

    _, body := http_helper.HttpGet(t, url, nil)
    assert.Contains(t, body, clusterName)
    assert.Contains(t, body, "Hello World")
}
```

### How to run

```bash
cd Day18/test
go test -v -timeout 45m -run TestFullStackEndToEnd ./...
```

---

## CI/CD Pipeline

### File: `.github/workflows/terraform-test.yml`

```yaml
name: Terraform Tests

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

jobs:
  unit-tests:
    name: Unit Tests (terraform test)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "1.6.0"
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id:     ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region:            us-east-1
      - run: terraform init
        working-directory: Day18/modules/services/webserver-cluster
      - run: terraform test
        working-directory: Day18/modules/services/webserver-cluster

  integration-tests:
    name: Integration Tests (Terratest)
    runs-on: ubuntu-latest
    if: github.event_name == 'push'
    needs: unit-tests
    env:
      AWS_ACCESS_KEY_ID:     ${{ secrets.AWS_ACCESS_KEY_ID }}
      AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
      AWS_DEFAULT_REGION:    us-east-1
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v4
        with:
          go-version: "1.21"
      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "1.6.0"
          terraform_wrapper: false
      - run: go mod download
        working-directory: Day18/test
      - run: go test -v -timeout 30m -run "TestWebserverCluster" ./...
        working-directory: Day18/test
```

### Job dependency explanation

`integration-tests` has two gates:

1. `if: github.event_name == 'push'` — integration tests only run when a PR is merged to main, not on every PR. This keeps PR feedback fast (seconds, not minutes) and avoids deploying real AWS resources on every draft commit.

2. `needs: unit-tests` — integration tests only start if unit tests passed. No point spending 10 minutes and real money deploying infrastructure when the plan itself is broken.

The `terraform_wrapper: false` setting on the integration job is critical — Terratest parses Terraform's stdout directly, and the wrapper adds extra output that breaks the parser.

---

## Test Layer Comparison

| Test Type | Tool | Deploys Real Infra | Time | Cost | What It Catches |
|---|---|---|---|---|---|
| Unit | `terraform test` | No (plan only) | Seconds | Free | Naming regressions, wrong ports, bad tag values, misconfigured alarm thresholds, listener config errors |
| Integration | Terratest | Yes | 5–15 min | Low (~$0.10–$0.50/run) | Module deploys successfully, ALB serves traffic, outputs are correct, health checks pass |
| End-to-End | Terratest | Yes | 15–30 min | Medium (~$0.50–$2/run) | Full request path works, cross-module wiring is correct, user-data.sh runs, DNS resolves |

---

## Chapter 9 Learnings

### Integration test vs. end-to-end test

An **integration test** deploys a single module in isolation and verifies it works on its own. It answers: "Does this module deploy successfully and serve traffic?"

An **end-to-end test** deploys multiple modules in dependency order and verifies they work together as a system. It answers: "Does the complete application work when all the pieces are connected?" E2E tests catch interface mismatches — for example, a VPC module that renames its `subnet_ids` output to `private_subnet_ids` will break the webserver module that depends on it. Neither unit tests nor integration tests would catch this because each module is tested in isolation.

### Why unit tests on every PR but E2E tests less frequently?

Brikman's recommendation comes down to the feedback loop and cost tradeoff:

- Unit tests take seconds and are free. Running them on every PR gives developers instant feedback without slowing them down.
- E2E tests take 15–30 minutes and cost real money. Running them on every PR would make PRs painfully slow and rack up AWS bills. The right cadence is nightly or before releases — often enough to catch regressions, infrequently enough to keep costs and wait times manageable.

The pyramid model: many unit tests, fewer integration tests, fewest E2E tests.

---

## Common Issues and Fixes

### Go module errors

```
cannot find module providing package github.com/gruntwork-io/terratest/modules/http-helper
```

Fix: run `go mod download` or `go mod tidy` in the `test/` directory before running tests.

### Terratest timeout

```
TestWebserverClusterIntegration 2026-04-04T10:30:00Z TIMEOUT
```

Fix: increase the `-timeout` flag. ALBs can take 5–10 minutes to register targets. Use `-timeout 30m` for integration tests and `-timeout 45m` for E2E.

### AWS IAM permission failures in GitHub Actions

```
Error: UnauthorizedOperation: You are not authorized to perform this operation
```

Fix: the IAM user/role used in CI needs permissions for EC2, ELB, AutoScaling, IAM, CloudWatch, and SNS. Create a dedicated CI IAM role with a scoped policy rather than using AdministratorAccess. Store credentials as GitHub Actions secrets — never in the workflow YAML.

### `terraform_wrapper: true` breaks Terratest output parsing

```
panic: runtime error: invalid memory address or nil pointer dereference
```

Fix: set `terraform_wrapper: false` in the `hashicorp/setup-terraform` step when running Terratest. The wrapper adds extra output that Terratest cannot parse.

### `terraform test` fails on data sources without credentials

```
Error: No valid credential sources found
```

Fix: even though `command = plan` does not create resources, Terraform still needs credentials to resolve `data "aws_vpc"`, `data "aws_subnets"`, and `data "aws_ami"`. Provide read-only AWS credentials in the environment or CI secrets.
