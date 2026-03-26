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

  # Autoscaling and monitoring off in dev — count = 0 for those resources
  enable_autoscaling         = false
  enable_detailed_monitoring = false

  # Greenfield: use the default VPC
  use_existing_vpc = false

  custom_tags = {
    Owner = "dev-team"
  }
}

output "alb_dns_name" {
  value = module.webserver_cluster.alb_dns_name
}

output "instance_type_used" {
  value = module.webserver_cluster.instance_type_used
}

# null — autoscaling disabled in dev
output "scale_out_policy_arn" {
  value = module.webserver_cluster.scale_out_policy_arn
}

# null — detailed monitoring disabled in dev
output "high_cpu_alert_arn" {
  value = module.webserver_cluster.high_cpu_alert_arn
}
