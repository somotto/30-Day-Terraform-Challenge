## What is Terraform?
Terraform is an open-source Infrastructure as Code (IaC) tool created by HashiCorp. It allows you to define cloud and on‑premises infrastructure using simple, declarative configuration files. Instead of manually clicking through cloud dashboards or writing imperative scripts, you describe the desired state of your infrastructure, and Terraform automatically provisions and manages it.

## What Problem Does It Solve?
Manual provisioning pain → Without IaC, engineers often set up servers, networks, and databases by hand, which is error‑prone and hard to reproduce.

Consistency across environments → Terraform ensures dev, staging, and production look the same.

Scalability → You can spin up or tear down entire environments with a single command.

Multi‑cloud support → It works across AWS, Azure, GCP, and many other providers, giving you flexibility and avoiding lock‑in.

Version control for infrastructure → Configurations live in code repositories, so changes are tracked, reviewed, and auditable.

## What Surprised or Challenged My Thinking
Declarative vs Imperative mindset → Instead of telling the system how to build step by step (imperative), you declare what you want, and Terraform figures out the steps. That shift in thinking is powerful but takes practice.

State management → Terraform keeps a “state file” to track what’s been deployed. Realizing that infrastructure has a “memory” was eye‑opening — it’s both a strength and a responsibility.

Infrastructure as code = collaboration → I hadn’t fully appreciated how IaC makes infrastructure changes reviewable just like software code. It means ops and dev teams can collaborate more effectively.

Idempotency → Running the same Terraform command multiple times doesn’t break things — it just ensures the infrastructure matches the desired state. That challenged my assumptions about automation scripts always being fragile.





## Environment Setup
1. Install Terraform
```bash
# Add HashiCorp repo
sudo apt-get update && sudo apt-get install -y gnupg software-properties-common

wget -O- https://apt.releases.hashicorp.com/gpg | \
gpg --dearmor | \
sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
sudo tee /etc/apt/sources.list.d/hashicorp.list

# Install Terraform
sudo apt-get update && sudo apt-get install terraform

# Verify installation
terraform version
```
2. Install AWS CLI
a. Download AWS CLI v2
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```
b. Verify installation
```bash
aws --version
```
c. Configure credentials
```bash
aws configure
Enter your AWS Access Key ID
Enter your AWS Secret Access Key
Default region: us-east-1 (or your preferred region)
Output format: json
```
d. Confirm identity
```bash
aws sts get-caller-identity
```
3. Verify Everything
```bash
terraform version
aws sts get-caller-identity
```
