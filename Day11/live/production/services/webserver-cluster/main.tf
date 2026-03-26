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

  cluster_name = "webservers-production"
  environment  = "production"

  # is_production in the module forces autoscaling and monitoring on regardless,
  enable_autoscaling         = true
  enable_detailed_monitoring = true

  # Greenfield: use the default VPC.
  use_existing_vpc = false

  custom_tags = {
    Owner      = "platform-team"
    CostCenter = "prod-001"
  }
}

output "alb_dns_name" {
  value = module.webserver_cluster.alb_dns_name
}

output "instance_type_used" {
  value = module.webserver_cluster.instance_type_used
}

output "scale_out_policy_arn" {
  value = module.webserver_cluster.scale_out_policy_arn
}

output "scale_in_policy_arn" {
  value = module.webserver_cluster.scale_in_policy_arn
}

output "high_cpu_alert_arn" {
  value = module.webserver_cluster.high_cpu_alert_arn
}
