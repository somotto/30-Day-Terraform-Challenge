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
  }
}

module "webserver_cluster" {
  source = "../../../../modules/services/webserver-cluster"

  cluster_name = "webservers-dev"
  environment  = "dev"
  min_size     = 2
  max_size     = 4

  # instance_type = null → module conditional selects t3.micro for dev
  instance_type = null

  # count conditional: autoscaling policies + CloudWatch alarms are created
  enable_autoscaling = true

  # for_each: add an HTTPS rule to the ALB security group
  extra_alb_ingress_rules = {
    https = {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  custom_tags = {
    Environment = "dev"
    ManagedBy   = "terraform"
    Day         = "10"
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

output "autoscaling_policy_arns" {
  value       = module.webserver_cluster.autoscaling_policy_arns
  description = "Scale-out and scale-in policy ARNs (populated because enable_autoscaling = true)"
}

output "instance_type_used" {
  value       = module.webserver_cluster.instance_type_used
  description = "Should be t3.micro — selected by the module's conditional"
}
