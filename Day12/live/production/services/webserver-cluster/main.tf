provider "aws" {
  region = "us-east-1"
}

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

module "webserver_cluster" {
  source = "../../../../modules/services/webserver-cluster"

  cluster_name = "webservers-prod"
  environment  = "production"

  # Rolling update version (used by the standard ASG)
  app_version = "v1"

  min_size = 2
  max_size = 6

  enable_blue_green = true

  active_environment = "green"

  blue_app_version  = "v1"
  green_app_version = "v2"

  custom_tags = {
    Owner      = "platform-team"
    CostCenter = "prod-001"
  }
}

output "alb_dns_name" {
  value       = module.webserver_cluster.alb_dns_name
  description = "ALB DNS — traffic goes to the active slot"
}

output "asg_name" {
  value       = module.webserver_cluster.asg_name
  description = "ASG name (includes random_id suffix)"
}

output "active_target_group_arn" {
  value       = module.webserver_cluster.active_target_group_arn
  description = "Currently active target group ARN"
}

output "blue_asg_name" {
  value       = module.webserver_cluster.blue_asg_name
  description = "Blue ASG — always running v1"
}

output "green_asg_name" {
  value       = module.webserver_cluster.green_asg_name
  description = "Green ASG — always running v2"
}
