# Environment Setup
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
