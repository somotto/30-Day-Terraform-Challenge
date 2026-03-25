# Dev environment — uses v0.0.2 to test the latest module changes
# before they are promoted to production.

provider "aws" {
  region = "us-east-1"
}

terraform {
  required_version = ">= 1.0"
}

module "webserver_cluster" {
  # Pin to v0.0.2 — dev intentionally tracks the latest version for validation
  source = "github.com/somotto/30-Day-Terraform-Challenge//Day9/modules/services/webserver-cluster?ref=v0.0.2"

  cluster_name  = "webservers-dev"
  environment   = "dev"
  instance_type = "t3.micro"
  min_size      = 2
  max_size      = 4

  custom_tags = {
    Environment = "dev"
    ManagedBy   = "terraform"
    Day         = "9"
  }
}

output "alb_dns_name" {
  value       = module.webserver_cluster.alb_dns_name
  description = "Hit this URL to reach the dev cluster"
}

output "asg_name" {
  value       = module.webserver_cluster.asg_name
  description = "Dev ASG name"
}
