terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "local" {}
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name used in resource naming and tags."
  type        = string
  default     = "dev"
}

resource "aws_ssm_parameter" "cloud_demo" {
  name        = "/day19/lab1/terraform-cloud-demo"
  type        = "String"
  value       = "managed-by-terraform-cloud"
  description = "Day19 Lab 1: resource managed via Terraform Cloud backend"

  tags = {
    ManagedBy   = "terraform"
    Environment = var.environment
    Lab         = "day19-terraform-cloud"
    Day         = "19"
  }
}

resource "aws_s3_bucket" "cloud_demo" {
  bucket = "day19-cloud-demo-${var.environment}-${data.aws_caller_identity.current.account_id}"

  tags = {
    ManagedBy   = "terraform"
    Environment = var.environment
    Lab         = "day19-terraform-cloud"
    Day         = "19"
  }
}

resource "aws_s3_bucket_public_access_block" "cloud_demo" {
  bucket                  = aws_s3_bucket.cloud_demo.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_caller_identity" "current" {}

output "ssm_parameter_name" {
  value       = aws_ssm_parameter.cloud_demo.name
  description = "SSM parameter managed by Terraform Cloud."
}

output "bucket_name" {
  value       = aws_s3_bucket.cloud_demo.bucket
  description = "S3 bucket managed by Terraform Cloud."
}

output "account_id" {
  value       = data.aws_caller_identity.current.account_id
  description = "AWS account ID — visible in Terraform Cloud run output."
}
