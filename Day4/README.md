# Day 4: Mastering Basic Infrastructure with Terraform
- Today, I learnt about DRY(Don't Repeat Yourself) principle in terraform - No repetition. By using imput variables, I eliminated harcoding. This makes the configuration reusable across environments. In a large team, hardcoding would lead to inconsistencies, errors, and wasted time. Variables keep infrastructure flexible and maintainable.
- Its implementations are shown in the tasks below:

## 1. Deploy a Configurable Web Server
This task was to eliminate hardcoded values. Instead of embedding instance type, region, or port directly in the [ConfigurableWebServer/main.tf](ConfigurableWebServer/main.tf), I moved them into a [ConfigurableWebServer/variables.tf](ConfigurableWebServer/variables.tf) file for flexible parameters.

## 2. Deploying a Clustered Web Server [ClusteredeWebServer/main.tf](ClusteredWebServer/main.tf)
In this task, I extended the setup to a cluster using an Auto Scaling Group and an Application Load Balancer. This makes the app highly available and capable of handling real traffic.

### Key Resources
- Launch Template - Defines the instance spec and user data
- Auto Scaling Group(ASG) - Ensures 2 - 5 instances are running
- Target Group + Listener - Connect the ALB to the ASG.

## Key Blocks
- Provider Block - Configures AWS region dynamically using var.region
- Data Sources - Fetch the default VPC , subnets, and the latest Amazon Linux AMI. This avoids hardcoding IDs.
- Security group - OPens the chosen var.server_port for inbound http traffic.
- Launch template - Defines the ec2 instance spec, user data and attaches the security grooup.
- Auto scaling group (ASG) - Ensures multiple ec2 instances are running, with min/max/desired capacity driven by variables.

## Workflow
```bash
terraform init
terraform plan
terraform apply
```


After applying, I checked the AWS Console -> EC2 -> ASG. I could see multiple EC2 instances launched under the ASG. Each instance had the same configuration.

Since ALBs are not part of the Free Tier, I validated the cluster by checking the individual public IPs of the EC2 instance. Each one served the same user data script, confirming consistency.

Finally, I destroyed the resources to avoid costs:
```bash
terraform destroy
```

## Challenges and Fixes

- Subnet IDs → Initially forgot to fetch subnets dynamically. Fixed by using data "aws_subnets".

- User Data Encoding → Terraform requires user data to be base64 encoded in launch templates. Fixed by wrapping the script in base64encode().

- Validation Without ALB → Since I couldn’t use an ALB, I validated by checking multiple EC2 public IPs individually.