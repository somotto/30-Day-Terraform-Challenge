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

provider "aws" {
  region = "us-east-1"
}

module "webserver_cluster" {
  source = "../../../../modules/services/webserver-cluster"

  cluster_name  = "webservers-prod"
  environment   = "production"
  project_name  = "terraform-challenge"
  team_name     = "platform-team"
  app_version   = "v3"
  instance_type = "t3.small"
  min_size      = 1
  max_size      = 2

  cpu_alarm_threshold = 70
  log_retention_days  = 90
  alarm_email         = ""

  secret_source = "none"
  secret_ref    = ""

  custom_tags = {
    CostCenter  = "prod-001"
    Criticality = "high"
    Day         = "20"
  }
}

output "alb_dns_name" {
  value       = module.webserver_cluster.alb_dns_name
  description = "ALB DNS name."
}

output "asg_name" {
  value       = module.webserver_cluster.asg_name
  description = "Auto Scaling Group name."
}

output "sns_topic_arn" {
  value       = module.webserver_cluster.sns_topic_arn
  description = "SNS topic ARN for CloudWatch alarm notifications."
}

output "log_group_name" {
  value       = module.webserver_cluster.log_group_name
  description = "CloudWatch log group name."
}
