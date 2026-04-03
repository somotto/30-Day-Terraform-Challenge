terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

module "state_bucket" {
  source = "../../modules/state-bucket"

  bucket_name         = var.state_bucket_name
  dynamodb_table_name = var.dynamodb_table_name
  environment         = "production"
  project_name        = "terraform-challenge"
  team_name           = "platform-team"
}

output "state_bucket_name" {
  value       = module.state_bucket.bucket_name
  description = "Copy this into your backend blocks: bucket = \"<value>\""
}

output "dynamodb_table_name" {
  value       = module.state_bucket.dynamodb_table_name
  description = "Copy this into your backend blocks: dynamodb_table = \"<value>\""
}
