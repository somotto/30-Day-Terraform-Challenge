# Day 23: Exam Preparation — Brushing Up on Key Terraform Concepts

Day 23 shifts focus entirely to certification readiness. The hands-on builds are
complete. Today is an honest self-audit against every official exam domain,
a structured study plan for the remaining days, deep review of CLI commands,
non-cloud providers, and five original practice questions.

---

## 1. Domain Audit

### Understand Infrastructure as Code concepts
Status: Green
I can clearly explain declarative vs imperative models and have applied Terraform
in multiple scenarios across all 22 previous days.

### Understand Terraform purpose
Status: Green
I understand how Terraform manages infrastructure lifecycle and enables
reproducibility across environments and teams.

### Understand Terraform basics
Status: Green
Confident with providers, resources, variables, outputs, data sources, and
expressions. Used all of these extensively throughout the challenge.

### Use the Terraform CLI
Status: Yellow
I use common commands daily but need deeper familiarity with state-related
commands, their flags, and edge-case behaviour tested on the exam.

### Interact with Terraform modules
Status: Green
I have built and consumed modules, understand input/output contracts, versioning,
and the difference between local and registry modules.

### Navigate the core Terraform workflow
Status: Green
I consistently follow init → validate → plan → apply → destroy in the correct
order and understand what each step does to state and real infrastructure.

### Implement and maintain state
Status: Yellow
I understand state conceptually and have used remote backends, but need more
hands-on practice with state manipulation commands (mv, rm, import).

### Read, generate, and modify configuration
Status: Green
Comfortable writing and editing HCL, using locals, dynamic blocks, for_each,
count, and conditional expressions.

### Understand Terraform Cloud capabilities
Status: Yellow
I have used Terraform Cloud but need deeper knowledge of workspace variables,
remote run modes, Sentinel enforcement points, and the private registry.

---

## 2. Study Plan (Days 24 to Exam)

| Topic | Confidence | Study Method | Time |
|---|---|---|---|
| Terraform CLI deep dive | Yellow | Write definitions for each command, run them in a test project, note key flags | 60 min |
| State management commands | Yellow | Practice `state list`, `show`, `mv`, `rm` on real resources, note what changes in the state file | 60 min |
| Terraform Cloud features | Yellow | Review workspace variables, remote run modes, permissions, and cost estimation limits | 45 min |
| Sentinel policies | Yellow | Write and review two policies, understand hard-mandatory vs soft-mandatory vs advisory | 45 min |
| Provider aliases | Yellow | Write a multi-region config using aliases, deploy a resource to each region | 30 min |
| Non-cloud providers | Green | Write examples using random, local, and tls providers; understand use cases | 20 min |
| IaC concepts | Green | Write three practice questions; review declarative vs imperative definitions | 15 min |
| Practice questions | Mixed | Solve 10 questions daily, review every incorrect answer, add gaps to plan | 60 min/day |

---

## 3. CLI Commands Self-Test

**terraform init**
Downloads providers and modules, configures the backend, and prepares the
working directory. Used every time you start a new project or change provider
or backend configuration.

**terraform validate**
Checks configuration files for syntax errors and internal consistency without
accessing any remote services. Used before planning to catch typos and
structural mistakes early.

**terraform fmt**
Rewrites configuration files to the canonical HCL style — consistent indentation,
aligned equals signs, sorted blocks. Used to keep code readable and pass
fmt-check gates in CI.

**terraform plan**
Compares current state against desired configuration and shows exactly what
would be created, changed, or destroyed. Used before every apply so you know
what is about to happen.

**terraform apply**
Executes the changes shown in the plan, creating or updating real infrastructure
and writing the new state. Used to converge infrastructure toward the desired
configuration.

**terraform destroy**
Removes all resources managed by the current configuration and clears them from
state. Used when tearing down an environment completely.

**terraform output**
Reads and displays output values stored in the state file. Used to retrieve
useful values — ALB DNS names, ARNs, IPs — after an apply without re-reading
the whole state.

**terraform state list**
Prints every resource address tracked in the current state file. Used to
inspect what Terraform is managing before running state manipulation commands.

**terraform state show**
Displays all attributes of a single resource in state. Used for debugging when
you need to see exactly what Terraform recorded about a resource after apply.

**terraform state mv**
Moves a resource from one address to another within the same state, or between
two state files. Used during refactoring — for example, when wrapping a resource
inside a module without destroying and recreating it.

**terraform state rm**
Removes a resource from state without touching the real infrastructure. Used
when you want Terraform to stop managing a resource — the resource continues
to exist in the cloud, Terraform just forgets about it.

**terraform import**
Reads an existing real-world resource and writes its attributes into state so
Terraform can manage it going forward. Used when adopting infrastructure that
was created outside of Terraform.

**terraform taint** *(deprecated — use `-replace` flag on plan/apply)*
Marks a resource for forced recreation on the next apply. Used when a resource
is in a broken state and needs to be replaced without changing its configuration.

**terraform workspace**
Creates, lists, selects, and deletes named workspaces within a single backend.
Used to maintain separate state files for dev and production from the same
configuration directory.

**terraform providers**
Lists all providers required by the current configuration and their version
constraints. Used for troubleshooting provider version conflicts or auditing
what external dependencies a configuration has.

**terraform login**
Authenticates the local CLI with Terraform Cloud by obtaining and storing an
API token. Used when setting up a new machine to work with remote runs or the
private registry.

**terraform graph**
Outputs the dependency graph of resources in DOT format, which can be rendered
with Graphviz. Used to visualise resource relationships and understand apply
ordering.

---

## 4. Practice Questions

### Question 1
A team member manually deleted an S3 bucket that Terraform manages. What
happens when you run `terraform plan`?

- A) Terraform errors out because the resource is missing
- B) Terraform detects drift and shows the bucket as a resource to be created
- C) Terraform removes the bucket from state automatically
- D) Nothing — Terraform only reads state, not real infrastructure

Correct answer: B

Explanation: On every plan, Terraform refreshes state by querying real
infrastructure. When it finds the bucket is gone, it marks it as needing
creation. A is wrong — Terraform handles missing resources gracefully. C is
wrong — Terraform does not auto-remove resources from state on plan. D is wrong
— Terraform always reads real infrastructure during refresh.

---

### Question 2
What does `terraform state rm aws_s3_bucket.example` do to the real S3 bucket?

- A) Deletes the bucket and all its contents
- B) Empties the bucket but leaves it in place
- C) Nothing — it only removes the resource from Terraform state
- D) Marks the bucket for deletion on the next apply

Correct answer: C

Explanation: `state rm` only modifies the state file. The real bucket is
completely untouched. A and B are wrong — no AWS API calls are made. D is wrong
— there is no "marked for deletion" concept in state; that is what `taint` does
for recreation.

---

### Question 3
You have two AWS provider blocks — one for us-east-1 and one for us-west-2
using an alias. How do you tell a resource to use the aliased provider?

- A) Set `region = "us-west-2"` inside the resource block
- B) Add `provider = aws.west` inside the resource block
- C) Prefix the resource type with the alias: `aws.west_s3_bucket`
- D) Terraform automatically picks the nearest region

Correct answer: B

Explanation: The `provider` meta-argument inside a resource block accepts a
`<provider>.<alias>` reference. A is wrong — the `region` argument on a resource
is not valid HCL. C is wrong — resource type names are fixed. D is wrong —
Terraform has no concept of geographic proximity.

---

### Question 4
Which Terraform Cloud feature runs automatically after a plan and can block an
apply before any human reviews it?

- A) Cost estimation
- B) Sentinel policy checks
- C) Remote state locking
- D) Workspace variables

Correct answer: B

Explanation: Sentinel policies run in the workflow between plan and apply. A
hard-mandatory policy failure blocks the apply entirely with no override. A is
wrong — cost estimation is informational and does not block by default. C is
wrong — state locking prevents concurrent runs but does not gate applies. D is
wrong — workspace variables are inputs, not enforcement mechanisms.

---

### Question 5
You refactor a resource from the root module into a child module. The resource
already exists in state at `aws_instance.web`. After the refactor it will be at
`module.web.aws_instance.server`. What must you do to avoid destroying and
recreating the instance?

- A) Run `terraform import module.web.aws_instance.server <id>`
- B) Run `terraform state mv aws_instance.web module.web.aws_instance.server`
- C) Add a `lifecycle { ignore_changes = all }` block
- D) Nothing — Terraform detects the move automatically

Correct answer: B

Explanation: `state mv` renames the address in state so Terraform sees the
existing resource at the new address and does not plan a replacement. A is wrong
— import is for resources that exist outside of Terraform entirely, not for
renaming addresses. C is wrong — `ignore_changes` suppresses drift detection,
it does not rename addresses. D is wrong — Terraform does not auto-detect
address renames (the `moved` block in HCL does, but that is a separate feature).

---

## 5. Official Practice Question Results

Worked through all official HashiCorp sample questions on first attempt.

Topics that required review:
- The exact behaviour of `terraform refresh` as a standalone command vs the
  implicit refresh inside `terraform plan`
- The distinction between `terraform.workspace` (the string value) and the
  `terraform workspace` CLI subcommand
- Which Sentinel enforcement level allows a workspace owner to override a
  policy failure (soft-mandatory)

---

## Additional Resources

- [Terraform Associate Study Guide](https://developer.hashicorp.com/terraform/tutorials/certification-003/associate-study-003)
- [Official Sample Questions](https://developer.hashicorp.com/terraform/tutorials/certification-003/associate-questions)
- [Terraform CLI Commands Reference](https://developer.hashicorp.com/terraform/cli/commands)
- [Terraform Random Provider](https://registry.terraform.io/providers/hashicorp/random/latest/docs)
- [Terraform Associate Exam Review](https://developer.hashicorp.com/terraform/tutorials/certification-003/associate-review-003)
