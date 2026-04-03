terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  # Uncomment and fill in after running the bootstrap module
   backend "s3" {
     bucket         = "day16-b7ck3t"
     key            = "production/services/webserver-cluster/terraform.tfstate"
     region         = "us-east-1"
     dynamodb_table = "terraform-state-lock"
     encrypt        = true
   }
}

provider "aws" {
  region = "us-east-1"
}

variable "db_password" {
  description = "DB password injected via TF_VAR_db_password environment variable."
  type        = string
  sensitive   = true
}

module "webserver_cluster" {
  source = "../../../../modules/services/webserver-cluster"

  cluster_name  = "webservers-prod"
  environment   = "production"
  project_name  = "terraform-challenge"
  team_name     = "platform-team"
  app_version   = "v1"
  instance_type = "t3.small"
  min_size      = 2
  max_size      = 6

  cpu_alarm_threshold = 70  
  log_retention_days  = 90
  alarm_email         = "" # set to your email endpoint

  secret_source = "none"
  secret_ref    = ""

  custom_tags = {
    CostCenter  = "prod-001"
    Criticality = "high"
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
