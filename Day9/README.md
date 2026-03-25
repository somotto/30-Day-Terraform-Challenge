# Day 9 — Advanced Terraform Modules: Versioning, Gotchas, and Multi-Environment Reuse

## Module Gotchas

### Gotcha 1 — File Paths Inside Modules

When a module references a file using a bare relative path, Terraform resolves it relative to the directory where `terraform` is run — not relative to the module itself. This means the same module breaks depending on where you call it from.

**Broken:**
```hcl
# This resolves relative to the caller's working directory, not the module
user_data = base64encode(templatefile("./user-data.sh", {
  server_port = var.server_port
}))
```

**Corrected:**
```hcl
# path.module always resolves to the module's own directory
user_data = base64encode(templatefile("${path.module}/user-data.sh", {
  server_port  = var.server_port
  cluster_name = var.cluster_name
  environment  = var.environment
}))
```

---

### Gotcha 2 — Inline Blocks vs Separate Resources

Some AWS resources support both an inline block and a standalone resource for the same configuration — `aws_security_group` is the classic example. If you define `ingress` blocks inline and also create `aws_security_group_rule` resources pointing at the same group, Terraform will fight itself on every plan, showing a perpetual diff.

**Broken:**
```hcl
resource "aws_security_group" "alb_sg" {
  name   = "${var.cluster_name}-alb-sg"
  vpc_id = data.aws_vpc.default.id

  # Inline block — conflicts with any aws_security_group_rule for this group
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# This will cause a permanent diff — Terraform can't reconcile both
resource "aws_security_group_rule" "extra_rule" {
  type              = "ingress"
  security_group_id = aws_security_group.alb_sg.id
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}
```

**Corrected:**
```hcl
# Security group shell — no inline rules
resource "aws_security_group" "alb_sg" {
  name   = "${var.cluster_name}-alb-sg"
  vpc_id = data.aws_vpc.default.id
}

# All rules as standalone resources — callers can add more without touching the module
resource "aws_security_group_rule" "alb_inbound_http" {
  type              = "ingress"
  security_group_id = aws_security_group.alb_sg.id
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}
```

---

### Gotcha 3 — Module Output Dependencies

When you use `depends_on = [module.some_module]` in a root configuration, Terraform treats the entire module as a single dependency. It cannot determine which specific resource inside the module you actually need, so it marks every resource in the module as a dependency. This causes unnecessary resource recreation and slows down plans significantly.

**Broken:**
```hcl
resource "aws_route53_record" "app" {
  # ...
  # Forces ALL resources in the module to be evaluated as dependencies
  depends_on = [module.webserver_cluster]
}
```

**Corrected:**
```hcl
resource "aws_route53_record" "app" {
  name    = "app.example.com"
  type    = "CNAME"
  records = [module.webserver_cluster.alb_dns_name]  # reference the specific output
  # No depends_on needed — Terraform infers the dependency from the reference
}
```

---

## Versioned Module Repository

Repository: `https://github.com/somotto/30-Day-Terraform-Challenge`

```bash
$ git tag -l
v0.0.1
v0.0.2
```

**What changed between v0.0.1 and v0.0.2:**

- Added `custom_tags` variable (`map(string)`) — callers can attach arbitrary tags to all resources without modifying the module
- Added `environment` variable — displayed on the web page served by each instance
- Extracted `user-data.sh` as a separate file referenced via `path.module` (Gotcha 1 fix)
- Refactored all security group rules from inline blocks to standalone `aws_security_group_rule` resources (Gotcha 2 fix)
- Added `alb_sg_id` output for callers that need to attach extra ALB rules

---

## Multi-Environment Calling Configurations

### Dev — uses v0.0.2

```hcl
# Day9/live/dev/services/webserver-cluster/main.tf
module "webserver_cluster" {
  source = "github.com/somotto/30-Day-Terraform-Challenge//Day9/modules/services/webserver-cluster?ref=v0.0.2"

  cluster_name  = "webservers-dev"
  environment   = "dev"
  instance_type = "t3.micro"
  min_size      = 2
  max_size      = 4

  custom_tags = {
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}
```

### Production — pinned to v0.0.1

```hcl
# Day9/live/production/services/webserver-cluster/main.tf
module "webserver_cluster" {
  source = "github.com/somotto/30-Day-Terraform-Challenge//Day9/modules/services/webserver-cluster?ref=v0.0.1"

  cluster_name  = "webservers-production"
  environment   = "production"
  instance_type = "t3.micro"
  min_size      = 4
  max_size      = 10
}
```

**Why production stays on v0.0.1:** Production infrastructure carries real traffic. Pinning it to a validated version means a module change that breaks something in dev never automatically reaches production. The promotion path is explicit: dev validates v0.0.2, the team reviews the diff, then production is updated in a deliberate commit. This is the same principle as pinning a Docker image tag or a library version in a lockfile.

---

## terraform init Output (example)

```
Initializing modules...
Downloading git::https://github.com/somotto/30-Day-Terraform-Challenge.git//Day9/modules/services/webserver-cluster?ref=v0.0.2 for webserver_cluster...
- webserver_cluster in .terraform/modules/webserver_cluster/Day9/modules/services/webserver-cluster

Initializing the backend...

Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 6.0"...
- Installing hashicorp/aws v6.37.0...

Terraform has been successfully initialized!
```

---

## Version Pinning Strategy

Referencing a module without a version pin — using a branch name like `?ref=main` or no ref at all — means every `terraform init` pulls whatever the latest commit is. In a team environment this is dangerous: two engineers running `terraform apply` an hour apart may be applying different infrastructure if someone pushed a module change between their runs. The plan looks identical locally but the actual resources differ. This is how silent drift gets introduced into production.

A version pin (`?ref=v0.0.1`) is immutable. The module source cannot change under you. It also makes the change history auditable — you can look at a root config's git log and see exactly when production was promoted from v0.0.1 to v0.0.2 and who approved it.

---

## Chapter 4 Gotchas — Reflections

The most dangerous gotcha in production is **Gotcha 2 (inline blocks vs separate resources)**. It produces a perpetual diff — Terraform always shows a change on plan but never actually converges. In a busy team this gets dismissed as "Terraform noise" and people start ignoring plan output. That's exactly when a real destructive change gets missed. The fix is simple but you have to know the rule exists.

Gotcha 1 (file paths) is the most common first-time mistake when extracting user-data scripts into modules. It works fine when you run from the module directory during development, then silently breaks when called from a live environment subdirectory.

---

## Challenges and Fixes

- **GitHub source URL double-slash**: The `//` separator between the repo root and the module subdirectory is required — `github.com/org/repo//modules/services/webserver-cluster?ref=v0.0.1`. A single slash treats the whole path as the repo name and fails with a confusing error.
- **terraform init caching**: After changing a `?ref=` tag, run `terraform init -upgrade` to force Terraform to re-download the module. Without `-upgrade` it may use the cached version from `.terraform/modules/`.
- **Tagging before pushing**: `git push origin main --tags` is required — `git push origin main` does not push tags. If you forget, `terraform init` will fail with "ref not found".
- **Day 8 user_data bug**: The original Day 8 `main.tf` had a broken heredoc in the `user_data` field (truncated HTML and a malformed `cat` command). This was fixed in Day 9 by extracting the script to `user-data.sh` and using `templatefile()`.

---

## Blog Post

URL: *(to be published)*

Summary: Covers the three module gotchas from Chapter 4 with broken/fixed code examples, walks through the full versioning workflow from `git tag` to `?ref=` pinning in source URLs, and explains the dev/production version split pattern. The versioning section shows all three source URL formats: local path, Git with ref, and Terraform Registry.
