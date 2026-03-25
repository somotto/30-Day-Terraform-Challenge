# Production environment — intentionally pinned to v0.0.1, the last
# validated stable release. Only bumped after dev has proven the new version.

provider "aws" {
  region = "us-east-1"
}

terraform {
  required_version = ">= 1.0"
}

module "webserver_cluster" {
  # Pin to v0.0.1 — production stays on the proven stable version
  source = "github.com/somotto/30-Day-Terraform-Challenge//Day9/modules/services/webserver-cluster?ref=v0.0.1"

  cluster_name  = "webservers-production"
  environment   = "production"
  instance_type = "t3.micro"
  min_size      = 4
  max_size      = 10

  # custom_tags not available in v0.0.1 — added in v0.0.2
}

output "alb_dns_name" {
  value       = module.webserver_cluster.alb_dns_name
  description = "Hit this URL to reach the production cluster"
}

output "asg_name" {
  value       = module.webserver_cluster.asg_name
  description = "Production ASG name"
}
