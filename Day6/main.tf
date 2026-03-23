#terraform {
#   backend "s3" {
#     bucket         = "day6-demo-bucket"
#     key            = "global/s3/terraform.tfstate"
#     region         = "us-east-1"
#     dynamodb_table = "terraform-state-locks"
#     encrypt        = true
#  }
#}

provider "aws" {
  region = var.region
}

# Simple S3 bucket used to observe local state before migrating to remote
resource "aws_s3_bucket" "demo" {
  bucket        = var.bucket_name

  tags = {
    Name        = "day6-demo-bucket"
    Environment = "learning"
  }
}
