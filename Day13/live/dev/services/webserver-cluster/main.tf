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

# SSM SecureString — value comes from TF_VAR_db_password, never written to
# any .tf file. The instance fetches it at boot via its IAM role.

variable "db_password" {
  description = "DB password injected via TF_VAR_db_password env var"
  type        = string
  sensitive   = true
}

module "db_password_param" {
  source = "../../../../modules/ssm-parameter"

  parameter_name  = "/webservers-dev/db_password"
  description     = "Dev DB password — fetched by instances at boot"
  parameter_value = var.db_password

  tags = {
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

module "webserver_cluster" {
  source = "../../../../modules/services/webserver-cluster"

  cluster_name = "webservers-dev"
  environment  = "dev"
  app_version  = "v1"

  min_size = 2
  max_size = 4

  # Tell instances to fetch the secret from SSM at boot
  secret_source = "ssm"
  secret_ref    = module.db_password_param.parameter_name

  # Grant the instance role permission to read the parameter
  secret_policy_arns = [module.db_password_param.read_policy_arn]

  custom_tags = {
    Owner = "dev-team"
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

output "ssm_parameter_name" {
  value       = module.db_password_param.parameter_name
  description = "SSM parameter path — pass to instances, not the value"
}
