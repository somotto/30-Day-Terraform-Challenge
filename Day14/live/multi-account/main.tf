terraform {
  required_version = ">= 1.0.0"

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
}

# Production account provider
provider "aws" {
  alias  = "production"
  region = "us-east-1"

  assume_role {
    role_arn     = var.production_role_arn
    session_name = "terraform-day14-production"
  }
}

# Staging account provider
provider "aws" {
  alias  = "staging"
  region = "us-east-1"

  assume_role {
    role_arn     = var.staging_role_arn
    session_name = "terraform-day14-staging"
  }
}

resource "random_id" "suffix" {
  byte_length = 4
}

module "production_bucket" {
  source = "../../modules/s3-bucket"

  providers = {
    aws = aws.production
  }

  bucket_name        = "day14-production-${random_id.suffix.hex}"
  environment        = "production"
  versioning_enabled = true

  tags = { Account = "production" }
}


module "staging_bucket" {
  source = "../../modules/s3-bucket"

  providers = {
    aws = aws.staging
  }

  bucket_name        = "day14-staging-${random_id.suffix.hex}"
  environment        = "staging"
  versioning_enabled = false

  tags = { Account = "staging" }
}
