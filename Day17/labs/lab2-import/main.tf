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

# Replace this bucket name with your actual pre-existing bucket name
variable "bucket_name" {
  description = "Name of the pre-existing S3 bucket to import."
  type        = string
  default     = "day17-import-lab-REPLACE-WITH-ACCOUNT-ID-us-east-1"
}

resource "aws_s3_bucket" "imported" {
  bucket = var.bucket_name

  tags = {
    ManagedBy   = "terraform"
    Environment = "dev"
    Lab         = "day17-import"
    CreatedBy   = "manual"
  }
}

resource "aws_s3_bucket_public_access_block" "imported" {
  bucket                  = aws_s3_bucket.imported.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

output "bucket_name" {
  value       = aws_s3_bucket.imported.bucket
  description = "Imported bucket name."
}

output "bucket_arn" {
  value       = aws_s3_bucket.imported.arn
  description = "Imported bucket ARN."
}
