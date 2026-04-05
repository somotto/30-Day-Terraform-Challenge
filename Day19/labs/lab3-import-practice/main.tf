terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  #
  # backend "s3" {
  #   bucket         = "YOUR-STATE-BUCKET-NAME(day16bucket)"
  #   key            = "day19/lab3/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "terraform-state-lock"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = "us-east-1"
}

variable "bucket_name" {
  description = "Name of the pre-existing S3 bucket to import."
  type        = string
  default     = "day19-import-practice-REPLACE-WITH-ACCOUNT-ID-us-east-1"
}

resource "aws_s3_bucket" "existing_logs" {
  bucket = var.bucket_name

  tags = {
    ManagedBy   = "terraform"
    Environment = "dev"
    CreatedBy   = "manual"
    Lab         = "day19-import-practice"
    Day         = "19"
  }
}

resource "aws_s3_bucket_public_access_block" "existing_logs" {
  bucket                  = aws_s3_bucket.existing_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Uncomment this block instead of running `terraform import` on the CLI.
# This approach is reproducible and reviewable in pull requests.
#
# import {
#   to = aws_s3_bucket.existing_logs
#   id = var.bucket_name
# }

output "bucket_name" {
  value       = aws_s3_bucket.existing_logs.bucket
  description = "Imported bucket name — now managed by Terraform."
}

output "bucket_arn" {
  value       = aws_s3_bucket.existing_logs.arn
  description = "Imported bucket ARN."
}
