terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # STEP 1: Start with local state — no backend block.
  # After running terraform apply once, you will have a local terraform.tfstate file.
  #
  # STEP 2: Uncomment the backend block below, fill in your bucket name,
  # then run: terraform init -migrate-state
  # STEP 3: Verify migration by running: terraform state list
  # The output should be identical to what you saw with local state.
  # The local terraform.tfstate file will now be empty (state is in S3).

  # backend "s3" {
  #   bucket         = "YOUR-STATE-BUCKET-NAME"   # from Day16 bootstrap output
  #   key            = "day17/lab1/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "terraform-state-lock"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = "us-east-1"
}

# A simple SSM parameter — cheap, fast to create, easy to verify.
resource "aws_ssm_parameter" "migration_demo" {
  name        = "/day17/lab1/migration-demo"
  type        = "String"
  value       = "state-migration-test-value"
  description = "Day17 Lab 1: demonstrates state migration from local to S3 backend"

  tags = {
    ManagedBy   = "terraform"
    Environment = "dev"
    Lab         = "day17-state-migration"
  }
}

output "parameter_name" {
  value       = aws_ssm_parameter.migration_demo.name
  description = "SSM parameter name — verify this exists in AWS Console after apply."
}

output "parameter_arn" {
  value       = aws_ssm_parameter.migration_demo.arn
  description = "SSM parameter ARN."
}
