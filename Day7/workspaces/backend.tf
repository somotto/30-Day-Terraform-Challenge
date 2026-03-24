terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Workspaces automatically prefix the key with the workspace name:
  # env:/dev/workspaces/terraform.tfstate
  # env:/staging/workspaces/terraform.tfstate
  # env:/production/workspaces/terraform.tfstate
  # use_lockfile = true uses S3 native locking (replaces deprecated dynamodb_table)

  backend "s3" {
    bucket       = "day7-terraform-state-2026"
    key          = "workspaces/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
