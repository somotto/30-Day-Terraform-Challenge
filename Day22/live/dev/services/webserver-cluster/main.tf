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

  cluster_name  = "webservers-dev"
  environment   = "dev"
  project_name  = "terraform-challenge"
  team_name     = "dev-team"
  app_version   = "v5"
  instance_type = "t3.micro"
  min_size      = 1
  max_size      = 2

  cpu_alarm_threshold           = 80
  request_count_alarm_threshold = 500
  log_retention_days            = 7
  alarm_email                   = ""

  secret_source = "none"
  secret_ref    = ""

  # Sentinel: require-terraform-tag enforces ManagedBy = "terraform" on all resources.
  # Sentinel: allowed-instance-types enforces t2/t3 family only.
  # Sentinel: cost-check blocks applies with > $50/month delta.
  custom_tags = {
    CostCenter = "dev-001"
    Day        = "22"
  }
}

output "alb_dns_name" {
  value       = module.webserver_cluster.alb_dns_name
  description = "ALB DNS name — open in browser to verify the cluster."
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

output "request_count_alarm_arn" {
  value       = module.webserver_cluster.request_count_alarm_arn
  description = "ARN of the high request-count alarm."
}
