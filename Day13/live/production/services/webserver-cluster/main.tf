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

# Secrets Manager — value comes from TF_VAR_db_password, never written to
# any .tf file. The instance fetches it at boot via its IAM role.

variable "db_password" {
  description = "DB password injected via TF_VAR_db_password env var"
  type        = string
  sensitive   = true
}

module "db_password_secret" {
  source = "../../../../modules/secrets-manager"

  secret_name  = "prod/webservers-prod/db_password"
  description  = "Prod DB password — fetched by instances at boot"
  secret_value = jsonencode({ password = var.db_password })

  recovery_window_in_days = 7

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

module "webserver_cluster" {
  source = "../../../../modules/services/webserver-cluster"

  cluster_name = "webservers-prod"
  environment  = "production"
  app_version  = "v1"

  min_size = 2
  max_size = 6

  # Tell instances to fetch the secret from Secrets Manager at boot
  secret_source = "secretsmanager"
  secret_ref    = module.db_password_secret.secret_arn

  # Grant the instance role permission to read the secret
  secret_policy_arns = [module.db_password_secret.read_policy_arn]

  custom_tags = {
    Owner      = "platform-team"
    CostCenter = "prod-001"
  }
}

output "alb_dns_name" {
  value       = module.webserver_cluster.alb_dns_name
  description = "ALB DNS name"
}

output "asg_name" {
  value       = module.webserver_cluster.asg_name
  description = "ASG name"
}

output "secret_arn" {
  value       = module.db_password_secret.secret_arn
  description = "Secrets Manager ARN — pass to instances, not the value"
}
