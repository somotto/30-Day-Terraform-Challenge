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

  cluster_name = "webservers-dev"
  environment  = "dev"

  app_version = "v2"

  min_size = 2
  max_size = 4

  custom_tags = {
    Owner = "dev-team"
  }
}

output "alb_dns_name" {
  value       = module.webserver_cluster.alb_dns_name
  description = "Hit this URL to verify the running version"
}

output "asg_name" {
  value       = module.webserver_cluster.asg_name
  description = "ASG name changes with each deployment (random_id suffix)"
}
