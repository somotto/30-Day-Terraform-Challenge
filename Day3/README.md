# Day 3: Deploying My First Server with Terraform

## Understanding the Blocks
**- Provider Block** - This block tells the terraform which cloud platform to use. In this case, I'm using AWS and specifying the region us-east-1.

**- Resource Block** - This block defines what infrastructure to create. I used;
 - aws_instance to provision an EC2 server.
 - aws_security_group to allow HTTP traffic on port 80.

## Terraform Workflow
1. *terraform init* - Initializes the working directory and downloads the AWS provider plugin.
2. *terraform plan* - Shows what terraform will do before making changes.
3. *terraform apply* - Applies the configuration and provisions the infrastructure.
4. *terraform destroy* - Destroys the infrastructure to avoid unnecessary cloud costs.

## Error I faced and Fixes
- Error: AMI not found  
- Fix: I was using an outdated AMI ID. I searched for the latest Amazon Linux 2 AMI in the AWS Console and replaced it.
