# Day 24: Final Exam Review and Certification Focus

Day 24 is pure exam preparation — no new deployments, no new concepts. This is
the day to close the gap between understanding and precision under time pressure.
Full simulation, deep domain drills, flash card review, and a locked-in exam-day
strategy.

---

## 1. Exam Simulation Results

Timer: 60 minutes. 57 questions. No lookups. No pauses.

Score: 44 / 57 — 77%

Passing threshold is 70% (40/57). Passed the simulation.

Questions answered incorrectly — topics:
- The exact output of `terraform output -json` when no outputs are defined (returns `{}`, not an error)
- Whether `terraform refresh` is deprecated (it is — use `terraform apply -refresh-only`)
- Sentinel enforcement levels — specifically which level allows a workspace owner to override
- The behaviour of `count` vs `for_each` when an item is removed from the middle of a list
- `terraform workspace` behaviour in Terraform Cloud vs OSS backends
- What `sensitive = true` does and does NOT do (masks terminal output, does NOT encrypt state)
- The `moved` block — when to use it vs `terraform state mv`

Weakest domain: Terraform CLI (missed 3 questions) and Terraform Cloud (missed 2 questions).

---

## 2. Flash Card Answers

Answered without notes first, then verified.

**Q1: What file does `terraform init` create to record provider versions?**
`.terraform.lock.hcl` — records the exact provider versions and their checksums
so every team member and CI run uses the same provider binary.

**Q2: What is the difference between `terraform.workspace` and a Terraform Cloud workspace?**
`terraform.workspace` is a string expression in HCL that returns the name of the
currently selected workspace — it is a value you can use inside configuration.
A Terraform Cloud workspace is a full remote execution environment with its own
state, variables, run history, and permissions. They share the word "workspace"
but operate at different levels.

**Q3: If you run `terraform state rm aws_instance.web`, what happens to the EC2 instance in AWS?**
Nothing. The instance continues running in AWS exactly as before. `state rm` only
removes the resource record from the local state file — no AWS API calls are made.
Terraform simply stops tracking that resource.

**Q4: What does `depends_on` do and when should you use it?**
`depends_on` creates an explicit dependency between resources or modules that
Terraform cannot infer from configuration references alone. Use it when a
resource depends on the side effects of another resource — for example, an IAM
policy attachment that must exist before an EC2 instance can assume a role, where
the instance block does not directly reference the attachment.

**Q5: What is the purpose of the `.terraform.lock.hcl` file?**
It pins the exact provider versions and checksums selected during `terraform init`.
This ensures that subsequent inits — by other team members or in CI — use the
same provider binaries rather than resolving version constraints fresh each time.
It should be committed to version control.

**Q6: How does `for_each` differ from `count` when items are removed from the middle of a collection?**
With `count`, resources are addressed by index (`aws_instance.web[0]`,
`aws_instance.web[1]`). Removing an item from the middle shifts all subsequent
indices, causing Terraform to plan replacements for every resource after the
removed item. With `for_each`, resources are addressed by key
(`aws_instance.web["prod"]`). Removing one key only affects that specific
resource — all others are untouched.

**Q7: What does `terraform apply -refresh-only` do?**
It updates the state file to match the real current state of infrastructure
without making any changes to real resources. It is the safe, explicit
replacement for the deprecated `terraform refresh` command. Useful for
reconciling drift before planning changes.

**Q8: What is the maximum number of items you can specify in a single `terraform import` command?**
One. Each `terraform import` call imports exactly one resource into state. To
import multiple resources you must run the command once per resource, or use
the `import` block in HCL (Terraform 1.5+) which allows multiple imports in a
single apply.

**Q9: What happens when you run `terraform plan` against a workspace that has never been applied?**
Terraform shows a plan to create all resources defined in the configuration.
Since there is no existing state, every resource is treated as new. No
infrastructure exists yet so there is nothing to refresh or diff against.

**Q10: What does `prevent_destroy` do and what does it NOT prevent?**
`prevent_destroy = true` inside a `lifecycle` block causes Terraform to return
an error if a plan would destroy that resource — protecting against accidental
deletion. It does NOT prevent `terraform state rm` (which removes the resource
from state without destroying it), and it does NOT prevent someone from removing
the `prevent_destroy` argument itself and then running destroy.

Corrections after verification:
- Q8: The HCL `import` block (1.5+) was a gap — I initially said there was no
  alternative to running the CLI command multiple times.

---

## 3. High-Weight Domain Drill

### Terraform Basics (24%)

Three things I now know precisely that I was fuzzy on before:

1. `terraform.tfstate.backup` is written before every apply — it holds the state
   from the previous successful apply, not the current one. If an apply fails
   mid-way, the backup still reflects the last clean state.

2. `templatefile(path, vars)` reads a file and renders it as a template using
   the provided variable map. It is the correct replacement for the deprecated
   `template_file` data source. The file path must be known at plan time.

3. `toset()` converts a list to a set, removing duplicates and losing order.
   This is the correct conversion to use before passing a list to `for_each`,
   because `for_each` requires either a map or a set of strings — not a list.

### Terraform CLI (26%)

Three things I now know precisely:

1. `terraform init -upgrade` forces Terraform to re-evaluate provider version
   constraints and download newer versions even when the lock file already pins
   a version. Without `-upgrade`, init respects the lock file and will not
   upgrade a pinned provider.

2. `terraform plan -target=aws_instance.web` limits the plan to that resource
   and its dependencies. It does NOT guarantee a safe partial apply in
   production — HashiCorp explicitly warns against using `-target` routinely
   because it can leave state inconsistent.

3. `terraform import` writes to state only — it does NOT generate the `.tf`
   resource block. After importing, you must write the matching resource
   configuration manually (or use `terraform show` to read the imported
   attributes and write the block from them).

### IaC Concepts (16%)

Three things I now know precisely:

1. Idempotency means running the same Terraform configuration multiple times
   produces the same result. If infrastructure already matches the configuration,
   a plan shows zero changes and an apply makes zero changes.

2. Configuration drift is the gap between what the state file (and configuration)
   declares and what actually exists in the real infrastructure. It occurs when
   changes are made outside of Terraform — manually in the console, via scripts,
   or by other tools.

3. Immutable infrastructure means replacing resources rather than modifying them
   in place. Terraform supports this through `create_before_destroy` in the
   `lifecycle` block — the new resource is created first, then the old one is
   destroyed, minimising downtime.

### Terraform's Purpose (20%)

Three things I now know precisely:

1. Terraform is provider-agnostic — it works with any service that exposes an
   API and has a provider plugin. This includes AWS, Azure, GCP, GitHub,
   Datadog, PagerDuty, and hundreds of others. The provider translates HCL
   resource blocks into API calls.

2. State is Terraform's source of truth for mapping configuration to real
   infrastructure. Without state, Terraform cannot know which real resource
   corresponds to which resource block, so it cannot plan updates or deletions.

3. Terraform Cloud is a SaaS product — HashiCorp hosts and manages it.
   Terraform Enterprise is the self-hosted version for organisations that
   require private networking, custom SSO, or audit log control. Both support
   remote runs, the private module registry, and Sentinel policies.

---

## 4. Common Exam Traps

From the official list plus three additional traps identified during simulation:

**Trap 1: `terraform workspace` in Terraform Cloud behaves differently than in OSS**
In open-source Terraform, workspaces share the same backend and configuration
directory — they are lightweight state isolation. In Terraform Cloud, each
workspace is a fully independent environment with its own variables, run
history, and permissions. Questions that conflate the two are a common trap.
Read carefully whether the question is about OSS or Cloud.

**Trap 2: The `moved` block vs `terraform state mv`**
Both rename a resource address in state. The difference is that the `moved`
block lives in `.tf` configuration and is applied automatically during the next
plan/apply — it also communicates the rename to module consumers. `terraform
state mv` is a one-time CLI operation with no configuration record. Exam
questions may describe a refactoring scenario and ask which approach is correct
for a reusable module — the answer is the `moved` block.

**Trap 3: `sensitive = true` does not encrypt state**
Marking an output or variable as `sensitive = true` only suppresses the value
in terminal output and plan display. The value is still stored in plain text in
the state file. If the state file is stored in S3, you need bucket encryption
and access controls separately. Exam questions sometimes imply that `sensitive`
provides security for the stored value — it does not.

---

## 5. Exam-Day Strategy

- Read every question fully before looking at the answers. The last sentence
  often contains the constraint that eliminates three of the four options.

- Spend a maximum of 90 seconds on any single question. If you are still
  uncertain, flag it and move on. Return to flagged questions after completing
  the rest — you will often find that a later question jogs your memory.

- On elimination: identify the one or two answers that are clearly wrong first.
  This usually gets you to two plausible options. Then apply the precise
  distinction you drilled — `state rm` vs `destroy`, `count` vs `for_each`,
  `sensitive` vs encrypted.

- On multi-select questions ("select TWO"): treat each option independently —
  is this statement true or false on its own? Select exactly the number asked.
  Selecting one or three is marked entirely wrong.

- Watch for the word "only" in answer choices. Terraform commands rarely do
  exactly one thing with no side effects — answers containing "only" are
  sometimes correct (`state rm` only modifies state) and sometimes traps.

- Do not second-guess your first answer unless you find a specific reason to
  change it. Changing answers based on anxiety rather than new reasoning lowers
  scores on average.

- Arrive with `.terraform.lock.hcl`, `terraform state` subcommands, and
  `for_each` vs `count` behaviour fresh in memory — these appear repeatedly
  across multiple domains.

---

## 6. Remaining Red Topics

No hard red topics remain after today's session. Two areas are still amber and
will get one more focused pass before the exam:

**Terraform Cloud run modes (remote, local, agent)**
I understand the concepts but want to be precise on which operations run
remotely vs locally in each mode, and what the UI shows during a remote run.
Plan: read the official run modes documentation once more and write a one-page
summary.

**Sentinel enforcement levels**
I know hard-mandatory, soft-mandatory, and advisory. I want to be precise on
exactly who can override a soft-mandatory failure (workspace owners and
organisation owners) and what the UI flow looks like.
Plan: re-read the Sentinel enforcement documentation and add a flash card for
each enforcement level.

---

## Resources

- [Terraform Associate Study Guide](https://developer.hashicorp.com/terraform/tutorials/certification-003/associate-study-003)
- [Official Sample Questions](https://developer.hashicorp.com/terraform/tutorials/certification-003/associate-questions)
- [Terraform Associate Review Tutorial](https://developer.hashicorp.com/terraform/tutorials/certification-003/associate-review-003)
- [Terraform CLI Commands Reference](https://developer.hashicorp.com/terraform/cli/commands)
- [Sentinel Policy Enforcement](https://developer.hashicorp.com/terraform/cloud-docs/policy-enforcement)
- [Terraform State Documentation](https://developer.hashicorp.com/terraform/language/state)
