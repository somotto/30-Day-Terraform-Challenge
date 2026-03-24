terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # App layer stores its own state separately from the network/env layer
  backend "s3" {
    bucket       = "day7-terraform-state-2026"
    key          = "environments/app/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
